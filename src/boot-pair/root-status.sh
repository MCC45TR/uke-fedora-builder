#!/bin/sh
set -eu
mkdir -p /var/log/uke-bringup
{
    printf 'UKE_FEDORA_EXT4_ROOT_READY\n'
    uname -r
    findmnt -n -o SOURCE,FSTYPE /
    printf 'pid1='; readlink /proc/1/exe
    printf 'selinux='; cat /sys/fs/selinux/enforce
} > /var/log/uke-bringup/root-status.txt
cat /var/log/uke-bringup/root-status.txt
# Export the same status on a real serial port when one exists. On Uke this
# remains the local console/journal; on QEMU it is an observation channel.
if [ -c /dev/ttyAMA0 ]; then cat /var/log/uke-bringup/root-status.txt > /dev/ttyAMA0; fi
