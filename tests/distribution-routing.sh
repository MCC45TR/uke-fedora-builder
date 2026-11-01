#!/usr/bin/env bash
# Host-only routing fixtures: forbidden backends must never reach preparation.
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../src/image/core.sh
# shellcheck disable=SC1091
source "$root/src/image/core.sh"
# shellcheck source=../src/public/entry.sh
# shellcheck disable=SC1091
source "$root/src/public/entry.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
bootstrap() { exit 90; }
public_worker() { exit 91; }
public_stage() { exit 92; }
image_main() { printf 'legacy:%s\n' "$*"; }
for distro in ubuntu arch invalid ''; do
    for target in image kernel core boot boot-pair; do
        for syntax in equal separate; do
            args=("--distro=$distro")
            [[ $syntax == equal ]] || args=(--distro "$distro")
            status=0
            (public_main "${args[@]}" --build "$target" --yes --dry-run) > "$fixture/refusal" 2>&1 || status=$?
            [[ $status == 1 ]]
            if grep -q 'legacy:' "$fixture/refusal"; then exit 1; fi
            if [[ $distro == ubuntu || $distro == arch ]]; then
                grep -q 'unsupported; native image backend is not implemented' "$fixture/refusal"
            fi
        done
    done
done
status=0
(public_main --distro) >/dev/null 2>&1 || status=$?
[[ $status == 1 ]]
public_main --build-from-source --dry-run > "$fixture/default"
public_main --distro fedora --build-from-source --dry-run > "$fixture/explicit"
cmp "$fixture/default" "$fixture/explicit"
public_main --distro=fedora --build core --dry-run > "$fixture/legacy"
grep -qx 'legacy:--build core --dry-run' "$fixture/legacy"
printf '%s\n' 'Distribution routing: Fedora parity and unsupported backend refusals passed.'
