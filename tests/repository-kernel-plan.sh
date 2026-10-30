#!/usr/bin/env bash
# No network or containers: repository kernel selection must remain explicitly admitted.
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
for rpm in latest 7.3.0-48.fc46; do
    (public_main --kernel-rpm "$rpm" --build image --mode singleboot --filesystem ext4 --dry-run) > "$work/plan"
    grep -F 'Kernel input: signed testing RPMs' "$work/plan" >/dev/null
done
for options in '--kernel-rpm invalid' '--kernel-rpm 7.4-rc1' '--kernel-rpm 7.3.0-1.fc45' '--kernel-rpm latest --build kernel' '--kernel-rpm latest --channel stable' '--kernel-rpm latest --reuse-kernel' '--kernel-rpm latest --kernel 7.3' '--kernel-rpm latest --kernel-profile el2-require'; do
    status=0
    # Intentional splitting of fixed fixture option strings.
    # shellcheck disable=SC2086
    (public_main $options --dry-run) > "$work/refused" 2>&1 || status=$?
    ((status > 0 && status < 90))
done
status=0
(UKE_KERNEL_REPO="$root" public_main --kernel-rpm latest --dry-run) > "$work/refused" 2>&1 || status=$?
((status > 0 && status < 90))
printf 'Signed repository kernel plans and incompatible source/channel/profile refusals passed\n'
