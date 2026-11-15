#!/bin/bash
# SPDX-License-Identifier: MIT
# Explicit protected-profile barrier; never auto-select for existing profiles.
# shellcheck disable=SC2154
check() { return 255; }
depends() { echo 'systemd resume uke-super-tools'; }
install() {
    local unit generator
    # The coordinated kernel build must supply the native admission policy.
    # A tool-only archive or an older physical-root guard cannot substitute.
    require_binaries /usr/libexec/uke-protected-boot-policy || return 1
    inst_multiple /usr/libexec/uke-protected-boot-policy || return 1
    # qcom_ice is an early module in the cumulative kernel. Its advertised
    # key types are fixed when the controller probes. The enclosing producer
    # must embed this config before that first probe, not append it to a later
    # vendor ramdisk or attempt a mounted-root controller reset.
    inst_simple "$moddir/uke-hwkm.conf" /usr/lib/modprobe.d/uke-hwkm.conf || return 1
    [[ -f $initdir$systemdsystemunitdir/systemd-hibernate-resume.service &&
       -x $initdir/usr/lib/systemd/systemd-hibernate-resume ]] || return 1
    cmp -s "$systemdsystemunitdir/systemd-hibernate-resume.service" \
        "$initdir$systemdsystemunitdir/systemd-hibernate-resume.service" || return 1
    grep -Fx 'ConditionKernelCommandLine=!noresume' \
        "$systemdsystemunitdir/systemd-hibernate-resume.service" >/dev/null || return 1
    [[ $(grep -c '^ConditionKernelCommandLine=' \
        "$systemdsystemunitdir/systemd-hibernate-resume.service") == 1 ]] || return 1
    for unit in uke-protected-role.service uke-protected-resume.service; do
        inst_simple "$moddir/$unit" "$systemdsystemunitdir/$unit" || return 1
    done
    for unit in sysroot.mount systemd-hibernate-resume.service; do
        mkdir -p "$initdir/etc/systemd/system/$unit.d" || return 1
        inst_simple "$moddir/$unit.conf" "/etc/systemd/system/$unit.d/50-uke-protected.conf" || return 1
    done
    mkdir -p "$initdir/etc/systemd/system-generators" "$initdir/etc/systemd/system" || return 1
    # Disable discovery before all generators run. A later root mask is too late.
    for generator in systemd-hibernate-resume-generator systemd-cryptsetup-generator systemd-gpt-auto-generator; do
        ln -s /dev/null "$initdir/etc/systemd/system-generators/$generator" || return 1
    done
    # Initrd never activates swap or falls back to a software cryptsetup unit.
    # Resume uses its validated inactive mapping, independently of swapon.
    for unit in swap.target systemd-cryptsetup@.service systemd-hibernate-resume@.service; do
        ln -s /dev/null "$initdir/etc/systemd/system/$unit" || return 1
    done
}
