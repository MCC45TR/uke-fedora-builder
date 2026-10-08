#!/usr/bin/env bash
# Disposable pinned ARM64 host userspace; never invoked on the tablet.
set -Eeuo pipefail
[[ $# == 1 ]]
owner=$1
[[ $(uname -m) == aarch64 ]]
root=/job/root
trap 'if [[ $owner != none ]]; then chown -R "$owner" /job; fi' EXIT
release=7.2.9-senemos-uke
(cd /job/inputs; sha256sum -c SHA256SUMS)
rm -rf "$root"
mkdir -p "$root" /job/tmp /job/empty-config
tar --numeric-owner --same-owner --xattrs --xattrs-include='security.capability' -xf /job/inputs/prepared-root.tar -C "$root"
packages=(/job/inputs/kernel/*.aarch64.rpm)
[[ ${#packages[@]} == 4 ]]
rpmkeys --root "$root" --import /builder/configs/keys/uke-copr.asc
for package in "${packages[@]}"; do
    rpmkeys --root "$root" --checksig "$package" | grep -F 'signatures OK'
done
rpm --root "$root" -Uvh --replacepkgs "${packages[@]}"
rpm --root "$root" --restore senemos-uke-linux-kernel-mainline{,-core,-modules,-dtbs}
rpm --root "$root" -V senemos-uke-linux-kernel-mainline{,-core,-modules,-dtbs}
rpm --root "$root" -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n' | sort > /job/installed-rpms.tsv
if cut -f1 /job/installed-rpms.tsv | grep -Ei 'python|pypy|libpython|^plasma-workspace$|^dolphin$'; then exit 1; fi
uuid=$(cat /job/inputs/root-uuid)
printf '%s\n' "$uuid" > "$root/etc/uke-boot-pair.uuid"
printf 'UUID=%s / ext4 defaults 0 1\n' "$uuid" > "$root/etc/fstab"
rm -f "$root/etc/systemd/system/sysinit.target.wants/debug-shell.service" \
    "$root/etc/systemd/system/multi-user.target.wants/uke-esp32-cdc-log.service" \
    "$root/etc/systemd/system/debug-shell.service.d/90-uke-core.conf"
ln -sfn /dev/null "$root/etc/systemd/system/getty@tty1.service"
for unit in uke-screen-shell uke-cdc-shell uke-root-status; do
    install -Dm644 "/builder/src/boot-pair/$unit.service" "$root/usr/lib/systemd/system/$unit.service"
    mkdir -p "$root/etc/systemd/system/multi-user.target.wants"
    ln -sfn "/usr/lib/systemd/system/$unit.service" "$root/etc/systemd/system/multi-user.target.wants/$unit.service"
done
install -Dm755 /builder/src/boot-pair/screen-shell.sh "$root/usr/libexec/uke-screen-shell"
install -Dm755 /builder/src/boot-pair/root-status.sh "$root/usr/libexec/uke-root-status"
# Automatic native-COPR updates must not silently replace the module tuple of
# this built-in-initramfs stock-ABL candidate. Update through a rebuilt pair.
printf '\nexcludepkgs=senemos-uke-linux-kernel-mainline*\n' >> "$root/etc/dnf/dnf.conf"
mkdir -p "$root/etc/systemd/journald.conf.d"
printf '[Journal]\nStorage=persistent\nSystemMaxUse=64M\nSystemMaxFileSize=8M\n' > "$root/etc/systemd/journald.conf.d/90-uke-bringup.conf"
rm -f "$root/etc/modules-load.d/uke-esp32.conf"
printf 'g_serial\n' > "$root/etc/modules-load.d/uke-cdc.conf"
chroot "$root" /usr/bin/depmod "$release"
# Temporarily install the exact signed host assembly dependency closure in
# this disposable native root. Remove it through RPM before target export.
# No project Python and no cross-sysroot guesses about upstream dracut hooks.
rpmkeys --root "$root" --import /builder/configs/keys/fedora-46.asc
for package in /job/inputs/host-rpms/*.rpm; do
    rpmkeys --root "$root" --checksig "$package" | grep -F 'signatures OK'
done
rpm --root "$root" -Uvh /job/inputs/host-rpms/*.rpm
mkdir -p "$root/usr/lib/dracut/modules.d/92uke-abl"
install -m644 /builder/src/boot-pair/dracut/* "$root/usr/lib/dracut/modules.d/92uke-abl/"
chmod 755 "$root/usr/lib/dracut/modules.d/92uke-abl/module-setup.sh"
# Upstream --sysroot resolves both hooks and target dependencies from this
# signed temporary installation, while host /proc and /dev remain available.
dracut --sysroot "$root" \
    --conf /dev/null --confdir /job/empty-config --tmpdir /job/tmp \
    --force --no-hostonly --no-hostonly-cmdline --no-early-microcode --gzip \
    --add uke-abl --kernel-cmdline "$(cat /job/inputs/kernel-cmdline)" \
    --filesystems ext4 --omit 'network plymouth crypt systemd-cryptsetup syslog lvm mdraid btrfs i18n' \
    /job/initramfs.cpio.gz "$release"
[[ -s /job/initramfs.cpio.gz ]]
rpm --root "$root" -e dracut kbd xkeyboard-config libxkbcommon
rm -rf "$root/usr/lib/dracut/modules.d/92uke-abl"
rpm --root "$root" -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n' | sort > /job/final-rpms.tsv
[[ $(sha256sum /job/final-rpms.tsv | cut -d ' ' -f1) == $(sha256sum /job/installed-rpms.tsv | cut -d ' ' -f1) ]]
cp /job/initramfs.cpio.gz "$root/boot/initramfs-$release.img"
rm -rf "$root/var/log/"* "$root/var/cache/dnf"* "$root/tmp/"* "$root/var/tmp/"*
rm -f "$root/etc/ssh/ssh_host_"* "$root/var/lib/systemd/random-seed" "$root/root/.bash_history"
: > "$root/etc/machine-id"
tar --numeric-owner --xattrs --xattrs-include='security.capability' -cpf /job/pair-root.tar -C "$root" .
(cd /job; sha256sum pair-root.tar > pair-root.sha256)
printf '%s\n' 'Pinned ARM64 root RPM replacement and root-capable dracut assembly complete'
