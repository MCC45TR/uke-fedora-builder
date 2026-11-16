#!/usr/bin/bash
# Original Fedora tools on an already qualified, independently owned loop.
# No swapon, host RAM use, real UFS, firmware or tablet access.
set -Eeuo pipefail
trap 'printf "UKE_SWAP_FIXTURE_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
[[ $# == 3 && $(id -u) == 0 && $1 =~ ^/dev/loop[0-9]+$ && -b $1 && -d $2 && ! -e $3 && ! -L $3 ]]
device=$(readlink -e "$1");fixture=$(realpath "$2");report=$(realpath -m "$3")
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
helper=$root/src/image/map-fastboot-swap.sh
[[ $(blockdev --getsize64 "$device") == 8589934592 ]]
[[ $(losetup -n -O BACK-INO "$device" | tr -d '[:space:]') == "$(stat -c %i "$fixture/super.raw")" ]]
[[ $(losetup -n -O BACK-MAJ:MIN "$device" | tr -d '[:space:]') == "$(findmnt -nro MAJ:MIN --target "$fixture/super.raw")" ]]
bash "$root/src/image/inspect-fastboot-super.sh" --block "$device" > /dev/null
devno=$(lsblk -dnro MAJ:MIN "$device")
uuid=UKE-SWAP-v1-${devno/:/-}
occupied=UKE-SWAP-FIXTURE-v1-${devno/:/-}
if dmsetup info linux_swap >/dev/null 2>&1;then echo 'Fixture swap mapper name already exists' >&2;exit 1;fi
work=$(mktemp -d "$fixture/swap-map.XXXXXXXX")
cleanup() {
    local status=$? actual
    trap - EXIT
    if actual=$(dmsetup info -c --noheadings -o uuid linux_swap 2>/dev/null | tr -d '[:space:]');then
        if [[ $actual == "$uuid" || $actual == "$occupied" ]];then
            dmsetup --noudevsync remove --retry linux_swap || status=1
        else status=1;fi
    fi
    find "$work" -depth -delete
    exit "$status"
}
trap cleanup EXIT
before=$(sha256sum "$device" | cut -d ' ' -f1)
refused() {
    local reason=$1;shift
    if bash "$helper" "$@" > "$work/refused.json" 2> "$work/refused.log";then
        echo 'Swap fixture accepted an invalid mapping' >&2;exit 1
    fi
    grep -Fq "$reason" "$work/refused.log"
}
refused 'unavailable for verification' --verify "$device"
printf '0 8 linear %s 0\n' "$devno" | dmsetup --noudevsync create --uuid "$occupied" linux_swap
refused 'already occupied' "$device"
refused 'ownership differs' --verify "$device"
[[ $(dmsetup info -c --noheadings -o uuid linux_swap | tr -d '[:space:]') == "$occupied" ]]
dmsetup --noudevsync remove --retry linux_swap
bash "$helper" "$device" > "$work/mapped.json"
bash "$helper" --verify "$device" > "$work/verified.json"
jq -e '.existing_mapping_verified and .writable_linear_mapping and .three_slot_topology_verified and
 .swap_label_and_full_capacity_verified and (.partition_write_executed|not) and (.swap_activated|not)' "$work/verified.json" > /dev/null
[[ $(blkid -p -s LABEL -o value /dev/mapper/linux_swap) == linux_swap ]]
table=$(dmsetup table linux_swap)
dd if=/dev/mapper/linux_swap of="$work/header" bs=4096 count=1 status=none
# Mutate only the owned disposable fixture, then restore its exact header.
swaplabel -L fixture_wrong /dev/mapper/linux_swap
refused 'signature and label' --verify "$device"
dd if="$work/header" of=/dev/mapper/linux_swap bs=4096 count=1 conv=notrunc status=none
dmsetup --noudevsync remove --retry linux_swap
printf '%s\n' "$table" | dmsetup --noudevsync create --readonly --uuid "$uuid" linux_swap
refused 'not writable' --verify "$device"
[[ $(blockdev --getro /dev/mapper/linux_swap) == 1 ]]
dmsetup --noudevsync remove --retry linux_swap
printf '%s\n' "$table" | dmsetup --noudevsync create --uuid "$occupied" linux_swap
dmsetup mknodes linux_swap
mkswap --quiet --pagesize 4096 --label linux_swap /dev/mapper/linux_swap 1024
dmsetup --noudevsync remove --retry linux_swap
refused 'does not cover its logical allocation' "$device"
if dmsetup info linux_swap >/dev/null 2>&1;then echo 'Failed new mapper was retained' >&2;exit 1;fi
printf '%s\n' "$table" | dmsetup --noudevsync create --uuid "$occupied" linux_swap
dmsetup mknodes linux_swap
dd if="$work/header" of=/dev/mapper/linux_swap bs=4096 count=1 conv=notrunc status=none
dmsetup --noudevsync remove --retry linux_swap
bash "$helper" "$device" > "$work/final.json"
bash "$helper" --verify "$device" > /dev/null
dmsetup --noudevsync remove --retry linux_swap
[[ $(sha256sum "$device" | cut -d ' ' -f1) == "$before" ]]
jq -n --slurpfile mapping "$work/final.json" --arg hash "$before" '
 {schema_version:1,owned_loop_only:true,original_tools_used:true,mapping:$mapping[0],
 foreign_mapping_preserved:true,missing_mapping_refused:true,readonly_mapping_refused:true,
 wrong_label_refused:true,short_swap_header_refused:true,new_failed_mapping_removed:true,
 complete_device_bytes_restored:true,device_sha256:$hash,swap_activated:false,
 physical_ufs_tested:false,operating_system_booted:false,encryption_tested:false,hibernate_tested:false}' > "$report"
