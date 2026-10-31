#!/usr/bin/env bash
# COPR-only prerequisite probe: disposable guest disk, TCG, no host mounts or block devices.
set -Eeuo pipefail
[[ ${UKE_COPR_WORKER_AUDIT:-0} == 1 ]]
recipe=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$recipe/src/public/guest-appliance.sh"
source "$recipe/src/public/filesystem-commands.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export LIBGUESTFS_BACKEND=direct LIBGUESTFS_BACKEND_SETTINGS=force_tcg
export LIBGUESTFS_CACHEDIR=$work/cache LIBGUESTFS_TMPDIR=$work/tmp
mkdir "$LIBGUESTFS_CACHEDIR" "$LIBGUESTFS_TMPDIR"
public_guest_appliance "$work/appliance"
truncate -s 1G "$work/disk.raw"
context=system_u:object_r:default_t:s0
{
cat <<GUEST
set-smp 1
set-memsize 512
set-network false
run
GUEST
for filesystem in f2fs xfs btrfs ext4; do
    printf 'echo UKE_IMAGE_APPLIANCE_FORMAT_START filesystem=%s\n' "$filesystem"
    printf 'wipefs /dev/sda\n'
    public_filesystem_format "$filesystem"
    # The disk is reformatted repeatedly; mount the declared type explicitly.
    printf 'vfs-type /dev/sda\nmount-vfs "" %s /dev/sda /\ntouch /format-proof\nsync\numount-all\n' "$filesystem"
    # Exercise the production non-recovery read options before the long root job.
    read_options=$(public_filesystem_ro_options "$filesystem")
    printf 'mount-vfs "%s" %s /dev/sda /\ncat /format-proof\numount-all\n' "$read_options" "$filesystem"
    printf 'echo UKE_IMAGE_APPLIANCE_READ_OPTION_PASS filesystem=%s\n' "$filesystem"
    printf 'echo UKE_IMAGE_APPLIANCE_FORMAT_PASS filesystem=%s\n' "$filesystem"
done
cat <<GUEST
mount-vfs "" ext4 /dev/sda /
write /proof "UKE_COPR_APPLIANCE_PROOF\n"
chown 65534 65534 /proof
setxattr security.selinux $context ${#context} /proof
sync
umount-all
GUEST
} > "$work/create.commands"
status=0
LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1 \
timeout --kill-after=20 600 guestfish --rw --format=raw -a "$work/disk.raw" -f "$work/create.commands" > "$work/create.log" 2>&1 || status=$?
printf 'UKE_IMAGE_APPLIANCE_PROBE create_exit=%d\n' "$status"
if [[ $status != 0 ]];then
    cat "$work/create.log" >&2
    if grep -Fq 'Permission denied' "$work/create.log";then
        printf 'UKE_IMAGE_APPLIANCE_PROBE refusal=permission-denied\n'
    elif grep -Fq 'No suitable kernel' "$work/create.log";then
        printf 'UKE_IMAGE_APPLIANCE_PROBE refusal=kernel-unavailable\n'
    else
        printf 'UKE_IMAGE_APPLIANCE_PROBE refusal=unavailable-see-exit-status\n'
    fi
    printf 'UKE_IMAGE_APPLIANCE_PROBE image_built=false full_os_composition=false\n'
    exit "$status"
fi
for filesystem in ext4 f2fs xfs btrfs; do
    grep -Fxq "$filesystem" "$work/create.log"
    grep -Fxq "UKE_IMAGE_APPLIANCE_FORMAT_PASS filesystem=$filesystem" "$work/create.log"
    grep -Fxq "UKE_IMAGE_APPLIANCE_READ_OPTION_PASS filesystem=$filesystem" "$work/create.log"
done
printf 'UKE_IMAGE_APPLIANCE_FORMATTERS ext4=true f2fs=true xfs=true btrfs=true basic_mounts=true\n'
printf 'UKE_IMAGE_APPLIANCE_READ_OPTIONS ext4=true f2fs=true xfs=true btrfs=true non_recovery_options_accepted=true\n'
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
