#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
relative=usr/lib/modules/fixture/kernel/drivers
mkdir -p "$fixture/initramfs/$relative" "$fixture/root/$relative"
check() { bash "$root/src/boot-pair/check-initramfs-modules.sh" "$fixture/initramfs" "$fixture/root" fixture; }
reject() { if check >/dev/null 2>&1; then echo 'Invalid early module tuple accepted' >&2; exit 1; fi; }
reject
printf 'reviewed module\n' > "$fixture/root/$relative/test.ko.zst"
cp "$fixture/root/$relative/test.ko.zst" "$fixture/initramfs/$relative/test.ko.zst"
check
printf 'older module\n' > "$fixture/initramfs/$relative/test.ko.zst"
reject
cp "$fixture/root/$relative/test.ko.zst" "$fixture/initramfs/$relative/test.ko.zst"
rm "$fixture/root/$relative/test.ko.zst"
reject
echo 'Empty, stale and absent root-module rejection: passed'
