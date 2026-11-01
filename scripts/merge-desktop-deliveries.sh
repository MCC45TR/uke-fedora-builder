#!/usr/bin/env bash
# Join four independent validated deliveries. No publication or image mutation.
set -Eeuo pipefail
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
output=${1:?Expected new output directory} core=${2:?Expected core hash}
shift 2
[[ ( $# == 4 || ( $# == 3 && ${UKE_ALLOW_MISSING_CUTEFISH:-0} == 1 ) ) && ! -e $output && ! -L $output && $core =~ ^[0-9a-f]{64}$ ]]
policy=complete
[[ ${UKE_ALLOW_MISSING_CUTEFISH:-0} != 1 ]] || policy=cutefish-optional
layout=$builder/src/public/release-layout.sh
mkdir -p "$output/assets" "$output/receipts/images" "$output/receipts/builds" "$output/receipts/reused"
for input in "$@"; do
    bash "$layout" verify "$input"
    manifests=("$input/receipts/images/"*.json)
    [[ ${#manifests[@]} == 1 ]]
    manifest=${manifests[0]} desktop=$(jq -er .desktop "${manifests[0]}")
    jq -e --arg core "$core" '.shared_core_sha256==$core and .desktop_isolation_audited==true and .previous_desktop_image_input==false' "$manifest" >/dev/null
    case $desktop in kde|gnome|cutefish|nextkde) ;; *) exit 1;; esac
    [[ ! -e $output/receipts/SOURCE-$desktop.txt ]]
    [[ -f $input/receipts/SOURCE.txt && ! -L $input/receipts/SOURCE.txt ]]
    if [[ -f $output/receipts/layout.json ]]; then
        cmp "$input/receipts/layout.json" "$output/receipts/layout.json"
        cmp "$input/receipts/cohort.json" "$output/receipts/cohort.json"
    else
        cp "$input/receipts/layout.json" "$input/receipts/cohort.json" "$output/receipts/"
    fi
    for asset in "$input/assets/"*; do
        name=${asset##*/}
        if [[ -e $output/assets/$name ]]; then cmp "$asset" "$output/assets/$name"
        else cp "$asset" "$output/assets/$name"; fi
    done
    name=${manifest##*/}
    [[ ! -e $output/receipts/images/$name ]]
    cp "$manifest" "$output/receipts/images/"
    cp -a "$input/receipts/builds/." "$output/receipts/builds/"
    cp "$input/receipts/SOURCE.txt" "$output/receipts/SOURCE-$desktop.txt"
    if [[ -f $input/receipts/REUSED-DESKTOP.json ]]; then cp "$input/receipts/REUSED-DESKTOP.json" "$output/receipts/reused/$desktop.json"; fi
done
bash "$layout" desktop-set "$output" "$core" "$policy"
bash "$layout" inventory "$output" > "$output/receipts/images.tsv"
bash "$layout" body "$output" "$output/receipts/images.tsv" > "$output/receipts/RELEASE.md"
jq -s --arg core "$core" '{desktop_set_validated:true,desktops:map(.desktop)|sort,shared_core_sha256:$core,shared_boot_files:1,root_image_files:length}' "$output/receipts/images/"*.json > "$output/receipts/desktop-set.json"
printf 'Merged independently validated desktops with one byte-identical boot; publication is a separate step.\n'
