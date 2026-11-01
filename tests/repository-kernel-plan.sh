#!/usr/bin/env bash
# No network or containers: default package routing and explicit source opt-in.
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/image/core.sh
# shellcheck disable=SC1091
source "$root/src/image/core.sh"
# shellcheck source=../src/public/entry.sh
# shellcheck disable=SC1091
source "$root/src/public/entry.sh"
bootstrap() { exit 90; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
for channel in stable testing unstable; do
    for rpm in latest 7.3.0-48.fc46; do
        public_main --kernel-rpm "$rpm" --channel "$channel" --mode singleboot --filesystem ext4 --dry-run > "$work/plan"
        grep -F "Kernel input: signed $channel RPMs" "$work/plan" >/dev/null
    done
    public_main --channel "$channel" --dry-run > "$work/default"
    grep -F "Kernel input: signed $channel RPMs (latest)" "$work/default" >/dev/null
    public_main --build-from-source --channel "$channel" --dry-run > "$work/source"
    if grep -F 'Kernel input: signed' "$work/source"; then exit 1; fi
done
for options in '--kernel-rpm invalid' '--kernel-rpm 7.4-rc1' '--kernel-rpm 7.3.0-1.fc45' '--kernel-rpm latest --build kernel' '--kernel-rpm latest --build-from-source' '--reuse-kernel' '--kernel 7.3' '--kernel-profile el2-require'; do
    status=0
    # Intentional splitting of fixed fixture option strings.
    # shellcheck disable=SC2086
    (public_main $options --dry-run) > "$work/refused" 2>&1 || status=$?
    ((status > 0 && status < 90))
done
jq -e '.channels.unstable.project == "uke-linux-unstable" and .channels.unstable.project != .channels.testing.project' "$root/configs/public-build.json" >/dev/null
for desktop in cutefish nextkde; do
    status=0
    (public_main --desktop "$desktop" --yes) > "$work/refused" 2>&1 || status=$?
    ((status > 0 && status < 90))
done
printf 'Default signed package routes, distinct unstable repository, source opt-in and desktop routing passed\n'
