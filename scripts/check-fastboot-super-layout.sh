#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Validate calculated capacities against original liblp, without payloads.
set -Eeuo pipefail
export LC_ALL=C
[[ $# == 1 ]] || { printf 'Usage: %s SUPER_BYTES\n' "${0##*/}" >&2; exit 2; }
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/image/fastboot-singleboot-layout.sh
# shellcheck disable=SC1091
source "$root/src/image/fastboot-singleboot-layout.sh"
for tool in lpmake lpdump jq; do command -v "$tool" >/dev/null; done
layout=$(fastboot_super_layout "$1")
work=$(mktemp -d /var/tmp/uke-liblp-check.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
swap=$(jq -er '.partitions[0].bytes' <<< "$layout")
rescue=$(jq -er '.partitions[1].bytes' <<< "$layout")
usable=$(jq -er .usable_payload_bytes <<< "$layout")
# Without -F, --sparse or --image lpmake writes only a tiny, nonflashable
# metadata fixture. Never produce an empty-but-flashable super image here.
lpmake --device-size "$1" --super-name super --alignment 1048576 \
    --metadata-size 65536 --metadata-slots 3 --group "uke_linux:$usable" \
    --partition "system_b:none:$rescue:uke_linux" \
    --partition "system_a:none:$swap:uke_linux" --output "$work/metadata.img"
[[ $(stat -c %s "$work/metadata.img") -le 1048576 ]]
# Compact metadata files contain one serialized description. Original lpdump
# ignores --slot for that file format; independent slot copies require a full
# raw container (tested separately by fastboot-super-inspection/composition).
lpdump --json "$work/metadata.img" > "$work/readback.json"
jq -e --argjson capacity "$1" --argjson swap "$swap" --argjson rescue "$rescue" \
        '(.block_devices | length) == 1 and .block_devices[0].name == "super" and
         (.block_devices[0].size | tonumber) == $capacity and
         (.partitions | length) == 2 and
         ([.partitions[] | select(.name == "system_a") | .size | tonumber] == [$swap]) and
         ([.partitions[] | select(.name == "system_b") | .size | tonumber] == [$rescue])' \
        "$work/readback.json" >/dev/null
jq -M -n --argjson layout "$layout" \
    '{schema_version:2,layout:$layout,original_liblp_metadata_description_readback:true,
      independent_slot_copies_verified:false,
      metadata_fixture_only:true,flashable_image_created:false,device_write_executed:false}'
