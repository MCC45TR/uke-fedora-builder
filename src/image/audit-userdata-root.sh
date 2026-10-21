#!/usr/bin/env bash
# Offline host container stage. No service or desktop session is started.
set -Eeuo pipefail
trap 'printf "Offline root audit failed at line %s\n" "$LINENO" >&2' ERR
require_no_match() {
    local rc=0
    grep "$@" || rc=$?
    [[ $rc == 1 ]]
}
[[ $# == 0 && -f /job/device-packages.complete && ! -e /job/rootfs-frozen ]]
root=/job/root
rpm --root "$root" -q plasma-setup plasma-login-manager kde-settings-plasmalogin \
    plasma-discover-offline-updates plasma-discover-packagekit PackageKit glibc-all-langpacks \
    ncurses ibus ibus-libpinyin ibus-hangul ibus-anthy ibus-chewing ibus-m17n \
    uke-installation-profile uke-kernel-update uke-touchscreen uke-bluetooth \
    uke-kde-plasma-meta openssh-server nftables firewalld selinux-policy-targeted \
    uke-core-meta uke-control uke-firmware uke-front-color uke-charge-control uke-offline-charge \
    uke-battery-observer uke-fastfetch-config > /job/audit/required-packages.txt
release=$(jq -er .kernel_release /builder/configs/images/userdata-rawhide.json)
[[ $(rpm --root "$root" -q senemos-uke-linux-kernel-mainline-singleboot --qf '%{VERSION}-%{RELEASE}') == "$release.fc46" ]]
if rpm --root "$root" -q senemos-uke-linux-kernel-mainline >/dev/null 2>&1; then exit 1; fi
[[ $(readlink "$root/usr/lib/senemos/default-boot.img") == kernel-updates/$release/userdata.img ]]
awk -F: '$3>=1000 && $3!=65534 {bad=1} END {exit bad}' "$root/etc/passwd"
grep -Eq '^root:(!|\*)' "$root/etc/shadow"
[[ ! -e $root/etc/plasma-setup-done && ! -e $root/var/lib/senemos/installation/profile ]]
[[ $(readlink "$root/etc/systemd/system/display-manager.service") == /usr/lib/systemd/system/plasmalogin.service ]]
[[ $(readlink "$root/etc/systemd/system/default.target") == /usr/lib/systemd/system/graphical.target ]]
for service in plasma-setup.service plasmalogin.service uke-install-profile.service uke-adaptive-display.target \
    firewalld.service upower.service uke-control.service uke-userdata-accept.service; do
    [[ $(systemctl --root="$root" is-enabled "$service") == enabled ]]
done
[[ $(systemctl --root="$root" is-enabled sshd.service || true) == disabled ]]
[[ $(systemctl --root="$root" is-enabled sshd.socket || true) == disabled ]]
[[ ! -L $root/etc/systemd/system/sshd.service || $(readlink "$root/etc/systemd/system/sshd.service") != /dev/null ]]
[[ -x $root/usr/sbin/nft && -x $root/usr/sbin/firewalld ]]
jq -e '.modules | index("physicaldisk") != null' "$root/etc/fastfetch/config.jsonc" >/dev/null
grep -Fxq CONFIG_NF_TABLES=m "$root/usr/lib/modules/$release/config"
grep -Fxq CONFIG_NF_NAT=m "$root/usr/lib/modules/$release/config"
for service in debug-shell.service uke-cdc-shell.service uke-esp32-cdc-log.service uke-boot-guard.service; do
    state=$(systemctl --root="$root" is-enabled "$service" || true)
    [[ $state == masked ]]
done
[[ -L "$root/etc/systemd/system/dev-fastrpc\\x2dadsp.device.wants/uke-adaptive-display.target" ]]
[[ -x $root/usr/sbin/sshd && -f $root/usr/lib/firewalld/services/ssh.xml ]]
jq -e '[.[] | select(.name=="outputs") | .data[]] |
    length==1 and .[0].connectorName=="DSI-1" and
    .[0].automaticBrightness==true and .[0].autoRotation=="InTabletMode" and
    .[0].vrrPolicy=="Always" and (.[0].autoBrightnessCurve|length)>1' \
    "$root/etc/xdg/kwinoutputconfig.json" >/dev/null
[[ -f $root/usr/lib/systemd/system/packagekit-offline-update.service ]]
[[ -x $root/usr/libexec/pk-offline-update && -x $root/usr/bin/clear ]]
[[ -s $root/etc/udev/hwdb.bin && $(stat -c %s "$root/etc/udev/hwdb.bin") -gt 10000000 ]]
[[ $(stat -c %s "$root/etc/machine-id") == 0 ]]
grep -Fxq 'SELINUX=enforcing' "$root/etc/selinux/config"
chroot "$root" /usr/bin/semodule -l > /job/audit/selinux-modules.txt
grep -Fxq uke-ssc /job/audit/selinux-modules.txt
grep -Fxq uke-power-profile /job/audit/selinux-modules.txt
grep -Fxq 'PARTLABEL=userdata / f2fs defaults,noatime 0 0' "$root/etc/fstab"
require_no_match -Fq 'senemos-uke-linux-kernel-mainline*' "$root/etc/dnf/dnf.conf"
if [[ -e $root/etc/senemos/kernel-update.conf ]] && grep -Fxq automatic=1 "$root/etc/senemos/kernel-update.conf"; then exit 1; fi
for directory in "$root/usr/lib/modules/"*; do
    [[ ${directory##*/} == "$release" || ${directory##*/} == 7.2.11-14 || ${directory##*/} == 7.2.11-17 ]]
done
grep -Fxq automatic=1 "$root/etc/senemos/userdata-update.conf"
[[ -z $(find "$root/dev" "$root/proc" "$root/sys" "$root/run" -mindepth 1 -print -quit) ]]
cmp /job/audit/private-rpm-payloads.tsv /job/audit/device-private-rpm-payloads.tsv
[[ ! -s /job/audit/device-private-rpm-verify.log ]]
for name in regulatory.db regulatory.db.p7s; do
    cmp "$root/usr/lib/firmware/$name" "/job/original-fedora/usr/lib/firmware/$name"
done
[[ -s $root/var/lib/uke-touch/normal.bin && -s $root/var/lib/uke-touch/reference.bin && -s $root/var/lib/uke-touch/config.ini ]]
if rpm --root "$root" -qa --qf '%{NAME}\n' | grep -E '(^sddm|-(debuginfo|debugsource)$|^gcc$|^gdb$|^clang$|^make$|^uke-cdc-debug$|^uke-esp32-cdc$|^uke-boot-recovery$|^senemos-uke-linux-kernel-mainline-up)'; then exit 1; fi
if grep -rE 'nabu-linux' "$root/etc/yum.repos.d"; then exit 1; fi
grep -Fq 'name=Uke Linux Test' "$root/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:mcc45tr:uke-linux-test.repo"
grep -Fq 'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-uke-copr-test' "$root/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:mcc45tr:uke-linux-test.repo"
[[ $(find "$root/etc/yum.repos.d" -name '*copr*' -type f | wc -l) == 1 ]]
grep -Fxq test "$root/etc/uke-control/channel"
require_no_match -rE 'uke-linux-test:custom:|results/mcc45tr/uke-linux/' "$root/etc/yum.repos.d"
chroot "$root" /usr/sbin/visudo -cf /etc/sudoers
chroot "$root" /usr/sbin/ldconfig -N -X
rpm --root "$root" -qa --qf '[%{FILENAMES}\t%{FILEFLAGS}\t%{FILELANGS}\n]' > /job/rpm-owned-files.tsv
rpm --root "$root" -qa --qf '%{NAME}\t%{EPOCHNUM}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\t%{SOURCERPM}\n' |
    LC_ALL=C sort > /job/installed-rpms.tsv
echo 'Offline account, first-run, service, package and update gates passed; no physical startup claimed.'
