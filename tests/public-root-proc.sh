#!/usr/bin/env bash
# Run in a disposable SYS_ADMIN-enabled worker; no host device is opened.
set -Eeuo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../src/public/root-proc.sh
# shellcheck disable=SC1091
source "$repo/src/public/root-proc.sh"
fixture=$(mktemp -d)
mkdir "$fixture/proc"
trap 'public_root_proc_unmount "$fixture"; find "$fixture" -depth -delete' EXIT
public_root_proc_mount "$fixture"
findmnt --mountpoint "$fixture/proc" --noheadings -o OPTIONS | grep -Eq '(^|,)ro(,|$)'
test -L "$fixture/proc/self/fd/1"
public_root_proc_unmount "$fixture"
public_root_proc_unmount "$fixture"
rmdir "$fixture/proc"
ln -s /proc "$fixture/proc"
if public_root_proc_mount "$fixture"; then exit 1; fi
unlink "$fixture/proc"
mkdir "$fixture/proc"
printf '%s\n' 'Read-only proc, descriptor visibility, complete detach, repeated cleanup and symlink refusal passed'
