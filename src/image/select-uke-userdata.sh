#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Early-startup selection only. Opens one read-only descriptor; never formats,
# maps, unlocks, mounts or resumes. Kernel sysfs is an input, not an OEM trust proof.
uke_userdata_reject() { printf 'UKE_PHYSICAL_USERDATA_REJECTED: %s\n' "$*" >&2; exit 1; }

uke_open_physical_userdata() {
    local compatible=/sys/firmware/devicetree/base/compatible bytes metadata key value count=0
    local selected='' node='' parent driver major minor sectors partition link
    local -A event=()
    [[ $(id -u) == 0 ]] || uke_userdata_reject 'root is required'
    [[ -f $compatible ]] || uke_userdata_reject 'device tree is unavailable'
    bytes=$(stat -Lc %s "$compatible")
    [[ $bytes =~ ^[1-9][0-9]{0,3}$ ]] || uke_userdata_reject 'invalid compatible property size'
    ((bytes <= 1024)) || uke_userdata_reject 'invalid compatible property size'
    [[ $(tail -c1 "$compatible" | od -An -tu1 | tr -d '[:space:]') == 0 ]] || uke_userdata_reject 'unterminated compatible property'
    tr '\0' '\n' < "$compatible" | grep -Fxq xiaomi,uke || uke_userdata_reject 'not the Uke board'
    tr '\0' '\n' < "$compatible" | grep -Fxq qcom,sm7675 || uke_userdata_reject 'not the measured Uke SoC'
    # Count every matching PARTNAME, including foreign/virtual candidates.
    # Udev's last-writer-wins name link does not establish uniqueness.
    for metadata in /sys/class/block/*/uevent; do
        [[ -r $metadata ]] || continue
        if grep -Fxq PARTNAME=userdata "$metadata"; then
            count=$((count+1))
            selected=${metadata%/uevent}
        fi
    done
    [[ $count == 1 ]] || uke_userdata_reject 'a unique userdata partition is required'
    node=$(readlink -e "$selected")
    [[ $node == /sys/devices/platform/soc/1d84000.ufshc/*/block/*/* &&
       -r $node/partition && ! -e $node/dm ]] || uke_userdata_reject 'userdata is outside the physical Uke UFS partition tree'
    driver=$(readlink -e /sys/devices/platform/soc/1d84000.ufshc/driver)
    [[ $driver == /sys/bus/platform/drivers/ufshcd-qcom ]] || uke_userdata_reject 'UFS controller driver differs'
    while IFS='=' read -r key value; do
        case $key in MAJOR|MINOR|DEVNAME|DEVTYPE|PARTN|PARTNAME)
            [[ ! -v event[$key] ]] || uke_userdata_reject 'duplicate device event field'
            event[$key]=$value;;
        esac
    done < "$node/uevent"
    [[ ${event[PARTNAME]:-} == userdata && ${event[DEVTYPE]:-} == partition &&
       ${event[DEVNAME]:-} =~ ^sd[a-z]+[1-9][0-9]*$ && ${node##*/} == "${event[DEVNAME]}" &&
       ${event[MAJOR]:-} =~ ^(0|[1-9][0-9]{0,8})$ && ${event[MINOR]:-} =~ ^(0|[1-9][0-9]{0,8})$ &&
       ${event[PARTN]:-} =~ ^[1-9][0-9]{0,5}$ ]] || uke_userdata_reject 'invalid physical partition identity'
    partition=$(< "$node/partition")
    [[ $partition == "${event[PARTN]}" ]] || uke_userdata_reject 'partition number disagrees with uevent'
    parent=${node%/*}
    [[ ! -e $parent/partition && -r $parent/queue/logical_block_size &&
       $(< "$parent/queue/logical_block_size") == 4096 ]] || uke_userdata_reject 'unexpected UFS logical sector size'
    uke_userdata_devno=${event[MAJOR]}:${event[MINOR]}
    [[ $(< "$node/dev") == "$uke_userdata_devno" &&
       $(readlink -e "/sys/dev/block/$uke_userdata_devno") == "$node" ]] || uke_userdata_reject 'sysfs device identities disagree'
    [[ -b /dev/${event[DEVNAME]} ]] || uke_userdata_reject 'selected partition node is unavailable'
    exec 3< "/dev/${event[DEVNAME]}"
    [[ -b /proc/self/fd/3 ]] || uke_userdata_reject 'opened input is not a block device'
    read -r major minor < <(stat -Lc '%t %T' /proc/self/fd/3)
    [[ $major =~ ^[0-9a-f]{1,8}$ && $minor =~ ^[0-9a-f]{1,8}$ &&
       $((16#$major)):$((16#$minor)) == "$uke_userdata_devno" ]] || uke_userdata_reject 'opened device differs from physical selection'
    link=/dev/disk/by-partlabel/userdata
    [[ -b $link && $(stat -Lc '%t %T' "$link") == "$major $minor" ]] || uke_userdata_reject 'partition-name link differs from the opened device'
    sectors=$(< "$node/size")
    [[ $sectors =~ ^[1-9][0-9]{0,10}$ ]] || uke_userdata_reject 'invalid physical sector count'
    uke_userdata_bytes=$(blockdev --getsize64 /proc/self/fd/3)
    [[ $uke_userdata_bytes =~ ^[1-9][0-9]{0,12}$ &&
       $uke_userdata_bytes == "$((sectors * 512))" &&
       $(blockdev --getss /proc/self/fd/3) == 4096 ]] || uke_userdata_reject 'opened capacity or sector size disagrees with sysfs'
    ((uke_userdata_bytes <= 2199023255552 && uke_userdata_bytes % 4096 == 0)) || uke_userdata_reject 'unsupported physical capacity'
    # Recheck the selected sysfs inode after opening. Callers retain fd3 rather
    # than returning a pathname for a later, independent device lookup.
    [[ $(readlink -e "$selected") == "$node" && $(< "$node/dev") == "$uke_userdata_devno" &&
       $(< "$node/size") == "$sectors" ]] || uke_userdata_reject 'physical identity changed while opening'
}
