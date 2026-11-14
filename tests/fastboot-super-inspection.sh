#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Full raw liblp fixtures with less than 1 MiB allocated storage each.
# Unwritten logical payloads are sparse holes. No device or compilation.
set -Eeuo pipefail
export LC_ALL=C
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/image/fastboot-singleboot-layout.sh
# shellcheck disable=SC1091
source "$root/src/image/fastboot-singleboot-layout.sh"
inspector=$root/src/image/inspect-fastboot-super.sh
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
fixture() {
    local capacity=$1 output=$2
    shift 2
    lpmake --device-size "$capacity" --super-name super --alignment 1048576 \
        --metadata-size 65536 --metadata-slots 3 "$@" --force-full-image --sparse \
        --output "$work/intermediate.sparse" >/dev/null 2> "$work/lpmake.log"
    simg2img "$work/intermediate.sparse" "$output"
    [[ $(stat -c %s "$output") == "$capacity" ]]
    (( $(stat -c %b "$output") * 512 <= 1048576 ))
}
reject() {
    if TMPDIR="$work" bash "$inspector" --image "$1" "$2" > "$work/refusal.json" 2> "$work/refusal.log"; then
        printf 'Invalid super layout accepted: %s\n' "$2" >&2; exit 1
    fi
    [[ ! -s $work/refusal.json ]]
}
for capacity in 4294967296 8589934592 11274289152 12884901888; do
    plan=$(fastboot_super_layout "$capacity")
    swap=$(jq -er '.partitions[0].bytes' <<< "$plan")
    rescue=$(jq -er '.partitions[1].bytes' <<< "$plan")
    usable=$(jq -er .usable_payload_bytes <<< "$plan")
    fixture "$capacity" "$work/good.img" --group "uke_linux:$usable" \
        --partition "system_a:none:$swap:uke_linux" --partition "system_b:none:$rescue:uke_linux"
    TMPDIR="$work" bash "$inspector" --image "$capacity" "$work/good.img" > "$work/result.json"
    jq -e --argjson size "$capacity" '.three_slot_topology_verified and .layout.super_bytes == $size and
      .mappings[0].start_sector == 2048 and
      .mappings[0].start_sector + .mappings[0].sectors == .mappings[1].start_sector and
      ([.mappings[].sectors] | add) * 512 == .layout.usable_payload_bytes and
      (.metadata_authenticity_verified | not) and (.block_mapping_created | not)' "$work/result.json" >/dev/null
    reject "$((capacity + 1048576))" "$work/good.img"
done
# Same names and sizes with reversed allocation order must NOT map the expected
# offsets. A JSON-only verifier cannot detect this case.
fixture "$capacity" "$work/reversed.img" --group "uke_linux:$usable" \
    --partition "system_b:none:$rescue:uke_linux" --partition "system_a:none:$swap:uke_linux"
reject "$capacity" "$work/reversed.img"
# Keep valid original-tool checksums while replacing only slot 2 with the
# reversed layout. Slots 0/1 must not hide a conflicting third metadata view.
cp "$work/good.img" "$work/different-slot.img"
for block in 35 83; do
    dd if="$work/reversed.img" of="$work/different-slot.img" bs=4096 skip="$block" seek="$block" count=16 conv=notrunc status=none
done
reject "$capacity" "$work/different-slot.img"
grep -q 'slot 2' "$work/refusal.log"
# AOSP's redundant-copy recovery remains usable, but losing both copies of
# one slot is refused. These offsets belong to this fixture's checked geometry.
cp "$work/good.img" "$work/one-damaged-copy.img"
printf '\000' | dd of="$work/one-damaged-copy.img" bs=1 seek=143360 conv=notrunc status=none
TMPDIR="$work" bash "$inspector" --image "$capacity" "$work/one-damaged-copy.img" > "$work/result.json"
cp "$work/one-damaged-copy.img" "$work/two-damaged-copies.img"
printf '\000' | dd of="$work/two-damaged-copies.img" bs=1 seek=339968 conv=notrunc status=none
reject "$capacity" "$work/two-damaged-copies.img"
fixture "$capacity" "$work/readonly.img" --group "uke_linux:$usable" \
    --partition "system_a:readonly:$swap:uke_linux" --partition "system_b:none:$rescue:uke_linux"
reject "$capacity" "$work/readonly.img"
fixture "$capacity" "$work/foreign.img" --group "android:$usable" \
    --partition "system_a:none:$swap:android" --partition "system_b:none:$rescue:android"
reject "$capacity" "$work/foreign.img"
fixture "$capacity" "$work/virtual-ab.img" --virtual-ab --group "uke_linux:$usable" \
    --partition "system_a:none:$swap:uke_linux" --partition "system_b:none:$rescue:uke_linux"
reject "$capacity" "$work/virtual-ab.img"
ln -s good.img "$work/link.img"
reject "$capacity" "$work/link.img"
printf 'not liblp\n' > "$work/garbage.img"
reject "$capacity" "$work/garbage.img"
if bash "$inspector" --block "$work/good.img" >/dev/null 2>&1; then exit 1; fi
printf 'Original liblp topology, multiple capacities, reversed/cross-slot extents, redundancy recovery, attributes, groups, virtual A/B and wrong-input refusals passed.\n'
