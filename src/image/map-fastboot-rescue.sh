#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Demand-only early-boot helper. Creates one read-only linear rescue mapping.
# The caller must independently select the unique physical Uke UFS super.
# This lower layer also supports owned loop devices for real mapping fixtures.
set -Eeuo pipefail
export LC_ALL=C
umask 077
fail() { printf 'UKE_RESCUE_REJECTED: %s\n' "$*" >&2; exit 1; }
[[ $# == 1 && $(id -u) == 0 ]] || fail 'run as root with one super block device'
here=$(cd -- "$(dirname -- "$0")" && pwd)
[[ -b $1 ]] || fail 'input is not a block device'
exec 3< "$1"
[[ -b /proc/self/fd/3 ]] || fail 'opened input is not a block device'
read -r major minor < <(stat -Lc '%t %T' /proc/self/fd/3)
[[ $major =~ ^[0-9a-f]{1,8}$ && $minor =~ ^[0-9a-f]{1,8}$ ]] || fail 'ambiguous opened block device identity'
devno=$((16#$major)):$((16#$minor))
[[ -r /sys/dev/block/$devno/dev && $(< "/sys/dev/block/$devno/dev") == "$devno" ]] || fail 'opened device has no matching sysfs identity'
capacity=$(blockdev --getsize64 /proc/self/fd/3)
runtime=/run/uke-rescue-mapper
[[ ! -L $runtime ]] || fail 'runtime directory is a symlink'
if [[ ! -d $runtime ]]; then mkdir -m700 "$runtime"; fi
[[ $(stat -c '%u:%a' "$runtime") == 0:700 ]] || fail 'runtime directory must be root-owned mode 0700'
[[ ! -L $runtime/lock ]] || fail 'lock is a symlink'
exec 9>> "$runtime/lock"
flock -n 9 || fail 'another rescue mapper is active'
work=$(mktemp -d "$runtime/check.XXXXXXXX")
name=uke-rescue
uuid=UKE-RESCUE-v1-${devno/:/-}
owned=0
cleanup() {
    local status=$?
    trap - EXIT
    if ((owned)); then
        if actual=$(dmsetup info -c --noheadings -o uuid "$name" 2>/dev/null | tr -d '[:space:]'); then
            if [[ $actual == "$uuid" ]]; then
                dmsetup --noudevsync remove --retry "$name" || status=1
            else
                printf 'UKE_RESCUE_REJECTED: mapping ownership changed; refusing cleanup of an unknown mapping\n' >&2
                status=1
            fi
        fi
    fi
    find "$work" -depth -delete
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if dmsetup info "$name" >/dev/null 2>&1; then fail 'rescue mapping name is already occupied'; fi
TMPDIR="$work" bash "$here/inspect-fastboot-super.sh" --block /proc/self/fd/3 > "$work/plan.json"
[[ $(jq -er .layout.super_bytes "$work/plan.json") == "$capacity" ]]
start=$(jq -er '.mappings[] | select(.role == "rescue") | .start_sector' "$work/plan.json")
sectors=$(jq -er '.mappings[] | select(.role == "rescue") | .sectors' "$work/plan.json")
[[ $start =~ ^[1-9][0-9]*$ && $sectors =~ ^[1-9][0-9]*$ ]]
printf '0 %s linear %s %s\n' "$sectors" "$devno" "$start" > "$work/table"
# Set ownership before invoking dmsetup so interrupted create is cleaned only
# if the resulting UUID matches this attempt's independently checked device.
owned=1
if ! dmsetup --noudevsync create --readonly --uuid "$uuid" "$name" < "$work/table"; then
    if ! dmsetup info "$name" >/dev/null 2>&1; then owned=0; fi
    fail 'cannot create read-only rescue mapping'
fi
dmsetup mknodes "$name"
mapped=/dev/mapper/$name
[[ -b $mapped && $(blockdev --getro "$mapped") == 1 ]] || fail 'rescue mapping is not read-only'
[[ $(blockdev --getsize64 "$mapped") == "$((sectors * 512))" ]] || fail 'mapped capacity differs'
actual=$(dmsetup table "$name")
[[ $actual == "$(< "$work/table")" ]] || fail 'active mapper table differs'
[[ $(blkid -p -s TYPE -o value "$mapped") == ext4 &&
   $(blkid -p -s LABEL -o value "$mapped") == FEDORA_RESCUE ]] || fail 'rescue payload is not provisioned EXT4'
timeout --signal=TERM --kill-after=1s 5s dumpe2fs -h "$mapped" > "$work/superblock" 2>/dev/null
blocks=$(awk '/^Block count:/ {print $3}' "$work/superblock")
block_size=$(awk '/^Block size:/ {print $3}' "$work/superblock")
[[ $blocks =~ ^[1-9][0-9]*$ && $block_size == 4096 ]] || fail 'unexpected EXT4 geometry'
((blocks * block_size == sectors * 512)) || fail 'rescue filesystem does not fill its logical allocation'
# Recheck metadata before making the mapper available to the caller.
TMPDIR="$work" bash "$here/inspect-fastboot-super.sh" --block /proc/self/fd/3 > "$work/rechecked.json"
cmp "$work/plan.json" "$work/rechecked.json" || fail 'super topology changed while mapping'
jq -M -n --arg path "$mapped" --arg uuid "$uuid" --argjson capacity "$((sectors * 512))" \
    '{schema_version:1,rescue_device:$path,dm_uuid:$uuid,rescue_bytes:$capacity,
      readonly_linear_mapping:true,three_slot_topology_verified:true,
      ext4_label_and_full_capacity_verified:true,partition_write_executed:false,
      physical_ufs_selection_verified:false,metadata_authenticity_verified:false,
      rescue_operating_system_verified:false,root_switch_executed:false}'
owned=0
