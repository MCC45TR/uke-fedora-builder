#!/usr/bin/bash
# Data-only capacity-derived installation plan. No image creation/device access.
set -Eeuo pipefail
[[ $# == 3 || $# == 4 ]] || {
    printf 'Usage: %s SOURCE_COMPOSITION GEOMETRY_JSON NEW_OUTPUT [DDMMYY]\n' "${0##*/}" >&2
    exit 2
}
composition=$(realpath "$1")
geometry=$(realpath "$2")
output=$(realpath -m "$3")
day=${4:-$(TZ=Europe/Istanbul date +%d%m%y)}
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
# shellcheck source=fastboot-singleboot-layout.sh
# shellcheck disable=SC1091
source "$repo/src/image/fastboot-singleboot-layout.sh"
archive=$(fastboot_install_name "$day")
[[ -f $composition && ! -L $composition && -f $geometry && ! -L $geometry && ! -e $output && ! -L $output ]]
jq -e '.kernel_release|test("^[0-9]+[.][0-9]+[.][0-9]+-[1-9][0-9]*-unstable$")' "$composition" >/dev/null
jq -e '.source_commit|test("^[a-f0-9]{40}$")' "$composition" >/dev/null
jq -e '.product == "uke" and (.partitions | type == "object") and
  ([.partitions.super,.partitions.userdata,.partitions.boot_a,.partitions.boot_b,
    .partitions.vendor_boot_a,.partitions.vendor_boot_b,.partitions.dtbo_a,.partitions.dtbo_b,
    .partitions.vbmeta_a,.partitions.vbmeta_b] |
    all(.[]; type == "number" and floor == . and . > 0 and . <= 2199023255552))' "$geometry" >/dev/null
layout=$(fastboot_super_layout "$(jq -er .partitions.super "$geometry")")
mkdir -m700 "$output"
trap 'status=$?; if ((status != 0)); then rm -rf -- "$output"; fi' EXIT
jq -n --argjson layout "$layout" '$layout' > "$output/super-layout.json"
jq --slurpfile source "$composition" \
   --slurpfile geometry "$geometry" --argjson layout "$layout" --arg archive "$archive" \
   --arg planner "$(git -C "$repo" rev-parse HEAD)" \
   --arg hash "$(sha256sum "$composition" | cut -d ' ' -f1)" \
   '. + {planner_commit:$planner,archive_name:$archive,measured_geometry:$geometry[0],
     resolved_super_layout:$layout,
     kernel:{release:$source[0].kernel_release,source_commit:$source[0].source_commit,composition_sha256:$hash},
     payloads_available:false,archive_created:false,
     kernel_encryption_in_full_candidate:($source[0].storage_encryption_enabled_in_full_candidate==true)}' \
   "$repo/configs/images/fastboot-update-uke.json" > "$output/release-plan.json"
printf 'require product=uke\n' > "$output/android-info.txt"
{
 printf 'version 1\n'
 jq -r '.payloads[]|"flash "+.partition+" "+.file' "$repo/configs/images/fastboot-update-uke.json"
} > "$output/fastboot-info.txt"
cp "$repo/docs/FASTBOOT-UPDATE-PREPARATION.md" "$output/README.md"
printf 'Planned %s: capacity-derived 80%% swap/20%% rescue, both boot cohorts, no /opt. No ZIP or device write.\n' "$archive"
