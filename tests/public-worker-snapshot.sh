#!/usr/bin/env bash
# Exercise the production worker builder against an immutable recipe copy.
# Worker archive export was retired; the production path retains a frozen recipe.
# shellcheck disable=SC2034
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/image/core.sh
# shellcheck disable=SC1091
source "$root/src/image/core.sh"
# shellcheck source=../src/public/entry.sh
# shellcheck disable=SC1091
source "$root/src/public/entry.sh"
ENGINE=${1:-docker}
WORK=$(mktemp -d /tmp/uke-worker-recipe.XXXXXX)
tag=localhost/uke-worker-fixture:$(basename "$WORK")
container=''
finish() {
    [[ -z $container ]] || "$ENGINE" rm "$container" >/dev/null 2>&1 || true
    "$ENGINE" image rm -f "$tag" >/dev/null 2>&1 || true
    find "$WORK" -depth -delete
}
trap finish EXIT
mkdir -p "$WORK/live/configs" "$WORK/recipe"
printf 'frozen worker bytes\n' > "$WORK/live/configs/payload"
printf 'FROM scratch\nCOPY payload /payload\n' > "$WORK/live/configs/Containerfile"
cp -a "$WORK/live/configs" "$WORK/recipe/"
printf 'later live edit\n' > "$WORK/live/configs/payload"
OFFLINE=0
public_worker "$tag" "linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')" scratch Containerfile > "$WORK/build.log" 2>&1
identity=$("$ENGINE" image inspect --format '{{.Id}}' "$tag")
OFFLINE=1
public_worker "$tag" unused scratch Containerfile
[[ $("$ENGINE" image inspect --format '{{.Id}}' "$tag") == "$identity" ]]
container=$("$ENGINE" create "$tag" /unused)
"$ENGINE" cp "$container:/payload" "$WORK/readback"
cmp "$WORK/recipe/configs/payload" "$WORK/readback"
if cmp -s "$WORK/live/configs/payload" "$WORK/readback"; then exit 1; fi
if (public_worker "$tag-missing" unused scratch Containerfile) > "$WORK/refused" 2>&1; then exit 1; fi
printf 'Production worker uses frozen recipe bytes, reuses exact cached identity and rejects a missing offline worker\n'
