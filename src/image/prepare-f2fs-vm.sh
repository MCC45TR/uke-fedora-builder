#!/usr/bin/env bash
# Native x86_64 container stage; only creates a host composition initramfs.
set -Eeuo pipefail
[[ $# == 1 && $1 =~ ^[a-zA-Z0-9.+_-]+$ ]]
release=$1
[[ $(uname -m) == x86_64 && -f /host/boot/vmlinuz-$release ]]
[[ -d /host/usr/lib/modules/$release && -d /job/vm ]]
mkdir -p /job/vm/empty-conf
install -m755 /builder/src/image/f2fs-vm-init.sh /job/vm/init
install -m755 /builder/src/image/metadata-manifest.sh /job/vm/metadata-manifest
dracut --force --no-hostonly --no-hostonly-cmdline --no-early-microcode \
    --conf /dev/null --confdir /job/vm/empty-conf \
    --kmoddir /host/usr/lib/modules/"$release" --kver "$release" --gzip \
    --add-drivers 'f2fs 9p 9pnet_virtio virtio_blk virtio_pci' \
    --install 'bash mount modprobe mkdir grep sha256sum mkfs.f2fs fsck.f2fs resize.f2fs tar setfiles sync umount logger getfattr awk sort cmp realpath cat stty rsync rm blkid fstrim zstd' \
    --include /job/vm/init /uke-compose-init \
    --include /job/vm/metadata-manifest /uke-metadata-manifest \
    --omit 'network network-manager network-legacy plymouth crypt systemd-cryptsetup syslog lvm mdraid btrfs i18n' \
    /job/vm/initramfs.cpio.gz
install -m644 /host/boot/vmlinuz-"$release" /job/vm/vmlinuz
sha256sum /job/vm/vmlinuz /job/vm/initramfs.cpio.gz > /job/vm/inputs.sha256
