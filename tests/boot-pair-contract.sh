#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../src/image/core.sh
# shellcheck disable=SC1091
source "$root/src/image/core.sh"
reject() { if (image_main --build boot-pair "$@") >/dev/null 2>&1; then echo 'Invalid pair request accepted' >&2; exit 1; fi; }
reject --distro debian --dry-run
reject --release 45 --dry-run
reject --jobs 0 --dry-run
reject --jobs
reject --device-dt
reject --kernel-cache
reject --unknown
(image_main --build boot-pair --offline --dry-run) | grep -F 'Two-image stock-ABL' >/dev/null
(image_main --build=boot-pair --help) | grep -F system.img >/dev/null
jq -e '.mode=="stock-abl-ext4-root" and .partition_changes==["boot_b","linux"] and .root_size_mib==3072 and .boot_tested==false and .hardware_tested==false' "$root/configs/boot/uke-boot-pair.json" >/dev/null
if rg -n '^\s*(fastboot|adb|dd .*of=/dev/|.*set-active)' "$root/src/boot-pair"; then echo 'Device mutation found' >&2; exit 1; fi
# Resume must preserve the frozen recipe and reject tampering, including when
# the development kernel has unrelated read-only Git objects below src/.
# shellcheck source=../src/boot-pair/entry.sh
# shellcheck disable=SC1091
source "$root/src/boot-pair/entry.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
kernel=$fixture/kernel
mkdir -p "$kernel/src/boot/vendor" "$kernel/src/upstream/.git/objects" "$kernel/patches/boot" "$kernel/tests"
touch "$kernel/src/boot/uke-abl.c" "$kernel/src/boot/prepare-abl-source.sh" \
    "$kernel/src/boot/sm7675-uke-ufs.dtso" "$kernel/src/boot/sm7675-uke-usb2.dtso" \
    "$kernel/src/boot/vendor/fdt_check.c" "$kernel/patches/boot/test.patch" \
    "$kernel/tests/abl-dt-check.cpp" "$kernel/tests/abl-dt-contract.sh"
printf 'unrelated read-only source\n' > "$kernel/src/upstream/.git/objects/sentinel"
chmod 444 "$kernel/src/upstream/.git/objects/sentinel"
BUILDER=$root WORK=$fixture/job
mkdir -p "$WORK/recipe" "$WORK/kernel-recipe" "$WORK/inputs"
recipe=$(pair_recipe_hash "$BUILDER" "$kernel")
pair_freeze_recipe "$kernel" "$recipe"
[[ ! -e $WORK/kernel-recipe/src/upstream ]]
chmod 444 "$WORK/kernel-recipe/src/boot/uke-abl.c"
pair_freeze_recipe "$kernel" "$recipe"
[[ $(stat -c %a "$WORK/kernel-recipe/src/boot/uke-abl.c") == 444 ]]
printf 'tamper\n' >> "$WORK/recipe/src/boot-pair/root-status.sh"
if (pair_freeze_recipe "$kernel" "$recipe") >/dev/null 2>&1; then echo 'Tampered frozen recipe accepted' >&2; exit 1; fi
echo 'Pair CLI, scope, non-mutation and frozen-recipe resume contracts passed'
