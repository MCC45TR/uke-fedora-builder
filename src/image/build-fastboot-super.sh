#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Host/Actions assembly only. Inputs/output are regular files, never devices.
set -Eeuo pipefail
export LC_ALL=C
umask 077
[[ $# == 3 ]] || {
    printf 'Usage: %s SUPER_LAYOUT_JSON RESCUE_RAW_EXT4 NEW_OUTPUT\n' "${0##*/}" >&2
    exit 2
}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
# shellcheck source=fastboot-singleboot-layout.sh
# shellcheck disable=SC1091
source "$root/src/image/fastboot-singleboot-layout.sh"
[[ -f $1 && ! -L $1 && -f $2 && ! -L $2 && ! -e $3 && ! -L $3 ]]
layout_file=$(realpath "$1")
rescue_input=$(realpath "$2")
output=$(realpath -m "$3")
for tool in lpmake lpdump lpunpack simg2img mkswap blkid e2fsck resize2fs e2label dumpe2fs jq; do
    command -v "$tool" >/dev/null
done
capacity=$(jq -er .super_bytes "$layout_file")
phase=$(jq -er .phase "$layout_file")
layout=$(fastboot_super_layout "$capacity" "$phase")
group=$(jq -er .group.name <<< "$layout")
((capacity % 4096 == 0)) || {
    printf 'Super capacity must be aligned to the 4096-byte sparse block.\n' >&2
    exit 1
}
[[ $(jq -Sc . "$layout_file") == "$(jq -Sc . <<< "$layout")" ]] || {
    printf 'Layout differs from the capacity-derived 80/20 contract.\n' >&2
    exit 1
}
[[ $(blkid -p -s TYPE -o value "$rescue_input") == ext4 ]]
swap_bytes=$(jq -er '.partitions[0].bytes' <<< "$layout")
rescue_bytes=$(jq -er '.partitions[1].bytes' <<< "$layout")
usable=$(jq -er .usable_payload_bytes <<< "$layout")
(( $(stat -c %s "$rescue_input") <= rescue_bytes )) || {
    printf 'Rescue input exceeds the allocated logical partition.\n' >&2
    exit 1
}
parent=$(dirname "$output")
[[ -d $parent ]]
available=$(df -Pk "$parent" | awk 'NR==2 {print $4}')
free_inodes=$(df -Pi "$parent" | awk 'NR==2 {print $4}')
[[ $free_inodes =~ ^[0-9]+$ ]] && ((free_inodes >= 64))
# Raw source, sparse output and one-at-a-time decoder/extraction readback,
# conservatively charging full logical sizes even where holes save storage.
required_kib=$(((capacity * 4 + 2147483648 + 1023) / 1024))
if [[ ! $available =~ ^[0-9]+$ ]] || ((available < required_kib)); then
    printf 'Super assembly needs %s KiB free including a 2-GiB reserve.\n' "$required_kib" >&2
    exit 1
fi
mkdir -m700 "$output"
work=$(mktemp -d "$output/.work.XXXXXXXX")
cleanup() {
    local status=$?
    trap - EXIT
    if ((status != 0)); then
        for log in "$work/"*.log; do
            [[ ! -f $log ]] || tail -n 20 -- "$log" >&2
        done
    fi
    rm -rf -- "$work"
    if ((status != 0)); then rm -rf -- "$output"; fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
jq -M . <<< "$layout" > "$output/super-layout.json"
truncate -s "$swap_bytes" "$work/swap.raw"
mkswap --pagesize 4096 --label linux_swap "$work/swap.raw" > "$work/mkswap.log"
[[ $(blkid -p -s TYPE -o value "$work/swap.raw") == swap ]]
# Linux swap v1 last_page is a little-endian u32 at byte 1028. Read bytes
# explicitly so this check does not depend on the host's endianness.
read -r b0 b1 b2 b3 < <(od -An -v -j1028 -N4 -tu1 "$work/swap.raw")
last_page=$((b0 + (b1 << 8) + (b2 << 16) + (b3 << 24)))
(((last_page + 1) * 4096 == swap_bytes))
cp --reflink=auto --sparse=always -- "$rescue_input" "$work/rescue.raw"
e2fsck -fn "$work/rescue.raw" > "$work/rescue-check.log" 2>&1
truncate -s "$rescue_bytes" "$work/rescue.raw"
resize2fs "$work/rescue.raw" > "$work/rescue-resize.log" 2>&1
e2label "$work/rescue.raw" FEDORA_RESCUE
e2fsck -fn "$work/rescue.raw" >> "$work/rescue-check.log" 2>&1
[[ $(blkid -p -s LABEL -o value "$work/rescue.raw") == FEDORA_RESCUE ]]
dumpe2fs -h "$work/rescue.raw" > "$output/rescue-superblock.txt" 2>/dev/null
rescue_blocks=$(awk '/^Block count:/ {print $3}' "$output/rescue-superblock.txt")
rescue_block_size=$(awk '/^Block size:/ {print $3}' "$output/rescue-superblock.txt")
[[ $rescue_blocks =~ ^[1-9][0-9]*$ && $rescue_block_size == 4096 ]]
((rescue_blocks * rescue_block_size == rescue_bytes))
swap_hash=$(sha256sum "$work/swap.raw" | cut -d ' ' -f1)
rescue_hash=$(sha256sum "$work/rescue.raw" | cut -d ' ' -f1)
lpmake --device-size "$capacity" --super-name super --alignment 1048576 \
    --metadata-size 65536 --metadata-slots 3 --group "$group:$usable" \
    --partition "system_b:none:$rescue_bytes:$group" \
    --partition "system_a:none:$swap_bytes:$group" \
    --image "system_a=$work/swap.raw" --image "system_b=$work/rescue.raw" \
    --sparse --output "$output/super.img"
[[ -f $output/super.img && ! -L $output/super.img ]]
simg2img "$output/super.img" "$work/readback.raw"
[[ $(stat -c %s "$work/readback.raw") == "$capacity" ]]
bash "$root/src/image/inspect-fastboot-super.sh" --image "$capacity" "$work/readback.raw" "$phase" > "$output/super-topology.json"
for slot in 0 1 2; do
    lpdump --json --slot="$slot" "$work/readback.raw" > "$output/lp-slot-$slot.json"
    jq -e --argjson capacity "$capacity" --argjson swap "$swap_bytes" --argjson rescue "$rescue_bytes" \
        '(.block_devices | length) == 1 and .block_devices[0].name == "super" and
         (.block_devices[0].size | tonumber) == $capacity and (.partitions | length) == 2 and
         ([.partitions[] | select(.name == "system_a") | .size | tonumber] == [$swap]) and
         ([.partitions[] | select(.name == "system_b") | .size | tonumber] == [$rescue])' \
        "$output/lp-slot-$slot.json" >/dev/null
done
mkdir "$work/extracted"
lpunpack -p system_a "$work/readback.raw" "$work/extracted"
[[ $(sha256sum "$work/extracted/system_a.img" | cut -d ' ' -f1) == "$swap_hash" ]]
[[ $(blkid -p -s LABEL -o value "$work/extracted/system_a.img") == linux_swap ]]
rm -- "$work/extracted/system_a.img" "$work/swap.raw"
lpunpack -p system_b "$work/readback.raw" "$work/extracted"
[[ $(sha256sum "$work/extracted/system_b.img" | cut -d ' ' -f1) == "$rescue_hash" ]]
e2fsck -fn "$work/extracted/system_b.img" > "$output/rescue-filesystem-check.txt" 2>&1
cp -- "$work/mkswap.log" "$output/mkswap.txt"
jq -M -n --arg hash "$(sha256sum "$output/super.img" | cut -d ' ' -f1)" \
    --arg swap "$swap_hash" --arg rescue "$rescue_hash" --argjson layout "$layout" \
    '{schema_version:1,super_sparse_sha256:$hash,swap_raw_sha256:$swap,rescue_raw_sha256:$rescue,
      layout:$layout,liblp_three_slot_readback:true,independent_aosp_decode:true,
      both_logical_payloads_byte_matched:true,rescue_full_capacity:true,swap_full_capacity:true,
      container_assembled:true,installable_archive_created:false,
      rescue_os_qualified:false,secure_boot_qualified:false,device_write_executed:false}' > "$output/super-composition.json"
(cd "$output"; sha256sum super.img super-layout.json super-topology.json super-composition.json lp-slot-?.json > SHA256SUMS)
printf 'Constructed and decoded %s with full-size swap/rescue payload byte checks; boot/OS/security admission remains separate.\n' "$output/super.img"
