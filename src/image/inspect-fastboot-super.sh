#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Read-only liblp admission for the image producer and early rescue mapper.
# This checks metadata geometry, not cryptographic authenticity or an OS boot.
set -Eeuo pipefail
export LC_ALL=C
umask 077
here=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=fastboot-singleboot-layout.sh
# shellcheck disable=SC1091
source "$here/fastboot-singleboot-layout.sh"
fail() { printf 'UKE_SUPER_REJECTED: %s\n' "$*" >&2; exit 1; }
phase=ready
slot_selection=all
case ${1:-} in
    --image)
        [[ $# -ge 3 && $# -le 5 && -f $3 && ! -L $3 ]] || fail 'expected capacity and a regular metadata/image file'
        capacity=$2
        device=$(realpath "$3")
        phase=${4:-ready}
        slot_selection=${5:-all}
        ;;
    --block)
        [[ $# == 2 ]] || fail 'expected one block device'
        device=$(readlink -e -- "$2")
        [[ -b $device ]] || fail 'input is not a block device'
        # Keep a reference open while liblp validates this device.
        exec 3< "$device"
        capacity=$(blockdev --getsize64 /proc/self/fd/3)
        device=/proc/self/fd/3
        ;;
    *) fail 'usage: inspect-fastboot-super.sh --image SUPER_BYTES FILE | --block DEVICE';;
esac
[[ $slot_selection == all || $slot_selection =~ ^[012]$ ]] || fail 'invalid slot selection'
layout=$(fastboot_super_layout "$capacity" "$phase") || fail 'unsupported capacity or phase'
group=$(jq -er .group.name <<< "$layout")
((capacity % 4096 == 0)) || fail 'capacity is not 4096-byte aligned'
if [[ $1 == --image ]]; then
    [[ $(stat -c %s "$device") == "$capacity" ]] || fail 'full raw image required; compact metadata files do not contain independent slot copies'
    exec 3< "$device"
    device=/proc/self/fd/3
fi
cmp -s -n 4096 /dev/zero "$device" || fail 'raw super reserved prefix is not zero; compact/sparse input is not a physical layout'
swap=$(jq -er '.partitions[0].bytes' <<< "$layout")
rescue=$(jq -er '.partitions[1].bytes' <<< "$layout")
usable=$(jq -er .usable_payload_bytes <<< "$layout")
first=$(jq -er .first_logical_byte <<< "$layout")
swap_sectors=$((swap / 512))
rescue_sectors=$((rescue / 512))
rescue_start=$((first / 512))
swap_start=$((rescue_start + rescue_sectors))
end=$((swap_start + swap_sectors))
((end * 512 <= capacity)) || fail 'logical extent exceeds the device'
work=$(mktemp -d "${TMPDIR:-/tmp}/uke-super-inspect.XXXXXXXX")
cleanup() { find "$work" -depth -delete; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ $1 == --image ]]; then
    # Freeze the bounded metadata prefix, retaining real slot offsets and
    # logical capacity as sparse holes. Original lpdump reads the liblp tables;
    # payload bytes are checked separately by the producer. This snapshot does
    # not authenticate payloads or relieve the producer's full-image cache use.
    truncate -s "$capacity" "$work/topology.raw"
    dd if="$device" of="$work/topology.raw" bs=1048576 count=1 iflag=fullblock conv=notrunc status=none
    device=$work/topology.raw
fi
# Keep parsing and output bounded even for malformed foreign geometry.
dump() (
    ulimit -v 262144
    ulimit -f 128
    timeout --signal=TERM --kill-after=1s 5s lpdump "$@" "$device"
)
cat > "$work/expected.txt" <<TEXT
Metadata version: 10.0
Metadata size: 440 bytes
Metadata max size: 65536 bytes
Metadata slot count: 3
Header flags: none
Partition table:
------------------------
  Name: system_b
  Group: $group
  Attributes: none
  Extents:
    0 .. $((rescue_sectors - 1)) linear super $rescue_start
------------------------
  Name: system_a
  Group: $group
  Attributes: none
  Extents:
    0 .. $((swap_sectors - 1)) linear super $swap_start
------------------------
Super partition layout:
------------------------
super: $rescue_start .. $swap_start: system_b ($rescue_sectors sectors)
super: $swap_start .. $end: system_a ($swap_sectors sectors)
------------------------
Block device table:
------------------------
  Partition name: super
  First sector: $rescue_start
  Size: $capacity bytes
  Flags: none
------------------------
Group table:
------------------------
  Name: default
  Maximum size: 0 bytes
  Flags: none
------------------------
  Name: $group
  Maximum size: $usable bytes
  Flags: none
------------------------
TEXT
slots=(0 1 2)
[[ $slot_selection == all ]] || slots=("$slot_selection")
for slot in "${slots[@]}"; do
    if dump --json --slot="$slot" > "$work/slot.json" 2> "$work/diagnostic"; then :; else
        result=$?
        tail -n 4 "$work/diagnostic" >&2
        fail "cannot decode metadata slot $slot (parser exit $result)"
    fi
    jq -e --argjson capacity "$capacity" --argjson swap "$swap" --argjson rescue "$rescue" --argjson usable "$usable" --arg group "$group" '
      (.block_devices | length) == 1 and .block_devices[0].name == "super" and
      (.block_devices[0].size | tonumber) == $capacity and
      (.block_devices[0].block_size | tonumber) == 4096 and
      (.block_devices[0].alignment | tonumber) == 1048576 and
      (.partitions | length) == 2 and all(.partitions[]; .is_dynamic and .group_name == $group) and
      ([.partitions[] | select(.name == "system_a") | .size | tonumber] == [$swap]) and
      ([.partitions[] | select(.name == "system_b") | .size | tonumber] == [$rescue]) and
      (.groups | length) == 2 and
      ([.groups[] | select(.name == $group) | .maximum_size | tonumber] == [$usable]) and
      ([.groups[] | select(.name == "default") | (.maximum_size // 0) | tonumber] == [0])' \
      "$work/slot.json" >/dev/null || fail "slot $slot does not describe the two Linux roles"
    if dump --slot="$slot" > "$work/slot.txt" 2> "$work/diagnostic"; then :; else
        result=$?
        tail -n 4 "$work/diagnostic" >&2
        fail "cannot read extents in slot $slot (parser exit $result)"
    fi
    # Original lpdump's JSON omits extents/attributes. Require the complete
    # producer format as well; any parser/version drift fails closed.
    sed -e '/^Slot [012]:$/d' -e 's/[[:blank:]]*$//' -e '/^$/d' "$work/slot.txt" > "$work/normalized.txt"
    cmp -s "$work/expected.txt" "$work/normalized.txt" || fail "slot $slot has unexpected extents, attributes or geometry"
done
[[ $(dump --dump-metadata-size 2> "$work/diagnostic") == "$first" ]] || fail 'metadata reservation differs'
jq -M -n --argjson layout "$layout" --argjson swap_start "$swap_start" --argjson rescue_start "$rescue_start" \
    --argjson swap_sectors "$swap_sectors" --argjson rescue_sectors "$rescue_sectors" \
    --argjson slots "$(printf '%s\n' "${slots[@]}" | jq -s .)" \
    '{schema_version:2,layout:$layout,verified_metadata_slots:$slots,three_slot_topology_verified:($slots|length==3),
      mappings:[{role:"swap",start_sector:$swap_start,sectors:$swap_sectors},
                {role:"rescue",start_sector:$rescue_start,sectors:$rescue_sectors}],
      metadata_authenticity_verified:false,operating_system_verified:false,
      block_mapping_created:false,partition_write_executed:false}'
