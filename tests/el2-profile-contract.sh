#!/usr/bin/env bash
# Prepared for later authorization; no packages, containers or devices.
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$root/src/image/core.sh"
source "$root/src/public/entry.sh"
bootstrap() { echo 'Unexpected host preparation' >&2; exit 90; }
public_worker() { exit 91; }
public_stage() { exit 92; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
public_main --build kernel --kernel 7.3 --kernel-profile el2-require --channel testing --skip-tests --dry-run > "$work/plan"
grep -F 'Kernel profile: el2-require; kernel tests enabled: 0' "$work/plan"
for profile in el2-exit-experimental invalid; do
    status=0
    (public_main --build kernel --kernel-profile "$profile" --dry-run) > "$work/refused" 2>&1 || status=$?
    ((status > 0 && status < 90))
done
KERNEL_PROFILE=normal RUN_TESTS=1 KERNEL_CONFIG_SHA=one
normal=$(kernel_producer_json native recipe worker)
KERNEL_PROFILE=el2-require
require=$(kernel_producer_json native recipe worker)
[[ $normal != "$require" ]]
RUN_TESTS=0
[[ $require != "$(kernel_producer_json native recipe worker)" ]]
KERNEL_CONFIG_SHA=two
[[ $require != "$(kernel_producer_json native recipe worker)" ]]
[[ $(kernel_version_resolve 7.3 "$work/unused" "$work/unused" 1) == 7.3.0 ]]
