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
archive=rootfs.tar
[[ ! -f /share/rootfs.tar.zst ]] || archive=rootfs.tar.zst
[[ -f /share/$archive && -f /share/$archive.sha256 ]]
(cd /share; sha256sum -c "$archive.sha256")
grow=0
patch=0
if grep -Fq 'uke.f2fs-patch=1' /proc/cmdline; then
    ! grep -Fq 'uke.f2fs-grow=1' /proc/cmdline
    [[ -s /share/fsuuid.expected ]]
    [[ $(blkid -s TYPE -o value /dev/vda) == f2fs ]]
    [[ $(blkid -s LABEL -o value /dev/vda) == UKE_LINUX ]]
    [[ $(blkid -s UUID -o value /dev/vda) == "$(cat /share/fsuuid.expected)" ]]
    patch=1
    fsck.f2fs -f /dev/vda
elif grep -Fq 'uke.f2fs-grow=1' /proc/cmdline; then
    grow=1
    fsck.f2fs -f /dev/vda
    resize.f2fs /dev/vda
else
    mkfs.f2fs -f -l UKE_LINUX -O extra_attr,inode_checksum,sb_checksum /dev/vda
fi
mount -t f2fs /dev/vda /target
# File labels are generated from this root's original Fedora policy.
contexts=/target/etc/selinux/targeted/contexts/files/file_contexts
if (( patch )); then
    [[ ! -e /target/.uke-staged-root && ! -L /target/.uke-staged-root ]]
    mkdir -m700 /target/.uke-staged-root
    tar --extract --numeric-owner --same-owner --acls --xattrs --xattrs-include=security.capability \
        -f "/share/$archive" -C /target/.uke-staged-root
    # Stage on the existing disk; only changed files replace their old inodes.
    rsync -aHAXc --numeric-ids --delete --exclude=/.uke-staged-root/ \
        /target/.uke-staged-root/ /target/
    rm -rf -- /target/.uke-staged-root
    setfiles -F -r /target "$contexts" /target
elif (( ! grow )); then
    tar --extract --numeric-owner --same-owner --acls --xattrs --xattrs-include=security.capability \
        -f "/share/$archive" -C /target
    setfiles -F -r /target "$contexts" /target
fi
[[ -s $contexts ]]
tar --compare --numeric-owner --acls --xattrs --xattrs-include=security.capability \
    -f "/share/$archive" -C /target
setfiles -n -v -r /target "$contexts" /target > /run/relabel-check.log
[[ ! -s /run/relabel-check.log ]]
/uke-metadata-manifest /target /run/xattrs.actual.tsv
cmp /share/xattrs.expected.tsv /run/xattrs.actual.tsv
if (( patch )); then
    [[ $(blkid -s UUID -o value /dev/vda) == "$(cat /share/fsuuid.expected)" ]]
    sync
    fstrim /target
fi
sync
umount /target
fsck.f2fs -f /dev/vda
echo 'UKE_F2FS_COMPOSE_PASSED'
sync
stty -F /dev/ttyS0 -echo
echo b > /proc/sysrq-trigger
