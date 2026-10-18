#!/usr/bin/env bash
# Offline host container stage. No service or desktop session is started.
set -Eeuo pipefail
trap 'printf "Offline root audit failed at line %s\n" "$LINENO" >&2' ERR
[[ $# == 0 && -f /job/device-packages.complete && ! -e /job/rootfs-frozen ]]
root=/job/root
rpm --root "$root" -q plasma-setup plasma-login-manager kde-settings-plasmalogin \
    plasma-discover-offline-updates plasma-discover-packagekit PackageKit glibc-all-langpacks \
    ncurses ibus ibus-libpinyin ibus-hangul ibus-anthy ibus-chewing ibus-m17n \
    uke-installation-profile uke-kernel-update uke-touchscreen uke-bluetooth \
    kde-plasma-uke-meta > /job/audit/required-packages.txt
awk -F: '$3>=1000 && $3!=65534 {bad=1} END {exit bad}' "$root/etc/passwd"
grep -Eq '^root:(!|\*)' "$root/etc/shadow"
[[ ! -e $root/etc/plasma-setup-done && ! -e $root/var/lib/senemos/installation/profile ]]
[[ $(readlink "$root/etc/systemd/system/display-manager.service") == /usr/lib/systemd/system/plasmalogin.service ]]
[[ $(readlink "$root/etc/systemd/system/default.target") == /usr/lib/systemd/system/graphical.target ]]
for service in plasma-setup.service plasmalogin.service uke-install-profile.service; do
    [[ $(systemctl --root="$root" is-enabled "$service") == enabled ]]
done
for service in sshd.service debug-shell.service uke-cdc-shell.service uke-esp32-cdc-log.service uke-boot-guard.service; do
    state=$(systemctl --root="$root" is-enabled "$service" || true)
    [[ $state == masked ]]
done
[[ -f $root/usr/lib/systemd/system/packagekit-offline-update.service ]]
[[ -x $root/usr/libexec/pk-offline-update && -x $root/usr/bin/clear ]]
[[ -s $root/etc/udev/hwdb.bin && $(stat -c %s "$root/etc/udev/hwdb.bin") -gt 10000000 ]]
[[ $(stat -c %s "$root/etc/machine-id") == 0 ]]
grep -Fxq 'SELINUX=enforcing' "$root/etc/selinux/config"
grep -Fxq 'PARTLABEL=userdata / f2fs defaults,noatime 0 0' "$root/etc/fstab"
grep -Fq 'senemos-uke-linux-kernel-mainline*' "$root/etc/dnf/dnf.conf"
[[ ! -e $root/etc/senemos/kernel-update.conf ]] || ! grep -Fxq automatic=1 "$root/etc/senemos/kernel-update.conf"
[[ $(find "$root/usr/lib/modules" -mindepth 1 -maxdepth 1 -type d | wc -l) == 1 ]]
[[ -z $(find "$root/dev" "$root/proc" "$root/sys" "$root/run" -mindepth 1 -print -quit) ]]
[[ -z $(find "$root/usr/lib/firmware" -type f ! -path "$root/usr/lib/firmware/regulatory.db" \
    ! -path "$root/usr/lib/firmware/regulatory.db.p7s" -print -quit) ]]
for name in regulatory.db regulatory.db.p7s; do
    cmp "$root/usr/lib/firmware/$name" "/job/original-fedora/usr/lib/firmware/$name"
done
[[ ! -d $root/var/lib/uke-touch ]] || [[ -z $(find "$root/var/lib/uke-touch" -type f -print -quit) ]]
if rpm --root "$root" -qa --qf '%{NAME}\n' | grep -E '(^sddm|-(debuginfo|debugsource)$|^gcc$|^gdb$|^clang$|^make$|^uke-cdc-debug$|^uke-esp32-cdc$|^uke-boot-recovery$|^senemos-uke-linux-kernel-mainline-up)'; then exit 1; fi
if grep -rE 'uke-linux-test|nabu-linux' "$root/etc/yum.repos.d"; then exit 1; fi
chroot "$root" /usr/sbin/visudo -cf /etc/sudoers
chroot "$root" /usr/sbin/ldconfig -N -X
rpm --root "$root" -qa --qf '[%{FILENAMES}\t%{FILEFLAGS}\t%{FILELANGS}\n]' > /job/rpm-owned-files.tsv
rpm --root "$root" -qa --qf '%{NAME}\t%{EPOCHNUM}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\t%{SOURCERPM}\n' |
    LC_ALL=C sort > /job/installed-rpms.tsv
echo 'Offline account, first-run, service, package and update gates passed; no physical startup claimed.'
