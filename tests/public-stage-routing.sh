#!/usr/bin/env bash
# Stage routing only; the injected engine never starts a container.
# shellcheck disable=SC2034
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/image/core.sh
# shellcheck disable=SC1091
source "$root/src/image/core.sh"
# shellcheck source=../src/public/entry.sh
# shellcheck disable=SC1091
source "$root/src/public/entry.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
ENGINE=podman WORK=$fixture output=$fixture JOBS=1 OFFLINE=1
# These replacements are invoked indirectly by the real stage function.
# shellcheck disable=SC2329
wait_idle() { :; }
# shellcheck disable=SC2329
podman() {
    case $1 in
        create) printf '%s\0' "$@" > "$fixture/stage-arguments"; printf 'fixture-container\n';;
        start|rm) :;;
        inspect) printf '0\n';;
        *) exit 93;;
    esac
}
for pair in 'linux/amd64 root' 'linux/amd64 kernel' 'linux/amd64 filesystem' 'linux/arm64 root'; do
    read -r platform stage <<< "$pair"
    public_stage fixture-image "$platform" "$stage"
    mapfile -d '' -t arguments < "$fixture/stage-arguments"
    namespace=0 capability=0
    for argument in "${arguments[@]}"; do
        [[ $argument != /builder/src/public/worker-namespace.sh ]] || namespace=1
        [[ $argument != SYS_ADMIN ]] || capability=1
    done
    if [[ $pair == 'linux/amd64 root' ]]; then
        [[ $namespace == 1 && $capability == 1 ]]
    else
        [[ $namespace == 0 ]]
    fi
    if [[ $stage == root ]]; then [[ $capability == 1 ]]; else [[ $capability == 0 ]]; fi
    [[ ${arguments[-1]} == "$stage" ]]
done
printf 'Root stages allow temporary proc mounts; only x86_64 cross-install roots use a private user namespace: passed\n'
