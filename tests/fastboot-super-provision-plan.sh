#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Original liblp phase/restart fixtures; sparse files, no devices or compilation.
set -Eeuo pipefail
export LC_ALL=C
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/image/fastboot-singleboot-layout.sh
# shellcheck disable=SC1091
source "$root/src/image/fastboot-singleboot-layout.sh"
planner=$root/src/image/plan-super-provision.sh
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
fastboot_super_layout 4294967296 seed > "$work/seed.json"
make_phase() {
    local capacity=$1 phase=$2 output=$3 plan group swap rescue usable
    plan=$(fastboot_super_layout "$capacity" "$phase")
    group=$(jq -er .group.name <<< "$plan")
    swap=$(jq -er '.partitions[0].bytes' <<< "$plan")
    rescue=$(jq -er '.partitions[1].bytes' <<< "$plan")
    usable=$(jq -er .usable_payload_bytes <<< "$plan")
    lpmake --device-size "$capacity" --super-name super --alignment 1048576 \
        --metadata-size 65536 --metadata-slots 3 --group "$group:$usable" \
        --partition "system_b:none:$rescue:$group" --partition "system_a:none:$swap:$group" \
        --output "$work/metadata.img" > /dev/null 2> "$work/tool.log"
    truncate -s 8589934592 "$output"
    lpflash "$output" "$work/metadata.img" > /dev/null 2> "$work/tool.log"
    (( $(stat -c %b "$output") * 512 <= 1048576 ))
}
copy_slot() {
    local input=$1 output=$2 slot=$3 block
    for block in "$((3 + slot * 16))" "$((51 + slot * 16))"; do
        dd if="$input" of="$output" bs=4096 skip="$block" seek="$block" count=16 conv=notrunc status=none
    done
}
check() {
    TMPDIR="$work" bash "$planner" "$work/seed.json" "$1" > "$work/result.json"
    jq -e --arg action "$2" --argjson initialize "$3" '.action==$action and
      .may_initialize_swap==$initialize and (.rescue_payload_relocation_required|not) and
      .seed_layout.partitions[1].start_byte==.target_layout.partitions[1].start_byte and
      .target_layout.super_bytes==8589934592 and (.device_write_executed|not)' "$work/result.json" >/dev/null
}
reject() {
    if TMPDIR="$work" bash "$planner" "$work/seed.json" "$1" > "$work/refused.json" 2> "$work/refused.log"; then exit 1; fi
    [[ ! -s $work/refused.json ]]
}
make_phase 4294967296 seed "$work/initial.raw"
make_phase 8589934592 growing "$work/growing.raw"
make_phase 8589934592 ready "$work/ready.raw"
check "$work/initial.raw" grow-fresh-seed true
cp --sparse=always "$work/initial.raw" "$work/mixed.raw"
copy_slot "$work/growing.raw" "$work/mixed.raw" 2
check "$work/mixed.raw" grow-fresh-seed true
check "$work/growing.raw" grow-fresh-seed true
cp --sparse=always "$work/growing.raw" "$work/mixed.raw"
copy_slot "$work/ready.raw" "$work/mixed.raw" 0
check "$work/mixed.raw" finish-ready-metadata false
check "$work/ready.raw" verify-ready false
cp --sparse=always "$work/initial.raw" "$work/conflict.raw"
copy_slot "$work/ready.raw" "$work/conflict.raw" 2
reject "$work/conflict.raw"
grep -q 'phases conflict' "$work/refused.log"
cp --sparse=always "$work/ready.raw" "$work/damaged.raw"
for offset in 143360 339968; do printf '\000' | dd of="$work/damaged.raw" bs=1 seek="$offset" conv=notrunc status=none; done
check "$work/damaged.raw" finish-ready-metadata false
truncate -s 8589934592 "$work/empty.raw"
reject "$work/empty.raw"
# A valid foreign slot is not a torn transaction and must never be repaired.
lpmake --device-size 8589934592 --super-name super --alignment 1048576 \
    --metadata-size 65536 --metadata-slots 3 --group android:8588886016 \
    --partition system_b:none:1718616064:android --partition system_a:none:6870269952:android \
    --output "$work/metadata.img" >/dev/null 2> "$work/tool.log"
truncate -s 8589934592 "$work/foreign.raw"
lpflash "$work/foreign.raw" "$work/metadata.img" >/dev/null 2> "$work/tool.log"
copy_slot "$work/foreign.raw" "$work/damaged.raw" 2
reject "$work/damaged.raw"
grep -q 'foreign valid layout' "$work/refused.log"
printf 'Original-tool seed growth, mixed-phase restart, ready-only metadata completion, corrupt-copy and previous/foreign-installation refusals passed.\n'
