#!/bin/bash
# SPDX-License-Identifier: MIT
# Host-only dracut module. No boot hook, service, device selection or autoformat.
# shellcheck disable=SC2154
check() { return 255; }
install() {
    local script
    inst_multiple bash env awk blkid blockdev cat cmp cp cut date dd dirname \
        dmsetup dumpe2fs e2fsck find flock grep id jq lpdump lpmake lpflash \
        ln lsblk mkdir mktemp mkswap mv od readlink realpath resize2fs sed \
        sha256sum simg2img stat tail timeout tr truncate uname
    for script in fastboot-singleboot-layout inspect-fastboot-super \
        plan-super-provision provision-fastboot-super map-fastboot-rescue; do
        inst_simple "$moddir/$script.sh" "/usr/libexec/uke-super/$script.sh"
        chmod 755 "$initdir/usr/libexec/uke-super/$script.sh"
    done
}
