#!/usr/bin/env bash
# Stage command construction only; the injected engine never starts a container.
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
# Keep the optional real /dev/kvm branch out of this host-independent fixture.
host_platform=fixture/no-kvm
# These replacements are invoked indirectly by the real stage function.
# shellcheck disable=SC2329
wait_idle() { :; }
# shellcheck disable=SC2329
podman() {
    case $1 in
        create) printf '%s\0' "$@" > "$fixture/stage-arguments"; printf 'fixture-container\n';;
        start|rm) :;;
        inspect) printf '%s\n' "${fixture_exit_code:-0}";;
        *) exit 93;;
    esac
}
for fedora_release in 44 45 rawhide; do
 for channel in testing stable unstable; do
  for pair in 'linux/amd64 root' 'linux/amd64 kernel' 'linux/amd64 filesystem' 'linux/arm64 root'; do
    read -r platform stage <<< "$pair"
    public_stage fixture-image "$platform" "$stage"
    mapfile -d '' -t arguments < "$fixture/stage-arguments"
    privileged=0 cache=0 recipe=0 network=0
    for argument in "${arguments[@]}"; do
        # Current main 4bcadc6 uses a privileged root worker directly. Neither
        # the historical namespace wrapper nor an extra capability is selected.
        [[ $argument != /builder/src/public/worker-namespace.sh && $argument != SYS_ADMIN ]]
        [[ $argument != --privileged ]] || privileged=$((privileged + 1))
        [[ $argument != "$output/cache/fedora-$fedora_release-$channel:/cache" ]] || cache=$((cache + 1))
        [[ $argument != "$WORK/recipe:/builder:ro" ]] || recipe=$((recipe + 1))
        [[ $argument != --network=none ]] || network=$((network + 1))
        [[ $argument != --device ]]
    done
    if [[ $stage == root ]]; then [[ $privileged == 1 ]]; else [[ $privileged == 0 ]]; fi
    [[ $cache == 1 && $recipe == 1 && $network == 1 ]]
    [[ ${arguments[-3]} == bash && ${arguments[-2]} == /builder/src/public/stage.sh && ${arguments[-1]} == "$stage" ]]
  done
 done
done
# Do not hide an unsuccessful worker behind a successful engine invocation.
if (fixture_exit_code=7; public_stage fixture-image linux/arm64 root) > "$fixture/refused" 2>&1; then
    echo 'Failed worker accepted' >&2; exit 1
fi
printf '36 stage routes: root-only privilege, exact target/channel cache, read-only recipe, offline network and failed-worker refusal passed; no container executed\n'
