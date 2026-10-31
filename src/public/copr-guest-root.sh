#!/usr/bin/env bash
# Run only on the disposable COPR native worker. All disks are new regular files.
# A public-RPM SDK supplies native DNF; ownership never passes through host extraction.
set -Eeuo pipefail
[[ ${UKE_COPR_WORKER_AUDIT:-0} == 1 && $# == 2 && -d $1 && -d $2 ]]
recipe=$(realpath "$1") inputs=$(realpath "$2")
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
# shellcheck source=copr-sdk.sh
# shellcheck disable=SC1091
source "$recipe/src/public/copr-sdk.sh"
public_copr_sdk "$recipe" "$inputs" "$work"
tar -cf "$work/recipe.tar" -C "$recipe" src/public/root-proc.sh src/public/root-transaction.sh \
    src/public/ext4-filesystem.sh src/public/root-metadata.sh src/public/guest-runtime.sh \
    src/public/copr-filesystem-entry.sh tests/copr-label-tree.sh tests/copr-guest-runtime.sh \
    tests/copr-guest-transaction.sh tests/copr-guest-compare.sh configs/keys/fedora-46.asc \
    configs/copr-image-fixture-packages.json \
    build-tools/ext4-labels build-tools/compare-root-metadata
tar -cf "$work/inputs.tar" -C "$inputs" .
truncate -s 8G "$work/guest.raw"
cat > "$work/create.commands" <<GUEST
set-smp 2
set-memsize 2048
set-network false
run
mkfs ext4 /dev/sda
mount /dev/sda /
tar-in $work/sdk.tar /
write /.uke-copr-sdk 1
mkdir-p /builder
tar-in $work/recipe.tar /builder
mkdir-p /inputs
tar-in $work/inputs.tar /inputs
mkdir-p /job
mkdir-p /job/filesystem-mount
upload $work/mke2fs.sha256 /job/mke2fs.sha256
command-out "/usr/bin/bash /builder/tests/copr-guest-transaction.sh" -
download /job/report.json $work/report.json
download /job/installed-rpms.tsv $work/installed-rpms.tsv
download /job/root.raw $work/root.raw
download /job/rootfs.tar $work/rootfs.tar
sync
umount-all
GUEST
public_copr_guest_run rw "$work/guest.raw" "$work/create.commands" "$work/guestfish.log" 1800
jq -e '.native_dnf and .scriptlets and .dependency_check and .numeric_owner and .tmpfiles and
    (.full_os_composition == false) and (.hardware_tested == false)' "$work/report.json"
sha256sum "$work/guest.raw" > "$work/guest.sha256"
cat > "$work/read.commands" <<GUEST
set-smp 1
set-memsize 512
set-network false
run
mount-options ro,noload /dev/sda /
cat /job/root/etc/passwd
cat /job/root/etc/group
cat /job/report.json
statns /job/root/var/lib/chrony
umount-all
GUEST
timeout --kill-after=10 180 guestfish --ro --format=raw -a "$work/guest.raw" \
    -f "$work/read.commands" > "$work/readback.log" 2>&1
sha256sum -c "$work/guest.sha256"
uid=$(jq -er .chrony_uid "$work/report.json")
gid=$(jq -er .chrony_gid "$work/report.json")
grep -Fxq "st_uid: $uid" "$work/readback.log"
grep -Fxq "st_gid: $gid" "$work/readback.log"
grep -Eq "^chrony:[^:]*:$uid:$gid:" "$work/readback.log"
cat "$work/report.json"
printf 'UKE_COPR_GUEST_ROOT signed_fedora_inputs=%d native_dnf=true scriptlets=true independent_readback=true readback_unchanged=true full_os_composition=false hardware_tested=false\n' "$PUBLIC_COPR_SDK_RPMS"
# This independent appliance reads the actual populated image, not its SDK tree.
sha256sum "$work/root.raw" > "$work/root.sha256"
cat > "$work/image-read.commands" <<GUEST
set-smp 2
set-memsize 1024
set-network false
run
vfs-type /dev/sda
vfs-label /dev/sda
mount-options ro,noload /dev/sda /
getxattr /etc/passwd security.selinux
statns /var/lib/chrony
tar-out / $work/root-readback.tar numericowner:true xattrs:true acls:true excludes:lost+found
umount-all
GUEST
timeout --kill-after=10 300 guestfish --ro --format=raw -a "$work/root.raw" \
    -f "$work/image-read.commands" > "$work/image-readback.log" 2>&1
sha256sum -c "$work/root.sha256"
grep -Fxq ext4 "$work/image-readback.log"
grep -Fxq UKE_LINUX "$work/image-readback.log"
grep -aFq passwd_file_t "$work/image-readback.log"
grep -Fxq "st_uid: $uid" "$work/image-readback.log"
grep -Fxq "st_gid: $gid" "$work/image-readback.log"
cat > "$work/compare.commands" <<GUEST
set-smp 2
set-memsize 2048
set-network false
run
mount /dev/sda /
upload $work/root-readback.tar /job/root-readback.tar
command-out "/usr/bin/bash /builder/tests/copr-guest-compare.sh" -
sync
umount-all
GUEST
timeout --kill-after=20 600 guestfish --rw --format=raw -a "$work/guest.raw" -f "$work/compare.commands"
"$recipe/build-tools/android-sparse" encode "$work/root.raw" "$work/root.img"
"$recipe/build-tools/android-sparse" decode "$work/root.img" "$work/decoded.raw"
cmp "$work/root.raw" "$work/decoded.raw"
unlink "$work/decoded.raw"
simg2img "$work/root.img" "$work/aosp.raw"
cmp "$work/root.raw" "$work/aosp.raw"
printf '%s\n' 'UKE_COPR_EXT4_IMAGE policy_labels=true independent_readback=true readback_unchanged=true sparse_roundtrip=true independent_aosp_decoder=true full_os_composition=false hardware_tested=false'
# The same full producer function must succeed for all four declared formats.
# shellcheck source=filesystem-commands.sh
# shellcheck disable=SC1091
source "$recipe/src/public/filesystem-commands.sh"
# shellcheck source=copr-filesystem.sh
# shellcheck disable=SC1091
source "$recipe/src/public/copr-filesystem.sh"
# The real image caller starts after a child root producer; it inherits no SDK env.
unset LIBGUESTFS_BACKEND LIBGUESTFS_BACKEND_SETTINGS LIBGUESTFS_CACHEDIR LIBGUESTFS_TMPDIR
for filesystem in ext4 f2fs xfs btrfs; do
    public_copr_filesystem "$work/guest.raw" "$work/rootfs.tar" "$filesystem" 1024 \
        "$work/$filesystem" /builder/build-tools "$recipe/build-tools"
    jq -e --arg fs "$filesystem" '.filesystem==$fs and .content_readback and .metadata_readback and
        .policy_contexts_verified and .readback_unchanged and .sparse_roundtrip and
        .independent_aosp_decoder and (.hardware_tested==false)' "$work/$filesystem/report.json"
done
printf '%s\n' 'UKE_COPR_FOUR_FILESYSTEMS complete_declared_formats=true bounded_root=true full_os_composition=false hardware_tested=false'
