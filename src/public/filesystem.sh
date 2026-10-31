#!/usr/bin/env bash
# Only a new regular file is attached to an isolated libguestfs appliance.
set -Eeuo pipefail
channel=$(jq -er .channel /job/request.json)
filesystem=$(jq -er .filesystem /job/request.json)
partition=$(jq -er .partition /job/request.json)
size=$(jq -er .size_mib /job/request.json)
case $filesystem in ext4|f2fs|xfs|btrfs) :;; *) exit 2;; esac
case $partition in linux|userdata) :;; *) exit 2;; esac
[[ $size =~ ^[1-9][0-9]{3,6}$ && ! -e /job/root.raw && -f /job/rootfs.tar ]]
# shellcheck source=root-metadata.sh
# shellcheck disable=SC1091
source /builder/src/public/root-metadata.sh
# shellcheck source=filesystem-commands.sh
# shellcheck disable=SC1091
source /builder/src/public/filesystem-commands.sh
# shellcheck source=guest-appliance.sh
# shellcheck disable=SC1091
source /builder/src/public/guest-appliance.sh
public_guest_appliance /job/filesystem-appliance
format=$(public_filesystem_format "$filesystem")
read_options=$(public_filesystem_ro_options "$filesystem")
# The appliance uses KVM when the container was given /dev/kvm; the image forces TCG otherwise.
if [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then unset LIBGUESTFS_BACKEND_SETTINGS; fi
cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
if [[ $filesystem == ext4 ]]; then
    if [[ $channel == unstable ]]; then
        cp "$UKE_IMAGE_TOOLS/ext4-labels" /job/ext4-labels
    else
        c++ -std=c++20 -O2 -Wall -Wextra -Werror /builder/src/image/ext4-labels.cpp \
            -o /job/ext4-labels -lext2fs -lcom_err -lselinux
    fi
    # shellcheck source=ext4-filesystem.sh
    # shellcheck disable=SC1091
    source /builder/src/public/ext4-filesystem.sh
    public_ext4_populate /job/root.raw /job/root "$size" /job/ext4-labels
else
truncate -s "${size}M" /job/root.raw
[[ -f /job/root.raw && ! -L /job/root.raw ]]
guestfish --rw --format=raw -a /job/root.raw <<GUEST
set-smp $cpus
set-memsize 2048
run
$format
mount /dev/sda /
tar-in /job/rootfs.tar / xattrs:true selinux:true acls:true
sync
umount-all
GUEST
fi
# A separate read-only appliance verifies the populated image, not the staging tree.
guestfish --ro --format=raw -a /job/root.raw <<GUEST > /job/filesystem-readback.txt
set-smp $cpus
set-memsize 2048
run
vfs-type /dev/sda
vfs-label /dev/sda
mount-options $read_options /dev/sda /
getxattr /etc/passwd security.selinux
tar-out / /job/root-readback.tar numericowner:true xattrs:true acls:true excludes:lost+found
umount-all
GUEST
grep -Fx "$filesystem" /job/filesystem-readback.txt
grep -Fx UKE_LINUX /job/filesystem-readback.txt
grep -aF passwd_file_t /job/filesystem-readback.txt
# Ignore generated SELinux labels here; contents, owners, ACLs and capabilities must match.
if [[ $channel == unstable ]]; then
    metadata_auditor=$UKE_IMAGE_TOOLS/compare-root-metadata
else
    metadata_auditor=/job/compare-root-metadata
    c++ -std=c++20 -O2 -Wall -Wextra -Werror /builder/src/image/compare-root-metadata.cpp -o "$metadata_auditor"
fi
public_root_compare /job/root /job/rootfs.tar /job/root-readback.tar /job "$metadata_auditor"
if [[ $channel == unstable ]]; then cp "$UKE_IMAGE_TOOLS/android-sparse" /job/android-sparse
else c++ -std=c++20 -O2 -Wall -Wextra -Werror /builder/src/boot-pair/android-sparse.cpp -o /job/android-sparse; fi
/job/android-sparse encode /job/root.raw "/job/artifacts/$partition.img"
if jq -e '(.kernel_rpm_request // "") != ""' /job/request.json >/dev/null; then
    # Hosted runner: keep one decoder output at a time and discard verified tar copies.
    rm /job/rootfs.tar /job/root-readback.tar
    sha256sum /job/root.raw > /job/root.raw.sha256
    /job/android-sparse decode "/job/artifacts/$partition.img" /job/expanded.raw
    dd if=/job/root.raw bs=4M status=none | cmp - /job/expanded.raw
    rm /job/expanded.raw
    simg2img "/job/artifacts/$partition.img" /job/aosp-expanded.raw
    dd if=/job/root.raw bs=4M status=none | cmp - /job/aosp-expanded.raw
    rm /job/aosp-expanded.raw
else
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
fi
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
