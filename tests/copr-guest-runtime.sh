#!/usr/bin/env bash
# Real mount ownership/refusal controls, only inside the disposable COPR SDK.
set -Eeuo pipefail
[[ $(id -u) == 0 && -f /.uke-copr-sdk && $(< /.uke-copr-sdk) == 1 ]]
source /builder/src/public/guest-runtime.sh
work=$(mktemp -d /job/runtime.XXXXXX)
PUBLIC_GUEST_MOUNTS=()
probe_mounted=0
cleanup() {
    local status=$?
    public_guest_unmounts || status=1
    if [[ $probe_mounted == 1 ]]; then umount /run || status=1; fi
    find "$work" -depth -delete
    exit "$status"
}
trap cleanup EXIT
snapshot() {
    local tree
    for tree in proc dev sys run; do
        findmnt --mountpoint "/$tree" --noheadings --raw --output ID,TARGET,FSTYPE
    done
}
snapshot > "$work/before"
public_guest_mounts
[[ ${#PUBLIC_GUEST_MOUNTS[@]} == 4 ]]
snapshot > "$work/owned"
if cmp -s "$work/before" "$work/owned"; then echo 'Owned virtual mounts were not created' >&2; exit 1; fi
public_guest_unmounts
PUBLIC_GUEST_MOUNTS=()
snapshot > "$work/after"
cmp "$work/before" "$work/after"
# A real unexpected filesystem must refuse before changing any other mount.
mount -t proc -o nosuid,nodev,noexec proc /run
probe_mounted=1
snapshot > "$work/probe"
if public_guest_mounts > "$work/refusal" 2>&1; then echo 'Unexpected virtual filesystem accepted' >&2; exit 1; fi
grep -F 'Unexpected SDK virtual filesystem at /run: proc (expected tmpfs)' "$work/refusal"
[[ ${#PUBLIC_GUEST_MOUNTS[@]} == 0 ]]
public_guest_unmounts
snapshot > "$work/refused"
cmp "$work/probe" "$work/refused"
umount /run
probe_mounted=0
snapshot > "$work/restored"
cmp "$work/before" "$work/restored"
printf '%s\n' 'UKE_COPR_GUEST_RUNTIME owned_layers=true appliance_mounts_preserved=true unexpected_filesystem_refused=true hardware_tested=false'
