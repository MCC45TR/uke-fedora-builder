#!/usr/bin/env bash
# Run as root inside a SYS_ADMIN-enabled disposable worker, or via sudo in CI.
set -Eeuo pipefail
[[ $(id -u) == 0 ]]
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
pids=()
# shellcheck disable=SC2329
cleanup() {
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || :; done
    for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || :; done
    rm -rf -- "$work"
}
trap 'cleanup' EXIT
parent=$(readlink /proc/self/ns/user)
awk '{print $1, $3}' /proc/self/uid_map > "$work/parent-uids"
awk '{print $1, $3}' /proc/self/gid_map > "$work/parent-gids"
cat /proc/self/setgroups > "$work/parent-setgroups"
cat > "$work/probe.sh" <<'BASH'
set -Eeuo pipefail
work=$1 parent=$2 index=$3
[[ $(id -u) == 0 && $(readlink /proc/self/ns/user) != "$parent" ]]
printf '%s\n' "$(readlink /proc/self/ns/user)" > "$work/namespace-$index"
awk '{if ($1!=$2) exit 1; print $1, $3}' /proc/self/uid_map > "$work/uids-$index"
awk '{if ($1!=$2) exit 1; print $1, $3}' /proc/self/gid_map > "$work/gids-$index"
cmp "$work/parent-uids" "$work/uids-$index"
cmp "$work/parent-gids" "$work/gids-$index"
cmp "$work/parent-setgroups" /proc/self/setgroups
if [[ $(< /proc/self/setgroups) == allow ]]; then
    [[ $(setpriv --reuid 65534 --regid 65534 --groups 65534 id -u) == 65534 ]]
fi
touch "$work/owner-$index"
chown 65534:65534 "$work/owner-$index"
[[ $(stat -c %u:%g "$work/owner-$index") == 65534:65534 ]]
mountpoint=$work/binfmt-$index
mkdir "$mountpoint"
mount -t binfmt_misc binfmt_misc "$mountpoint"
trap 'umount "$mountpoint"' EXIT
[[ ! -e $mountpoint/uke-worker-userns-fixture ]]
printf '%s\n' ':uke-worker-userns-fixture:M::UKE_WORKER_PROBE::/bin/false:F' > "$mountpoint/register"
[[ -e $mountpoint/uke-worker-userns-fixture ]]
touch "$work/ready-$index"
for ((attempt=0;attempt<50;attempt++)); do
    [[ -e $work/ready-1 && -e $work/ready-2 ]] && break
    sleep 0.1
done
[[ -e $work/ready-1 && -e $work/ready-2 ]]
printf 'UKE_WORKER_PROBE\n' > "$work/executable-$index"
chmod 755 "$work/executable-$index"
status=0
"$work/executable-$index" || status=$?
[[ $status == 1 ]]
BASH
for index in 1 2; do
    bash "$root/src/public/worker-namespace.sh" bash "$work/probe.sh" "$work" "$parent" "$index" &
    pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
pids=()
[[ $(cat "$work/namespace-1") != "$(cat "$work/namespace-2")" ]]
[[ ! -e /proc/sys/fs/binfmt_misc/uke-worker-userns-fixture ]]
printf 'Concurrent private binfmt registries, execution, UID/GID ranges and group policy: passed\n'
