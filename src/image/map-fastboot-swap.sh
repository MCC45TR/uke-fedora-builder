#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Demand-only early-boot helper. Creates one writable linear swap mapping.
# The caller must independently select the unique physical Uke UFS super.
# This lower layer also supports owned loop devices for real mapping fixtures.
set -Eeuo pipefail
export LC_ALL=C
umask 077
fail() { printf 'UKE_SWAP_REJECTED: %s\n' "$*" >&2; exit 1; }
verify=false
if [[ $# == 2 && $1 == --verify ]];then verify=true;shift;fi
[[ $# == 1 && $(id -u) == 0 ]] || fail 'run as root with [--verify] and one super block device'
here=$(cd -- "$(dirname -- "$0")" && pwd)
[[ -b $1 ]] || fail 'input is not a block device'
exec 3< "$1"
[[ -b /proc/self/fd/3 ]] || fail 'opened input is not a block device'
read -r major minor < <(stat -Lc '%t %T' /proc/self/fd/3)
[[ $major =~ ^[0-9a-f]{1,8}$ && $minor =~ ^[0-9a-f]{1,8}$ ]] || fail 'ambiguous opened block device identity'
devno=$((16#$major)):$((16#$minor))
[[ -r /sys/dev/block/$devno/dev && $(< "/sys/dev/block/$devno/dev") == "$devno" ]] || fail 'opened device has no matching sysfs identity'
capacity=$(blockdev --getsize64 /proc/self/fd/3)
runtime=/run/uke-swap-mapper
[[ ! -L $runtime ]] || fail 'runtime directory is a symlink'
if [[ ! -d $runtime ]]; then mkdir -m700 "$runtime"; fi
[[ $(stat -c '%u:%a' "$runtime") == 0:700 ]] || fail 'runtime directory must be root-owned mode 0700'
[[ ! -L $runtime/lock ]] || fail 'lock is a symlink'
exec 9>> "$runtime/lock"
flock -n 9 || fail 'another swap mapper is active'
work=$(mktemp -d "$runtime/check.XXXXXXXX")
name=linux_swap
uuid=UKE-SWAP-v1-${devno/:/-}
owned=0
cleanup() {
    local status=$?
    trap - EXIT
    if ((owned)); then
        if actual=$(dmsetup info -c --noheadings -o uuid "$name" 2>/dev/null | tr -d '[:space:]'); then
            if [[ $actual == "$uuid" ]]; then
                dmsetup --noudevsync remove --retry "$name" || status=1
            else
                printf 'UKE_SWAP_REJECTED: mapping ownership changed; refusing cleanup of an unknown mapping\n' >&2
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
if dmsetup info "$name" >/dev/null 2>&1; then
    [[ $verify == true ]] || fail 'swap mapping name is already occupied'
else
    [[ $verify == false ]] || fail 'swap mapping is unavailable for verification'
fi
TMPDIR="$work" bash "$here/inspect-fastboot-super.sh" --block /proc/self/fd/3 > "$work/plan.json"
[[ $(jq -er .layout.super_bytes "$work/plan.json") == "$capacity" ]]
start=$(jq -er '.mappings[] | select(.role == "swap") | .start_sector' "$work/plan.json")
sectors=$(jq -er '.mappings[] | select(.role == "swap") | .sectors' "$work/plan.json")
[[ $start =~ ^[1-9][0-9]*$ && $sectors =~ ^[1-9][0-9]*$ ]]
printf '0 %s linear %s %s\n' "$sectors" "$devno" "$start" > "$work/table"
# Set ownership before invoking dmsetup so interrupted create is cleaned only
# if the resulting UUID matches this attempt's independently checked device.
if [[ $verify == false ]];then
    owned=1
    if ! dmsetup --noudevsync create --uuid "$uuid" "$name" < "$work/table"; then
        if ! dmsetup info "$name" >/dev/null 2>&1; then owned=0; fi
        fail 'cannot create writable swap mapping'
    fi
    dmsetup mknodes "$name"
fi
[[ $(dmsetup info -c --noheadings -o uuid "$name" | tr -d '[:space:]') == "$uuid" ]] || fail 'swap mapping ownership differs'
mapped=/dev/mapper/$name
[[ -b $mapped && $(blockdev --getro "$mapped") == 0 ]] || fail 'swap mapping is not writable'
[[ $(blockdev --getsize64 "$mapped") == "$((sectors * 512))" ]] || fail 'mapped capacity differs'
actual=$(dmsetup table "$name")
[[ $actual == "$(< "$work/table")" ]] || fail 'active mapper table differs'
[[ $(getconf PAGESIZE) == 4096 ]] || fail 'this swap contract requires 4096-byte pages'
[[ $(blkid -p -s TYPE -o value "$mapped") == swap &&
   $(blkid -p -s LABEL -o value "$mapped") == linux_swap ]] || fail 'swap payload lacks the provisioned Linux swap signature and label'
# Linux swap_info v1: version, last_page, nr_badpages at byte 1024. Read
# only one header, retaining the descriptor and the topology admission above.
read -r version last_page bad_pages < <(od --endian=little -An -tu4 -j1024 -N12 "$mapped")
[[ $version == 1 && $last_page =~ ^[1-9][0-9]*$ && $bad_pages == 0 ]] || fail 'unsupported swap header geometry'
(((last_page + 1) * 4096 == sectors * 512)) || fail 'swap signature does not cover its logical allocation'
# Recheck metadata before making the mapper available to the caller.
TMPDIR="$work" bash "$here/inspect-fastboot-super.sh" --block /proc/self/fd/3 > "$work/rechecked.json"
cmp "$work/plan.json" "$work/rechecked.json" || fail 'super topology changed while mapping'
jq -M -n --arg path "$mapped" --arg uuid "$uuid" --argjson capacity "$((sectors * 512))" --argjson verify "$verify" \
    '{schema_version:1,swap_device:$path,dm_uuid:$uuid,swap_bytes:$capacity,
      existing_mapping_verified:$verify,
      writable_linear_mapping:true,three_slot_topology_verified:true,
      swap_label_and_full_capacity_verified:true,partition_write_executed:false,
      physical_ufs_selection_verified:false,metadata_authenticity_verified:false,
      swap_activated:false,encrypted_swap_verified:false,hibernate_verified:false}'
owned=0
