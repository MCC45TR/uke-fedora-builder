#!/usr/bin/env bash
# COPR-only prerequisite probe: disposable guest disk, TCG, no host mounts or block devices.
set -Eeuo pipefail
[[ ${UKE_COPR_WORKER_AUDIT:-0} == 1 ]]
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export LIBGUESTFS_BACKEND=direct LIBGUESTFS_BACKEND_SETTINGS=force_tcg
export LIBGUESTFS_CACHEDIR=$work/cache LIBGUESTFS_TMPDIR=$work/tmp
mkdir "$LIBGUESTFS_CACHEDIR" "$LIBGUESTFS_TMPDIR"
truncate -s 64M "$work/disk.raw"
context=system_u:object_r:default_t:s0
cat > "$work/create.commands" <<GUEST
set-smp 1
set-memsize 512
set-network false
run
mkfs ext4 /dev/sda
mount /dev/sda /
write /proof "UKE_COPR_APPLIANCE_PROOF"
chown 65534 65534 /proof
setxattr security.selinux $context ${#context} /proof
sync
umount-all
GUEST
status=0
timeout --kill-after=10 180 guestfish --rw --format=raw -a "$work/disk.raw" -f "$work/create.commands" > "$work/create.log" 2>&1 || status=$?
printf 'UKE_IMAGE_APPLIANCE_PROBE create_exit=%d\n' "$status"
if [[ $status != 0 ]];then
    if grep -Fq 'Permission denied' "$work/create.log";then
        printf 'UKE_IMAGE_APPLIANCE_PROBE refusal=permission-denied\n'
    elif grep -Fq 'No suitable kernel' "$work/create.log";then
        printf 'UKE_IMAGE_APPLIANCE_PROBE refusal=kernel-unavailable\n'
    else
        printf 'UKE_IMAGE_APPLIANCE_PROBE refusal=unavailable-see-exit-status\n'
    fi
    printf 'UKE_IMAGE_APPLIANCE_PROBE image_built=false full_os_composition=false\n'
    exit 0
fi
sha256sum "$work/disk.raw" > "$work/disk.sha256"
cat > "$work/read.commands" <<GUEST
set-smp 1
set-memsize 512
set-network false
run
mount-options ro,noload /dev/sda /
cat /proof
statns /proof
getxattr /proof security.selinux
umount-all
GUEST
timeout --kill-after=10 180 guestfish --ro --format=raw -a "$work/disk.raw" -f "$work/read.commands" > "$work/read.log" 2>&1
sha256sum -c "$work/disk.sha256" > /dev/null
grep -Fxq UKE_COPR_APPLIANCE_PROOF "$work/read.log"
grep -Fxq 'st_uid: 65534' "$work/read.log"
grep -Fxq 'st_gid: 65534' "$work/read.log"
grep -aFq "$context" "$work/read.log"
printf 'UKE_IMAGE_APPLIANCE_PROBE tcg=true numeric_owner=true selinux_xattr=true independent_readback=true host_image_unchanged_after_read=true\n'
printf 'UKE_IMAGE_APPLIANCE_PROBE full_os_composition=false hardware_tested=false\n'
