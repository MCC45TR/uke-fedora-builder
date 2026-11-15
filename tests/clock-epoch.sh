#!/usr/bin/env bash
# Compose metadata only. No host clock, clock service or block-device changes.
set -Eeuo pipefail
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/public/first-boot-policy.sh
# shellcheck disable=SC1091
source "$builder/src/public/first-boot-policy.sh"
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
epoch=1794334272
reject() { if "$@"; then printf 'Unexpected epoch admission\n' >&2; exit 1; fi; }
mkdir -p "$work/root/usr/lib"
printf 'original Fedora file\n' > "$work/root/usr/lib/clock-epoch"
sha256sum "$work/root/usr/lib/clock-epoch" > "$work/fedora.sha256"
public_clock_epoch "$work/root" "$epoch"
clock=$work/root/var/lib/systemd/timesync/clock
[[ $(stat -c '%Y %a %s' "$clock") == "$epoch 644 0" ]]
public_clock_epoch "$work/root" "$epoch"
sha256sum -c --strict --quiet "$work/fedora.sha256"
reject public_clock_epoch "$work/root" 0
reject public_clock_epoch "$work/root" 1234567890
reject public_clock_epoch "$work/root" "$(( $(date -u +%s) + 86400 ))"
reject public_clock_epoch / "$epoch"
printf 'unexpected existing state\n' > "$clock"
reject public_clock_epoch "$work/root" "$epoch"
grep -Fx 'unexpected existing state' "$clock" >/dev/null
unlink "$clock"
printf 'outside state\n' > "$work/outside"
ln -s "$work/outside" "$clock"
reject public_clock_epoch "$work/root" "$epoch"
grep -Fx 'outside state' "$work/outside" >/dev/null
unlink "$clock"
truncate -s 0 "$work/empty-outside"
ln "$work/empty-outside" "$clock"
reject public_clock_epoch "$work/root" "$epoch"
[[ $(stat -c %h "$work/empty-outside") == 2 ]]
unlink "$clock"
public_clock_epoch "$work/root" "$epoch"
# The real Fedora EXT4 formatter must preserve the standard epoch's mtime.
truncate -s 16M "$work/root.ext4"
mkfs.ext4 -q -F -d "$work/root" "$work/root.ext4"
debugfs -R 'stat /var/lib/systemd/timesync/clock' "$work/root.ext4" > "$work/inode" 2>/dev/null
hex=$(printf '%08x' "$epoch")
grep -Eq "mtime: 0x$hex:" "$work/inode"
printf 'Standard systemd epoch: sane floor, repeat, state/symlink/future refusal, original Fedora preservation and real EXT4 mtime passed.\n'
