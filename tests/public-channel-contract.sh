#!/usr/bin/env bash
# Metadata and CLI only: no container, compiler or RPM generation.
# shellcheck disable=SC2034,SC1091
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../src/public/channel.sh
source "$root/src/public/channel.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
policy=$root/configs/public-build.json
for channel in stable testing unstable; do
    public_channel "$channel" "$policy"
    case $channel in stable) expected=uke-linux;; testing) expected=uke-linux-test;; unstable) expected=uke-linux-unstable;; esac
    [[ $PUBLIC_PROJECT == "$expected" && $PUBLIC_FINGERPRINT =~ ^[0-9A-F]{40}$ ]]
done
[[ $PUBLIC_FINGERPRINT == 2204A661EA630A5303500085538797E72A3E4ECA ]]
if public_channel invalid "$policy"; then exit 1; fi
jq '.channels.unstable=.channels.testing' "$policy" > "$work/alias.json"
if public_channel unstable "$work/alias.json"; then echo 'Test-repository alias admitted' >&2; exit 1; fi
jq '.channels.unstable.fingerprint=.channels.testing.fingerprint' "$policy" > "$work/key.json"
if public_channel unstable "$work/key.json"; then echo 'Wrong unstable key admitted' >&2; exit 1; fi
# shellcheck source=../src/image/core.sh
source "$root/src/image/core.sh"
# shellcheck source=../src/public/entry.sh
source "$root/src/public/entry.sh"
# shellcheck disable=SC2329
bootstrap() { exit 90; }
for target in image kernel; do
    (public_main --build "$target" --channel unstable --dry-run) > "$work/plan"
    grep -F 'Kernel input: signed unstable RPMs (latest)' "$work/plan" >/dev/null
done
for options in '--kernel 7.3.0' '--reuse-kernel' '--kernel-profile el2-require' '--release 44 --kernel-rpm latest' '--release 45 --kernel-rpm latest'; do
    status=0
    # Intentional splitting of fixed fixture arguments.
    # shellcheck disable=SC2086
    (public_main --channel unstable $options --dry-run) > "$work/refused" 2>&1 || status=$?
    ((status > 0 && status < 90))
done
for release in 44 45; do
    status=0
    (public_main --channel unstable --release "$release" --build kernel --yes) > "$work/refused" 2>&1 || status=$?
    ((status > 0 && status < 90))
done
bash "$root/tests/public-root-packages.sh"
bash "$root/tests/public-copr-root-contract.sh"
echo 'Three pinned channels, unstable repository defaults and alias/key/source/release refusals passed; no builds ran.'
