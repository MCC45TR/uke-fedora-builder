#!/bin/bash
# Host composition guest only; never included in the Fedora tablet root.
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
fail() {
    echo 'UKE_F2FS_COMPOSE_FAILED'
    sync
    stty -F /dev/ttyS0 -echo || true
    echo b > /proc/sysrq-trigger
}
trap fail ERR
[[ $$ == 1 ]]
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /run /share /target
mount -t tmpfs tmpfs /run
grep -Fq 'uke.f2fs-compose=1' /proc/cmdline
[[ -b /dev/vda && ! -e /dev/vdb ]]
modprobe f2fs
modprobe 9pnet_virtio
modprobe 9p
mount -t 9p -o trans=virtio,version=9p2000.L,msize=1048576,ro compose /share
if grep -Fq 'uke.f2fs-xattr-audit=1' /proc/cmdline; then
    [[ $(cat /sys/class/block/vda/ro) == 1 ]]
    mount -t f2fs -o ro,disable_roll_forward /dev/vda /target
    /uke-metadata-manifest /target /run/xattrs.actual.tsv
    cmp /share/xattrs.expected.tsv /run/xattrs.actual.tsv
    umount /target
    echo 'UKE_F2FS_XATTR_AUDIT_PASSED'
    stty -F /dev/ttyS0 -echo
    echo b > /proc/sysrq-trigger
    exit 1
fi
[[ -f /share/rootfs.tar && -f /share/rootfs.tar.sha256 ]]
(cd /share; sha256sum -c rootfs.tar.sha256)
grow=0
if grep -Fq 'uke.f2fs-grow=1' /proc/cmdline; then
    grow=1
    fsck.f2fs -f /dev/vda
    resize.f2fs /dev/vda
else
    mkfs.f2fs -f -l UKE_LINUX -O extra_attr,inode_checksum,sb_checksum /dev/vda
fi
mount -t f2fs /dev/vda /target
# File labels are generated from this root's original Fedora policy.
contexts=/target/etc/selinux/targeted/contexts/files/file_contexts
if (( ! grow )); then
    tar --extract --numeric-owner --same-owner --acls --xattrs --xattrs-include=security.capability \
        -f /share/rootfs.tar -C /target
    setfiles -F -r /target "$contexts" /target
fi
[[ -s $contexts ]]
tar --compare --numeric-owner --acls --xattrs --xattrs-include=security.capability \
    -f /share/rootfs.tar -C /target
setfiles -n -v -r /target "$contexts" /target > /run/relabel-check.log
[[ ! -s /run/relabel-check.log ]]
/uke-metadata-manifest /target /run/xattrs.actual.tsv
cmp /share/xattrs.expected.tsv /run/xattrs.actual.tsv
sync
umount /target
fsck.f2fs -f /dev/vda
echo 'UKE_F2FS_COMPOSE_PASSED'
sync
stty -F /dev/ttyS0 -echo
echo b > /proc/sysrq-trigger
