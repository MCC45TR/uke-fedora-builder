#!/usr/bin/env bash
# Offline host composition of a private, device-matched test root.
set -Eeuo pipefail
[[ $# == 0 && -f /job/packages.complete && ! -e /job/rootfs-frozen ]]
root=/job/root
release=$(jq -er .kernel_release /builder/configs/images/userdata-rawhide.json)
[[ $release == 7.2.11-14 ]]
install -m644 /job/inputs/compose.repo /etc/yum.repos.d/uke-compose.repo
install -m644 /job/inputs/fedora-46.asc /etc/pki/rpm-gpg/RPM-GPG-KEY-uke-fedora46
install -m644 /job/inputs/uke-copr.asc /etc/pki/rpm-gpg/RPM-GPG-KEY-uke-copr
printf '%%_install_langs all\n' > /etc/rpm/macros.zz-uke-languages
for key in /job/inputs/fedora-46.asc /job/inputs/uke-copr.asc /job/inputs/uke-copr-test.asc /job/inputs/device-rpm-publickeys.asc; do
    rpm --root "$root" --import "$key"
done
# These legacy local RPMs are admitted only by pinned archives and exact live
# device file metadata/digest verification, never as a public firmware provider.
cmp /job/audit/private-rpm-payloads.tsv /job/audit/device-private-rpm-payloads.tsv
[[ ! -s /job/audit/device-private-rpm-verify.log ]]
(cd /job/inputs/private-rpms; sha256sum -c --strict SHA256SUMS)
private=(/job/inputs/private-rpms/*.noarch.rpm)
[[ ${#private[@]} == 7 ]]
for file in "${private[@]}"; do [[ -f $file && ! -L $file ]]; done
rpmkeys --root "$root" --define '_pkgverify_level digest' --checksig "${private[@]}" > /job/logs/private-rpm-digests.log
(cd /job/inputs/public-rpms; sha256sum -c --strict SHA256SUMS)
shopt -s nullglob
public=(/job/inputs/public-rpms/*.aarch64.rpm /job/inputs/public-rpms/*.noarch.rpm)
for suffix in -singleboot -core -modules -dtbs -boot; do
    [[ -f /job/inputs/public-rpms/senemos-uke-linux-kernel-mainline${suffix}-${release}.fc46.aarch64.rpm ]]
done
for file in "${public[@]}"; do [[ -f $file && ! -L $file ]]; done
rpmkeys --root "$root" --checksig "${public[@]}" > /job/logs/device-rpm-signatures.log
# Touch driver/data require one transaction. Public signatures were checked
# above; only the pinned private legacy RPMs use digest admission. Remote RPMs
# still require repository signatures and dependencies are never bypassed.
command=(dnf5 --use-host-config --installroot="$root" --releasever=rawhide
    --disable-repo='*' --enable-repo=rawhide --enable-repo=uke-linux
    --setopt=cachedir=/job/cache --setopt=keepcache=True --setopt=gpgcheck=True
    --setopt=localpkg_gpgcheck=False --setopt=install_weak_deps=False
    --setopt=tsflags=nodocs --setopt=excludepkgs='*-debuginfo,*-debugsource,kernel,kernel-core,kernel-modules*,sddm*')
"${command[@]}" -y install "${private[@]}" "${public[@]}" kde-plasma-uke-meta ddcutil > /job/logs/device-install.log 2>&1
"${command[@]}" check > /job/logs/device-dependency-check.log 2>&1
bash /builder/src/image/install-oem-runtime.sh
rpm --root "$root" --restore -a
rpm --root "$root" -qa --qf '%{NAME}\t%{EPOCHNUM}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\t%{SOURCERPM}\n' |
    LC_ALL=C sort > /job/installed-rpms.tsv
[[ $(rpm --root "$root" -q senemos-uke-linux-kernel-mainline-singleboot --qf '%{VERSION}-%{RELEASE}') == "$release.fc46" ]]
systemctl --root="$root" enable uke-install-profile.service uke-wifi-factory.service uke-touchscreen.service
printf 'device-packages-complete\n' > /job/device-packages.complete
