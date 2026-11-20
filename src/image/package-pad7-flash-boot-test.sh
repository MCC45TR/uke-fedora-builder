#!/usr/bin/env bash
# Package the exact image reported to boot with the temporary Fastboot command.
set -Eeuo pipefail
export LC_ALL=C
[[ $# == 2 && -f $1 && ! -e $2 ]]
boot=$(realpath "$1")
output=$(realpath -m "$2")
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
printf '%s  %s\n' 64b0cd8b29e3087475530369fc18a1ec9282dd6e22c97339a3148d2aa41b6529 "$boot" |
    sha256sum -c --strict
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
cp "$repo/configs/images/stable-super-fastboot/android-info.txt" "$work/"
printf 'version 1\nflash boot boot.img\n' > "$work/fastboot-info.txt"
ln -s "$boot" "$work/boot.img"
(cd "$work"; zip -q -1 "$output" android-info.txt fastboot-info.txt boot.img)
unzip -tq "$output"
unzip -p "$output" boot.img | cmp - "$boot"
bash "$repo/tests/temporary-fastboot-boot.sh" "$boot" "$output"
