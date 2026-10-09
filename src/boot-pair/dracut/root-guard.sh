#!/bin/sh
# Native/POSIX initramfs boundary: never fall back to Android or another EXT4 root.
set -eu
uuid=$(cat /etc/uke-boot-pair.uuid)
case "$uuid" in
    ????????-????-????-????-????????????) ;;
    *) echo 'UKE_ROOT_REJECTED: invalid image UUID' >&2; exit 1;;
esac
case "$uuid" in *[!a-f0-9-]*) exit 1;; esac
selected=/dev/disk/by-uuid/$uuid
attempt=0
read -r uptime _ < /proc/uptime
started=${uptime%%.*}
while [ "$attempt" -lt 45 ]; do
    count=0
    candidate=''
    for metadata in /sys/class/block/*/uevent; do
        [ -r "$metadata" ] || continue
        name='' device=''
        while IFS='=' read -r key value; do
            case "$key" in PARTNAME) name=$value;; DEVNAME) device=$value;; esac
        done < "$metadata"
        [ "$name" = linux ] || continue
        count=$((count + 1))
        candidate=/dev/$device
    done
    if [ "$count" -gt 1 ]; then
        echo 'UKE_ROOT_REJECTED: multiple linux partitions' >&2; exit 1
    fi
    if [ "$count" -eq 1 ] && [ -b "$candidate" ] && [ -e "$selected" ]; then
        [ "$(readlink -f "$selected")" = "$(readlink -f "$candidate")" ] || {
            echo 'UKE_ROOT_REJECTED: UUID belongs to a different partition' >&2; exit 1;
        }
        [ "$(blkid -p -s UUID -o value "$candidate")" = "$uuid" ] && \
        [ "$(blkid -p -s TYPE -o value "$candidate")" = ext4 ] || {
            echo 'UKE_ROOT_REJECTED: unexpected filesystem identity' >&2; exit 1;
        }
        echo 'UKE_ROOT_ADMITTED: linux partition and image UUID match'
        exit 0
    fi
    attempt=$((attempt + 1))
    read -r uptime _ < /proc/uptime
    [ "$(( ${uptime%%.*} - started ))" -lt 45 ] || break
    sleep 1
done
echo 'UKE_ROOT_REJECTED: matching linux partition unavailable' >&2
exit 1
