#!/bin/bash
# Upstream host-only dracut interface; excluded from the tablet root.
# shellcheck disable=SC2154
check() { return 0; }
depends() { echo systemd; }
installkernel() {
    instmods ufs_qcom phy_qcom_qmp_ufs dwc3 dwc3_qcom \
        phy_msm_snps_eusb2_uke repeater_qti_pmic_eusb2_uke \
        i2c_qcom_geni gpi g_serial usb_f_acm usbhid hid_generic xhci_hcd xhci_plat_hcd
}
install() {
    inst_multiple /bin/sh /usr/bin/bash /usr/sbin/modprobe /usr/bin/blkid /usr/bin/readlink /usr/bin/grep /usr/bin/sleep /usr/bin/cat /usr/bin/udevadm /usr/bin/mount /usr/bin/dmesg /usr/bin/tail /usr/bin/uke-boot-status
    inst_simple "$moddir/root-guard.sh" /usr/libexec/uke-root-guard
    chmod 755 "$initdir/usr/libexec/uke-root-guard"
    inst_simple "$moddir/uke-root-guard.service" "$systemdsystemunitdir/uke-root-guard.service"
    inst_simple "$moddir/uke-initrd-screen.service" "$systemdsystemunitdir/uke-initrd-screen.service"
    mkdir -p "$initdir$systemdsystemunitdir/sysroot.mount.requires"
    ln -s ../uke-root-guard.service "$initdir$systemdsystemunitdir/sysroot.mount.requires/uke-root-guard.service"
    mkdir -p "$initdir$systemdsystemunitdir/initrd.target.wants"
    ln -s ../uke-initrd-screen.service "$initdir$systemdsystemunitdir/initrd.target.wants/uke-initrd-screen.service"
    # Keep the existing peripheral debug shell available when UFS/root fails.
    for unit in uke-cdc-acm uke-cdc-shell; do
        inst_simple "$systemdsystemunitdir/$unit.service" "$systemdsystemunitdir/$unit.service"
        mkdir -p "$initdir$systemdsystemunitdir/$unit.service.d"
        cat > "$initdir$systemdsystemunitdir/$unit.service.d/initrd.conf" <<'UNIT'
[Unit]
DefaultDependencies=no
IgnoreOnIsolate=yes
After=systemd-udev-trigger.service
Before=initrd-switch-root.target
Conflicts=initrd-switch-root.target
StartLimitIntervalSec=0
[Service]
Restart=on-failure
RestartSec=2
UNIT
    done
    ln -s ../uke-cdc-shell.service "$initdir$systemdsystemunitdir/initrd.target.wants/uke-cdc-shell.service"
}
