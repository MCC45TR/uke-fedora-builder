#!/usr/bin/env bash
# Run only on the disposable COPR native worker. All disks are new regular files.
# A public-RPM SDK supplies native DNF; ownership never passes through host extraction.
set -Eeuo pipefail
[[ ${UKE_COPR_WORKER_AUDIT:-0} == 1 && $# == 2 && -d $1 && -d $2 ]]
recipe=$(realpath "$1") inputs=$(realpath "$2")
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
[[ $recipe =~ ^/[A-Za-z0-9_./+-]+$ && $inputs =~ ^/[A-Za-z0-9_./+-]+$ && $work =~ ^/[A-Za-z0-9_./+-]+$ ]]
export LIBGUESTFS_BACKEND=direct LIBGUESTFS_BACKEND_SETTINGS=force_tcg
export LIBGUESTFS_CACHEDIR=$work/cache LIBGUESTFS_TMPDIR=$work/tmp
mkdir "$work/cache" "$work/tmp" "$work/keydb" "$work/job"
(cd "$inputs"; sha256sum -c SHA256SUMS > "$work/input-hashes.log")
rpmkeys --dbpath "$work/keydb" --import "$recipe/configs/keys/fedora-46.asc"
shopt -s nullglob
archives=("$inputs/rpms/"*.rpm)
(( ${#archives[@]} > 0 ))
tar -cf "$work/sdk.tar" --files-from /dev/null
for archive in "${archives[@]}"; do
    [[ $(rpm -qp --qf '%{VENDOR}' "$archive") == 'Fedora Project' ]]
    case $(rpm -qp --qf '%{ARCH}' "$archive") in aarch64|noarch) ;; *) exit 1;; esac
    rpmkeys --dbpath "$work/keydb" --checksig "$archive" | grep -F 'signatures OK'
    rpm2cpio "$archive" > "$work/payload.cpio"
    bsdtar -tf "$work/payload.cpio" > "$work/payload.paths"
    awk '/^\// || /(^|\/)\.\.(\/|$)/ {bad=1} END {exit bad}' "$work/payload.paths"
    # libarchive imports CPIO metadata directly, including numeric owners and links.
    # No host chown, fakeroot, mutable configuration or installed RPM DB is involved.
    bsdtar --format=gnutar -cf "$work/payload.tar" "@$work/payload.cpio"
    tar --concatenate -f "$work/sdk.tar" "$work/payload.tar"
done
tar -cf "$work/recipe.tar" -C "$recipe" src/public/root-proc.sh src/public/root-transaction.sh \
    tests/copr-guest-transaction.sh configs/keys/fedora-46.asc
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
mkdir-p /builder
tar-in $work/recipe.tar /builder
mkdir-p /inputs
tar-in $work/inputs.tar /inputs
mkdir-p /job
command-out "/usr/bin/bash /builder/tests/copr-guest-transaction.sh" -
download /job/report.json $work/report.json
download /job/installed-rpms.tsv $work/installed-rpms.tsv
sync
umount-all
GUEST
status=0
timeout --kill-after=20 1800 guestfish --rw --format=raw -a "$work/guest.raw" \
    -f "$work/create.commands" 2>&1 | tee "$work/guestfish.log" || status=$?
if [[ $status != 0 ]]; then cat "$work/guestfish.log" >&2; exit "$status"; fi
jq -e '.native_dnf and .scriptlets and .dependency_check and .numeric_owner and
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
printf 'UKE_COPR_GUEST_ROOT signed_fedora_inputs=%d native_dnf=true scriptlets=true independent_readback=true readback_unchanged=true full_os_composition=false hardware_tested=false\n' "${#archives[@]}"
