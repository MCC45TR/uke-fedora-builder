#!/bin/bash
# SPDX-License-Identifier: MIT
# Host-only installer. Only an explicit kernel-admitted seed profile can write.
# shellcheck disable=SC2154
check() { return 255; }
depends() { echo 'systemd uke-super-tools'; }
install() {
    local script
    # This plaintext seed/rescue profile must not replace protected-root policy.
    [[ ! -e $initdir/usr/libexec/uke-protected-boot-policy &&
       ! -e $initdir$systemdsystemunitdir/uke-protected-role.service ]] || return 1
    inst_multiple udevadm
    for script in early-super-policy prepare-early-super guard-early-rescue;do
        inst_simple "$moddir/$script.sh" "/usr/libexec/uke-super/$script.sh"
        chmod 755 "$initdir/usr/libexec/uke-super/$script.sh"
    done
    inst_simple "$moddir/uke-super-prepare.service" "$systemdsystemunitdir/uke-super-prepare.service"
    mkdir -p "$initdir$systemdsystemunitdir/uke-root-guard.service.d"
    cat > "$initdir$systemdsystemunitdir/uke-root-guard.service.d/60-uke-super.conf" <<'UNIT'
[Unit]
Requires=uke-super-prepare.service
After=uke-super-prepare.service
[Service]
ExecStart=
ExecStart=/usr/libexec/uke-super/guard-early-rescue.sh
UNIT
}
