#!/usr/bin/env bash
# Signed-payload identity fixtures; no downloads, RPM installation or compilation.
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/public/cohort.sh
# shellcheck disable=SC1091
source "$repo/src/public/cohort.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
root=$work/root abi=7.3.1-1010
bundle=$root/usr/lib/senemos/kernel-updates/$abi
source_dir=$root/usr/share/senemos/uke/$abi
mkdir -p "$root/usr/lib/modules/$abi" "$bundle" "$source_dir"
printf 'kernel_release=%s\n' "$abi" > "$bundle/manifest"
sha=$(printf 'a%.0s' {1..40})
printf '%s\n' "$sha" > "$source_dir/source-commit"
jq -n --arg sha "$sha" '{kernel_release:"7.3.1-1010",source_commit:$sha,
    upstream_version:"7.3.1",rpm_revision:"1010.1"}' > "$source_dir/source-composition.json"
[[ $(cohort_repository_release "$root" "$abi") == "$abi" ]]
[[ $(cohort_repository_release "$root" "$abi.1") == "$abi" ]]
reject() {
    if cohort_repository_release "$root" "$1" > "$work/refused" 2>&1; then
        echo "Incompatible kernel RPM/ABI accepted: $1" >&2; exit 1
    fi
}
for evr in 7.3.1-115 7.3.1-1011.1 7.3.0-1010.1 7.3.1-1010.2 7.3.1-1010.0 7.3.1-1010.1.1; do reject "$evr"; done
cp "$source_dir/source-composition.json" "$work/composition"
for expression in '.kernel_release="7.3.1-1011"' '.source_commit=("b"*40)' \
    '.upstream_version="7.3.0"' 'del(.rpm_revision)'; do
    jq "$expression" "$work/composition" > "$source_dir/source-composition.json"
    reject "$abi.1"
done
cp "$work/composition" "$source_dir/source-composition.json"
mkdir "$root/usr/lib/modules/7.3.1-115"; reject "$abi.1"; rmdir "$root/usr/lib/modules/7.3.1-115"
printf 'kernel_release=7.3.1-115\n' > "$bundle/manifest"; reject "$abi.1"
printf 'kernel_release=%s\n' "$abi" > "$bundle/manifest"
mv "$source_dir/source-composition.json" "$work/composition"
ln -s "$work/composition" "$source_dir/source-composition.json"; reject "$abi.1"
rm "$source_dir/source-composition.json"
reject "$abi.1"
mv "$work/composition" "$source_dir/source-composition.json"

jq -n --arg sha "$sha" '{builder_commit:$sha,kernel_commit:$sha,kernel_version:"7.3.1",
    kernel_profile:"normal",fedora_release:"rawhide",partition:"userdata",filesystem:"ext4",
    mode:"singleboot",target:"image"}' > "$work/request"
jq -n --arg sha "$sha" '{kernel_source_commit:$sha,kernel_version:"7.3.1",kernel_profile:"normal",
    kernel_family:"senemos-uke-linux-kernel-mainline",kernel_release:"7.3.1-1010",
    rpm_version_release:"7.3.1-1010.1",rpm_dist:".fc46",payload_sha256:("c"*64)}' > "$work/info"
jq -s '.[0]+.[1]' "$work/request" "$work/info" > "$work/manifest"
cohort_identity "$work/request" "$work/info" "$work/manifest"
for evr in 7.3.1-1011.1 7.3.0-1010.1 7.3.1-1010.0 7.3.1-1010.1.1; do
    jq --arg evr "$evr" '.rpm_version_release=$evr' "$work/info" > "$work/bad-info"
    jq -s '.[0]+.[1]' "$work/request" "$work/bad-info" > "$work/manifest"
    if cohort_identity "$work/request" "$work/bad-info" "$work/manifest"; then
        echo 'Invalid self-consistent RPM revision receipt accepted' >&2; exit 1
    fi
done
# The cumulative unstable family has a different ABI from its RPM EVR. It
# requires an explicit profile and signed composition even without repackaging.
root=$work/unstable-root
abi=7.3.3-26-unstable
bundle=$root/usr/lib/senemos/kernel-updates/$abi
source_dir=$root/usr/share/senemos/uke/$abi
mkdir -p "$root/usr/lib/modules/$abi" "$bundle" "$source_dir"
printf 'kernel_release=%s\n' "$abi" > "$bundle/manifest"
printf '%s\n' "$sha" > "$source_dir/source-commit"
jq -n --arg sha "$sha" '{kernel_release:"7.3.3-26-unstable",source_commit:$sha,
    upstream_version:"7.3.3",rpm_revision:"26"}' > "$source_dir/source-composition.json"
[[ $(cohort_repository_release "$root" 7.3.3-26 unstable) == "$abi" ]]
for profile in normal el2-require unknown; do
    if cohort_repository_release "$root" 7.3.3-26 "$profile" >/dev/null 2>&1; then exit 1; fi
