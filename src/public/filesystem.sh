#!/usr/bin/env bash
# Only a new regular file is attached to an isolated libguestfs appliance.
set -Eeuo pipefail
filesystem=$(jq -er .filesystem /job/request.json)
partition=$(jq -er .partition /job/request.json)
size=$(jq -er .size_mib /job/request.json)
case $filesystem in ext4|f2fs|xfs|btrfs) :;; *) exit 2;; esac
case $partition in linux|userdata) :;; *) exit 2;; esac
[[ $size =~ ^[1-9][0-9]{3,6}$ && ! -e /job/root.raw && -f /job/rootfs.tar ]]
truncate -s "${size}M" /job/root.raw
[[ -f /job/root.raw && ! -L /job/root.raw ]]
case $filesystem in
    btrfs) format='mkfs-btrfs /dev/sda label:UKE_LINUX sectorsize:4096';;
    f2fs) format='mkfs f2fs /dev/sda label:UKE_LINUX features:extra_attr,inode_checksum,sb_checksum';;
    *) format="mkfs $filesystem /dev/sda label:UKE_LINUX blocksize:4096";;
esac
guestfish --rw --format=raw -a /job/root.raw <<GUEST
run
$format
mount /dev/sda /
tar-in /job/rootfs.tar / xattrs:true acls:true
selinux-relabel /etc/selinux/targeted/contexts/files/file_contexts / force:true
sync
umount-all
GUEST
# A separate read-only appliance verifies the populated image, not the staging tree.
guestfish --ro --format=raw -a /job/root.raw <<'GUEST' > /job/filesystem-readback.txt
run
vfs-type /dev/sda
vfs-label /dev/sda
mount-ro /dev/sda /
getxattr /etc/passwd security.selinux
tar-out / /job/root-readback.tar numericowner:true xattrs:true acls:true excludes:lost+found
umount-all
GUEST
grep -Fx "$filesystem" /job/filesystem-readback.txt
grep -Fx UKE_LINUX /job/filesystem-readback.txt
grep -aF passwd_file_t /job/filesystem-readback.txt
# Ignore generated SELinux labels here; contents, owners, ACLs and capabilities must match.
tar --compare --numeric-owner --acls --xattrs --xattrs-include=security.capability -f /job/root-readback.tar -C /job/root
for name in rootfs root-readback; do
    tar -tf "/job/$name.tar" | sed -e 's|^\./||' -e 's|/$||' | LC_ALL=C sort > "/job/$name.files"
done
cmp /job/rootfs.files /job/root-readback.files
c++ -std=c++20 -O2 -Wall -Wextra -Werror /builder/src/boot-pair/android-sparse.cpp -o /job/android-sparse
/job/android-sparse encode /job/root.raw "/job/artifacts/$partition.img"
/job/android-sparse decode "/job/artifacts/$partition.img" /job/expanded.raw
cmp /job/root.raw /job/expanded.raw
simg2img "/job/artifacts/$partition.img" /job/aosp-expanded.raw
cmp /job/root.raw /job/aosp-expanded.raw
jq --arg raw "$(sha256sum /job/root.raw | cut -d ' ' -f1)" --argjson bytes "$(stat -c %s /job/root.raw)" \
    --arg sparse "$(sha256sum "/job/artifacts/$partition.img" | cut -d ' ' -f1)" \
    --arg boot "$(sha256sum /job/artifacts/boot.img | cut -d ' ' -f1)" \
    --argjson boot_bytes "$(stat -c %s /job/artifacts/boot.img)" \
    '. + {root_raw_bytes:$bytes,root_raw_sha256:$raw,root_sparse_sha256:$sparse,boot_sha256:$boot,boot_bytes:$boot_bytes,
      filesystem_contents_readback:true,filesystem_metadata_readback:true,selinux_relabel_performed:true,
      sparse_roundtrip_verified:true,independent_aosp_decoder_verified:true,physical_boot_tested:false,hardware_tested:false}' \
    /job/artifacts/manifest.json > /job/manifest.tmp
mv /job/manifest.tmp /job/artifacts/manifest.json
