#!/usr/bin/env bash
# Host composition only. The sole guest disk is a newly created regular file.
set -Eeuo pipefail
[[ $# == 2 && $2 =~ ^localhost/[a-zA-Z0-9._:/-]+$ ]]
job=$(realpath "$1") vm_image=$2
[[ -f $job/device-packages.complete && -f $job/root-audit.complete && ! -e $job/rootfs-frozen ]]
[[ -f $job/vm/vmlinuz && -f $job/vm/initramfs.cpio.gz && -d $job/root ]]
[[ ! -e $job/image && ! -L $job/image ]]
mkdir -m700 "$job/image"
touch "$job/rootfs-frozen"
podman unshare bash "$(dirname "$0")/metadata-manifest.sh" "$job/root" "$job/image/xattrs.expected.tsv"
podman unshare tar --create --numeric-owner --one-file-system --sort=name \
    --acls --xattrs --xattrs-include=security.capability \
    -f "$job/image/rootfs.tar" -C "$job/root" .
(cd "$job/image"; sha256sum rootfs.tar > rootfs.tar.sha256)
truncate -s 14G "$job/image/userdata.f2fs.img"
[[ -f $job/image/userdata.f2fs.img && ! -L $job/image/userdata.f2fs.img ]]
podman run --rm --pull=never --network=none --security-opt label=disable --cpus=2 --memory=3g --device /dev/kvm \
    -v "$job/vm:/vm:ro" -v "$job/image:/job" "$vm_image" \
    /usr/bin/timeout 1200 qemu-system-x86_64 \
    -machine q35,accel=kvm -cpu host -smp 2 -m 2048 -nodefaults -display none -monitor none -serial stdio \
    -no-reboot -nic none -kernel /vm/vmlinuz -initrd /vm/initramfs.cpio.gz \
    -append 'console=ttyS0 rdinit=/uke-compose-init selinux=0 panic=1 uke.f2fs-compose=1' \
    -drive if=none,id=target,format=raw,file=/job/userdata.f2fs.img,cache=none \
    -device virtio-blk-pci,drive=target,logical_block_size=4096,physical_block_size=4096 \
    -virtfs local,path=/job,mount_tag=compose,security_model=none,readonly=on \
    > "$job/logs/f2fs-full-compose.log" 2>&1
grep -Eq $'^UKE_F2FS_COMPOSE_PASSED\r?$' "$job/logs/f2fs-full-compose.log"
if grep -Eq 'UKE_F2FS_COMPOSE_FAILED|Kernel panic' "$job/logs/f2fs-full-compose.log"; then exit 1; fi
(cd "$job/image"; sha256sum userdata.f2fs.img > userdata.f2fs.img.sha256)
zstd -T2 -10 --zstd=wlog=25 -q "$job/image/userdata.f2fs.img" -o "$job/image/userdata.f2fs.img.zst"
zstd -t "$job/image/userdata.f2fs.img.zst"
touch "$job/f2fs-image.complete"
touch "$job/f2fs-xattr-audit.complete"