done
if cohort_repository_release "$root" 7.3.3-27 unstable >/dev/null 2>&1; then exit 1; fi
cp "$source_dir/source-composition.json" "$work/unstable-composition"
for expression in '.source_commit=("b"*40)' '.kernel_release="7.3.3-26"' \
    '.rpm_revision="27"' '.upstream_version="7.3.2"' 'del(.rpm_revision)'; do
    jq "$expression" "$work/unstable-composition" > "$source_dir/source-composition.json"
    if cohort_repository_release "$root" 7.3.3-26 unstable >/dev/null 2>&1; then
        echo 'Unstable source/ABI mismatch accepted' >&2; exit 1
    fi
done
cp "$work/unstable-composition" "$source_dir/source-composition.json"
jq -n --arg sha "$sha" '{builder_commit:$sha,kernel_commit:$sha,kernel_version:"7.3.3",
    kernel_profile:"unstable",channel:"unstable",fedora_release:"rawhide",partition:"userdata",
    filesystem:"ext4",mode:"singleboot",target:"image"}' > "$work/request"
jq -n --arg sha "$sha" '{kernel_source_commit:$sha,kernel_version:"7.3.3",kernel_profile:"unstable",
    kernel_family:"senemos-uke-linux-kernel-mainline-unstable",kernel_release:"7.3.3-26-unstable",
    rpm_version_release:"7.3.3-26",rpm_dist:".fc46",payload_sha256:("c"*64)}' > "$work/info"
jq -s '.[0]+.[1]' "$work/request" "$work/info" > "$work/manifest"
cohort_identity "$work/request" "$work/info" "$work/manifest"
for expression in '.kernel_family="senemos-uke-linux-kernel-mainline"' \
    '.kernel_release="7.3.3-26"' '.rpm_version_release="7.3.3-27"' '.kernel_profile="normal"'; do
    jq "$expression" "$work/info" > "$work/bad-info"
    jq -s '.[0]+.[1]' "$work/request" "$work/bad-info" > "$work/manifest"
    if cohort_identity "$work/request" "$work/bad-info" "$work/manifest"; then exit 1; fi
done
jq '.channel="testing"' "$work/request" > "$work/wrong-channel"
jq -s '.[0]+.[1]' "$work/wrong-channel" "$work/info" > "$work/manifest"
if cohort_identity "$work/wrong-channel" "$work/info" "$work/manifest"; then exit 1; fi

root=$work/publication-root
abi=7.4.5-senemos
bundle=$root/usr/lib/senemos/kernel-updates/$abi
source_dir=$root/usr/share/senemos/uke/$abi
mkdir -p "$root/usr/lib/modules/$abi" "$bundle" "$source_dir"
printf 'kernel_release=%s\n' "$abi" > "$bundle/manifest"
printf '%s\n' "$sha" > "$source_dir/source-commit"
jq -n --arg sha "$sha" '{
    kernel_release:"7.4.5-senemos",source_commit:$sha,upstream_version:"7.3.5",rpm_revision:"12",
    publication:{family:"senemos-uke-linux-kernel-mainline",parent_copr_build:11360041,
                 source_kernel_release:"7.3.5-12-unstable"}}' > "$work/publication-composition"
cp "$work/publication-composition" "$source_dir/source-composition.json"
[[ $(cohort_repository_release "$root" 7.3.5-12) == "$abi" ]]
reject 7.3.5-13
reject 7.4.5-12
bad_compositions=(
    'del(.publication)'
    '.publication.source_kernel_release="7.3.5-13-unstable"'
    '.publication.family="senemos-uke-linux-kernel-mainline-unstable"'
    '.publication.parent_copr_build=0'
)
for expression in "${bad_compositions[@]}"; do
    jq "$expression" "$work/publication-composition" > "$source_dir/source-composition.json"
    reject 7.3.5-12
done
jq '.channel="stable" | .kernel_version="7.3.5" | .kernel_profile="normal"' "$work/request" > "$work/normal-request"
jq '.kernel_version="7.3.5" | .kernel_profile="normal" | .kernel_family="senemos-uke-linux-kernel-mainline" |
    .kernel_release="7.4.5-senemos" | .rpm_version_release="7.3.5-12"' "$work/info" > "$work/normal-info"
jq -s '.[0]+.[1]' "$work/normal-request" "$work/normal-info" > "$work/manifest"
cohort_identity "$work/normal-request" "$work/normal-info" "$work/manifest"

family=senemos-uke-linux-kernel-mainline
evr=7.3.5-12.fc46
printf '%s\n' "$family-$evr.aarch64" "$family-core-$evr.aarch64" > "$work/inventory"
[[ $(cohort_kernel_components "$work/inventory" "$family" "$evr") == $'\n-core' ]]
printf '%s\n' "$family-modules-$evr.aarch64" >> "$work/inventory"
if cohort_kernel_components "$work/inventory" "$family" "$evr" >/dev/null 2>&1; then exit 1; fi
printf '%s\n' "$family-dtbs-$evr.aarch64" "$family-boot-$evr.aarch64" >> "$work/inventory"
[[ $(cohort_kernel_components "$work/inventory" "$family" "$evr") == $'\n-core\n-modules\n-dtbs\n-boot' ]]
echo 'Normal and cumulative unstable RPM/ABI identities, source proofs, family and channel refusal passed'
