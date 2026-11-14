#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Early-startup selection only. Opens one read-only descriptor; never formats,
# maps, unlocks, mounts or resumes. Kernel sysfs is an input, not an OEM trust proof.
uke_super_reject() { printf 'UKE_PHYSICAL_SUPER_REJECTED: %s\n' "$*" >&2; exit 1; }

uke_open_physical_super() {
    local compatible=/sys/firmware/devicetree/base/compatible bytes metadata key value count=0
    local selected='' node='' parent driver major minor sectors partition link
    local -A event=()
    [[ $(id -u) == 0 ]] || uke_super_reject 'root is required'
    [[ -f $compatible ]] || uke_super_reject 'device tree is unavailable'
    bytes=$(stat -Lc %s "$compatible")
    [[ $bytes =~ ^[1-9][0-9]{0,3}$ ]] || uke_super_reject 'invalid compatible property size'
    ((bytes <= 1024)) || uke_super_reject 'invalid compatible property size'
    [[ $(tail -c1 "$compatible" | od -An -tu1 | tr -d '[:space:]') == 0 ]] || uke_super_reject 'unterminated compatible property'
    tr '\0' '\n' < "$compatible" | grep -Fxq xiaomi,uke || uke_super_reject 'not the Uke board'
    tr '\0' '\n' < "$compatible" | grep -Fxq qcom,sm7675 || uke_super_reject 'not the measured Uke SoC'
    # Count every matching PARTNAME, including foreign/virtual candidates.
    # Udev's last-writer-wins name link does not establish uniqueness.
    for metadata in /sys/class/block/*/uevent; do
        [[ -r $metadata ]] || continue
        if grep -Fxq PARTNAME=super "$metadata"; then
            count=$((count+1))
            selected=${metadata%/uevent}
        fi
    done
    [[ $count == 1 ]] || uke_super_reject 'a unique super partition is required'
    node=$(readlink -e "$selected")
    [[ $node == /sys/devices/platform/soc/1d84000.ufshc/*/block/*/* &&
       -r $node/partition && ! -e $node/dm ]] || uke_super_reject 'super is outside the physical Uke UFS partition tree'
    driver=$(readlink -e /sys/devices/platform/soc/1d84000.ufshc/driver)
    [[ $driver == /sys/bus/platform/drivers/ufshcd-qcom ]] || uke_super_reject 'UFS controller driver differs'
    while IFS='=' read -r key value; do
        case $key in MAJOR|MINOR|DEVNAME|DEVTYPE|PARTN|PARTNAME)
            [[ ! -v event[$key] ]] || uke_super_reject 'duplicate device event field'
            event[$key]=$value;;
        esac
    done < "$node/uevent"
    [[ ${event[PARTNAME]:-} == super && ${event[DEVTYPE]:-} == partition &&
       ${event[DEVNAME]:-} =~ ^sd[a-z]+[1-9][0-9]*$ && ${node##*/} == "${event[DEVNAME]}" &&
       ${event[MAJOR]:-} =~ ^(0|[1-9][0-9]{0,8})$ && ${event[MINOR]:-} =~ ^(0|[1-9][0-9]{0,8})$ &&
       ${event[PARTN]:-} =~ ^[1-9][0-9]{0,5}$ ]] || uke_super_reject 'invalid physical partition identity'
    partition=$(< "$node/partition")
    [[ $partition == "${event[PARTN]}" ]] || uke_super_reject 'partition number disagrees with uevent'
    parent=${node%/*}
    [[ ! -e $parent/partition && -r $parent/queue/logical_block_size &&
       $(< "$parent/queue/logical_block_size") == 4096 ]] || uke_super_reject 'unexpected UFS logical sector size'
    uke_super_devno=${event[MAJOR]}:${event[MINOR]}
    [[ $(< "$node/dev") == "$uke_super_devno" &&
       $(readlink -e "/sys/dev/block/$uke_super_devno") == "$node" ]] || uke_super_reject 'sysfs device identities disagree'
    [[ -b /dev/${event[DEVNAME]} ]] || uke_super_reject 'selected partition node is unavailable'
    exec 3< "/dev/${event[DEVNAME]}"
    [[ -b /proc/self/fd/3 ]] || uke_super_reject 'opened input is not a block device'
    read -r major minor < <(stat -Lc '%t %T' /proc/self/fd/3)
    [[ $major =~ ^[0-9a-f]{1,8}$ && $minor =~ ^[0-9a-f]{1,8}$ &&
       $((16#$major)):$((16#$minor)) == "$uke_super_devno" ]] || uke_super_reject 'opened device differs from physical selection'
    link=/dev/disk/by-partlabel/super
    [[ -b $link && $(stat -Lc '%t %T' "$link") == "$major $minor" ]] || uke_super_reject 'partition-name link differs from the opened device'
    sectors=$(< "$node/size")
    [[ $sectors =~ ^[1-9][0-9]{0,10}$ ]] || uke_super_reject 'invalid physical sector count'
    uke_super_bytes=$(blockdev --getsize64 /proc/self/fd/3)
    [[ $uke_super_bytes =~ ^[1-9][0-9]{0,12}$ &&
       $uke_super_bytes == "$((sectors * 512))" &&
       $(blockdev --getss /proc/self/fd/3) == 4096 ]] || uke_super_reject 'opened capacity or sector size disagrees with sysfs'
    ((uke_super_bytes <= 2199023255552 && uke_super_bytes % 4096 == 0)) || uke_super_reject 'unsupported physical capacity'
    # Recheck the selected sysfs inode after opening. Callers retain fd3 rather
    # than returning a pathname for a later, independent device lookup.
    [[ $(readlink -e "$selected") == "$node" && $(< "$node/dev") == "$uke_super_devno" &&
       $(< "$node/size") == "$sectors" ]] || uke_super_reject 'physical identity changed while opening'
}

uke_super_main() {
    set -Eeuo pipefail
    export LC_ALL=C
    umask 077
    [[ $# == 1 && ( $1 == --identity-only || $1 == --inspect-ready ) ]] || uke_super_reject 'expected --identity-only or --inspect-ready'
    local here result='{}' layout=false
    here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    uke_open_physical_super
    if [[ $1 == --inspect-ready ]]; then
        result=$(bash "$here/inspect-fastboot-super.sh" --block /proc/self/fd/3)
        layout=true
    fi
    jq -M -n --argjson result "$result" --argjson layout "$layout" --arg devno "$uke_super_devno" --argjson bytes "$uke_super_bytes" \
        '$result + {physical_ufs_selection_verified:true,
          physical_selection:{schema_version:1,board:"xiaomi,uke",soc:"qcom,sm7675",controller:"1d84000.ufshc",
            partition_name:"super",device_major_minor:$devno,capacity_bytes:$bytes,logical_sector_bytes:4096,
            opened_readonly:true},linux_layout_verified:$layout,metadata_authenticity_verified:false,operating_system_verified:false,
          partition_write_executed:false,root_switch_executed:false,crypto_or_resume_executed:false}'
}

if [[ ${BASH_SOURCE[0]:-} == "$0" ]]; then uke_super_main "$@"; fi
