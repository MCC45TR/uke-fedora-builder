#!/usr/bin/bash
# Host-only initial EXT4 test. The complete singleboot profile is separate.
test_fastboot_requirements() {
    # shellcheck source=fastboot-requirements.sh
    # shellcheck disable=SC1091
    source "$(dirname "${BASH_SOURCE[0]}")/fastboot-requirements.sh"
    fastboot_requirements "$1" || return
    printf 'require current-slot=b\n'
}
test_fastboot_tasks() {
    printf 'version 1\nflash boot_b boot.img\nflash userdata userdata.img\n'
}
