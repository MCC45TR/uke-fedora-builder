#!/bin/bash
# Upstream dracut host interface; this setup file is never run on the tablet.
# shellcheck disable=SC2154 # moddir, initdir and systemdsystemunitdir come from dracut.
check() { return 0; }
depends() { echo systemd; }
installkernel() {
    instmods cdc_acm usbhid hid_generic xhci_hcd xhci_plat_hcd dwc3 dwc3_qcom \
        phy_msm_snps_eusb2_uke repeater_qti_pmic_eusb2_uke
}
install() {
    inst_multiple /bin/sh /usr/bin/journalctl /usr/bin/uke-boot-status
    inst_binary /usr/libexec/senemos-uke/uke-esp32-cdc
    inst_simple "$moddir/uke-initrd-shell.service" "$systemdsystemunitdir/uke-initrd-shell.service"
    inst_simple "$moddir/uke-initrd-cdc.service" "$systemdsystemunitdir/uke-initrd-cdc.service"
    mkdir -p "$initdir$systemdsystemunitdir/initrd.target.wants"
    ln -s ../uke-initrd-shell.service "$initdir$systemdsystemunitdir/initrd.target.wants/uke-initrd-shell.service"
    ln -s ../uke-initrd-cdc.service "$initdir$systemdsystemunitdir/initrd.target.wants/uke-initrd-cdc.service"
}
