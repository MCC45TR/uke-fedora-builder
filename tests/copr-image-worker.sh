#!/usr/bin/env bash
# COPR-only environment evidence. Does not run the composer or change host policy.
set -Eeuo pipefail
[[ ${UKE_COPR_WORKER_AUDIT:-0} == 1 ]]
owner=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/mount"
probe() {
    local label=$1 status=0
    shift
    timeout --kill-after=2 15 "$@" > "$work/$label.log" 2>&1 || status=$?
    printf 'UKE_IMAGE_WORKER_PROBE %s exit=%d\n' "$label" "$status"
    [[ $status != 124 && $status != 137 ]] || return 1
    printf '%s\n' "$status" > "$work/$label.status"
}
printf 'UKE_IMAGE_WORKER_PROBE root_identity=%s\n' "$([[ $(id -u) == 0 ]] && printf true || printf false)"
probe current_identity_wrapper bash "$owner/src/public/worker-namespace.sh" /usr/bin/true
probe mapped_root_mount unshare --user --map-root-user --mount --propagation private --pid --fork --mount-proc \
    /bin/bash -euc 'test "$(id -u)" = 0; mount -t tmpfs tmpfs "$1"; touch "$1/probe"; chroot / /usr/bin/true; umount "$1"' probe "$work/mount"
probe subordinate_ids unshare --user --map-auto --map-root-user --mount --propagation private --pid --fork --mount-proc \
    /bin/bash -euc 'test "$(id -u)" = 0; mount -t tmpfs tmpfs "$1"; touch "$1/probe"; chown 65534:65534 "$1/probe"; test "$(stat -c %u:%g "$1/probe")" = 65534:65534; umount "$1"' probe "$work/mount"
for name in current_identity_wrapper mapped_root_mount subordinate_ids;do
    status=$(cat "$work/$name.status")
    if [[ $status != 0 ]];then
        # Keep generic operation failures, excluding worker paths, usernames and IDs.
        if grep -Fq 'Operation not permitted' "$work/$name.log";then
            printf 'UKE_IMAGE_WORKER_PROBE %s refusal=operation-not-permitted\n' "$name"
        elif grep -Fq 'No subuid' "$work/$name.log";then
            printf 'UKE_IMAGE_WORKER_PROBE %s refusal=no-subuid-range\n' "$name"
        else
            printf 'UKE_IMAGE_WORKER_PROBE %s refusal=unavailable-see-exit-status\n' "$name"
        fi
    fi
done
printf 'UKE_IMAGE_WORKER_PROBE scope=prerequisites-only image_built=false hardware_tested=false\n'
