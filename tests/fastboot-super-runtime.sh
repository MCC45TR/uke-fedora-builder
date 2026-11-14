#!/usr/bin/env bash
# Native execution only inside the disposable, nonbootable dracut tool archive.
set -Eeuo pipefail
trap 'printf "UKE_SUPER_CHROOT_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
[[ $(uname -m) == aarch64 && -d /source/tests && -f /work/check.ext4 && ! -e /init ]]
for script in fastboot-singleboot-layout inspect-fastboot-super plan-super-provision provision-fastboot-super map-fastboot-rescue select-uke-super; do
    [[ -f /usr/libexec/uke-super/$script.sh ]]
done
if bash /usr/libexec/uke-super/select-uke-super.sh --identity-only > /work/physical-result.json 2> /work/physical-rejected.txt; then
    echo 'Tools-only chroot without Uke device tree admitted physical storage' >&2; exit 1
fi
grep -F 'device tree is unavailable' /work/physical-rejected.txt >/dev/null
bash /source/tests/fastboot-super-inspection.sh
bash /source/tests/fastboot-super-provision-plan.sh
e2fsck -fn /work/check.ext4
truncate -s 32M /work/check.ext4
resize2fs /work/check.ext4
dumpe2fs -h /work/check.ext4 > /work/header
[[ $(awk '/^Block count:/{print $3}' /work/header) == 8192 && $(awk '/^Block size:/{print $3}' /work/header) == 4096 ]]
[[ $(blkid -p -s LABEL -o value /work/check.ext4) == FEDORA_RESCUE ]]
truncate -s 16M /work/swap
mkswap --pagesize 4096 --label linux_swap /work/swap
[[ $(blkid -p -s TYPE -o value /work/swap) == swap && $(blkid -p -s LABEL -o value /work/swap) == linux_swap ]]
printf 'Native isolated liblp metadata, phase planner, EXT4 growth and swap-file tool execution passed. No swapon or block-device write.\n'
