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
# The appliance uses KVM when the container was given /dev/kvm; the image forces TCG otherwise.
if [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then unset LIBGUESTFS_BACKEND_SETTINGS; fi
cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
relabel='selinux-relabel /etc/selinux/targeted/contexts/files/file_contexts / force:true'
[[ $filesystem != ext4 ]] || relabel=''
guestfish --rw --format=raw -a /job/root.raw <<GUEST
set-smp $cpus
set-memsize 2048
run
$format
mount /dev/sda /
tar-in /job/rootfs.tar / xattrs:true acls:true
$relabel
sync
umount-all
GUEST
if [[ $filesystem == ext4 ]]; then
    # The appliance skips virtual directories; label image inodes offline.
    c++ -std=c++20 -O2 -Wall -Wextra -Werror /builder/src/image/ext4-labels.cpp \
        -o /job/ext4-labels -lext2fs -lcom_err -lselinux
    expected=/job/root
    contexts=$expected/etc/selinux/targeted/contexts/files/file_contexts
    /job/ext4-labels apply /job/root.raw "$expected" "$contexts"
    /job/ext4-labels verify /job/root.raw "$expected" "$contexts"
fi
# A separate read-only appliance verifies the populated image, not the staging tree.
guestfish --ro --format=raw -a /job/root.raw <<GUEST > /job/filesystem-readback.txt
set-smp $cpus
set-memsize 2048
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
# Both decoders and the raw-image hash read the same files; run them together.
sha256sum /job/root.raw > /job/root.raw.sha256 &
hash_pid=$!
(/job/android-sparse decode "/job/artifacts/$partition.img" /job/expanded.raw && dd if=/job/root.raw bs=4M status=none | cmp - /job/expanded.raw) &
ours_pid=$!
(simg2img "/job/artifacts/$partition.img" /job/aosp-expanded.raw && dd if=/job/root.raw bs=4M status=none | cmp - /job/aosp-expanded.raw) &
aosp_pid=$!
wait "$hash_pid"
wait "$ours_pid"
wait "$aosp_pid"
jq --arg fs "$filesystem" --arg raw "$(cut -d ' ' -f1 /job/root.raw.sha256)" --argjson bytes "$(stat -c %s /job/root.raw)" \
    --arg sparse "$(sha256sum "/job/artifacts/$partition.img" | cut -d ' ' -f1)" \
    --arg boot "$(sha256sum /job/artifacts/boot.img | cut -d ' ' -f1)" \
    --argjson boot_bytes "$(stat -c %s /job/artifacts/boot.img)" \
    '. + {root_raw_bytes:$bytes,root_raw_sha256:$raw,root_sparse_sha256:$sparse,boot_sha256:$boot,boot_bytes:$boot_bytes,
      image_built:true,filesystem_contents_readback:true,filesystem_metadata_readback:true,selinux_relabel_performed:true,
      selinux_policy_contexts_verified:($fs=="ext4"),
      sparse_roundtrip_verified:true,independent_aosp_decoder_verified:true,physical_boot_tested:false,hardware_tested:false}' \
    /job/artifacts/manifest.json > /job/manifest.tmp
mv /job/manifest.tmp /job/artifacts/manifest.json
