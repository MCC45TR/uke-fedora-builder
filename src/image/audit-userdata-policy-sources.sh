#!/usr/bin/env bash
# Native host stage: require native profiles and original Fedora context text.
set -Eeuo pipefail
[[ $# == 0 && -f /job/device-packages.complete && ! -e /job/rootfs-frozen ]]
root=/job/root original=/job/original-fedora proof=/job/audit/selinux-recompiled
release=$(jq -er .kernel_release /builder/configs/images/userdata-rawhide.json)
[[ $release =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]]
rpm --root "$root" -q --provides "senemos-uke-linux-kernel-mainline-core-$release.fc46.aarch64" |
    grep -Fx 'uke-kernel(platform-profile-qos-v1) = 1' >/dev/null
rpm --root "$root" -V power-profiles-daemon
if rpm --root "$root" -q uke-power-profile-backend >/dev/null 2>&1; then
    echo 'The retired power-profile overlay remains installed' >&2; exit 1
fi
for file in usr/libexec/uke-power-profiles-daemon \
    usr/lib/systemd/system/power-profiles-daemon.service.d/60-uke-cpufreq.conf \
    usr/share/selinux/packages/uke-power-profile.cil; do
    [[ ! -e $root/$file && ! -L $root/$file ]]
done
mkdir -p "$proof"
contexts=etc/selinux/targeted/contexts/files
for name in file_contexts file_contexts.homedirs; do
    cmp "$root/$contexts/$name" "$original/$contexts/$name"
    cmp "$root/$contexts/$name" "$root/var/lib/selinux/targeted/active/$name"
    cp "$root/$contexts/$name" "$proof/$name"
done
echo 'Selected kernel provides native profiles; the original Fedora daemon and SELinux context text are retained.'
