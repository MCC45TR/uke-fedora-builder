#!/usr/bin/env bash
# Real local image round trip; creates only a disposable scratch image/container.
# shellcheck disable=SC2034
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/image/core.sh
# shellcheck disable=SC1091
source "$root/src/image/core.sh"
# shellcheck source=../src/public/entry.sh
# shellcheck disable=SC1091
source "$root/src/public/entry.sh"
ENGINE=${1:-podman}
WORK=$(mktemp -d /tmp/uke-worker-snapshot.XXXXXX)
tag=localhost/uke-worker-fixture:$(basename "$WORK")
image='' container=''
finish() {
    [[ -z $container ]] || "$ENGINE" rm "$container" > /dev/null 2>&1 || true
    [[ -z $image ]] || "$ENGINE" image rm -f "$image" > /dev/null 2>&1 || true
    "$ENGINE" image rm -f "$tag" > /dev/null 2>&1 || true
    find "$WORK" -depth -delete
}
trap finish EXIT
mkdir -p "$WORK/context" "$WORK/inputs"
printf 'worker archive fixture %s\n' "$WORK" > "$WORK/context/payload"
printf 'FROM scratch\nCOPY payload /payload\n' > "$WORK/context/Containerfile"
"$ENGINE" build --network=none -t "$tag" -f "$WORK/context/Containerfile" "$WORK/context" > "$WORK/build.log" 2>&1
image=$("$ENGINE" image inspect --format '{{.Id}}' "$tag")
image=sha256:${image#sha256:}
[[ $(public_snapshot_worker "$tag") == "$image" ]]
[[ $(public_snapshot_worker "$image") == "$image" ]]
[[ $(find "$WORK/inputs" -type f | wc -l) == 1 ]]
archive=$WORK/inputs/worker-${image#sha256:}.tar
"$ENGINE" image rm "$tag" > /dev/null
if "$ENGINE" image inspect "$image" > /dev/null 2>&1; then exit 1; fi
"$ENGINE" load --input "$archive" > "$WORK/load.log" 2>&1
restored=$("$ENGINE" image inspect --format '{{.Id}}' "$image")
[[ sha256:${restored#sha256:} == "$image" ]]
container=$("$ENGINE" create "$image" /unused)
"$ENGINE" cp "$container:/payload" "$WORK/readback"
cmp "$WORK/context/payload" "$WORK/readback"
if public_snapshot_worker localhost/uke-worker-fixture:missing > /dev/null 2>&1; then exit 1; fi
echo 'Worker archive restores the exact image ID and payload after local removal; repeated/missing-image checks passed'
