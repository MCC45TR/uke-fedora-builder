#!/usr/bin/env bash
# Host-only completion of the empty-root compose. Never runs on a tablet.
set -Eeuo pipefail
[[ $# == 0 && -f /job/packages.complete && ! -e /job/rootfs-frozen ]]
root=/job/root
install -m644 /job/inputs/compose.repo /etc/yum.repos.d/uke-compose.repo
install -m644 /job/inputs/fedora-46.asc /etc/pki/rpm-gpg/RPM-GPG-KEY-uke-fedora46
install -m644 /job/inputs/uke-copr.asc /etc/pki/rpm-gpg/RPM-GPG-KEY-uke-copr
printf '%%_install_langs all\n' > /etc/rpm/macros.zz-uke-languages
packages=()
for name in uke-boot-integration uke-installation-profile uke-kernel-update uke-wifi-factory; do
    matches=(/job/inputs/candidate-rpms/fedora-rawhide-aarch64/"$name"-0.1.0-30.fc46.aarch64.rpm)
    [[ ${#matches[@]} == 1 && -f ${matches[0]} ]]
    packages+=("${matches[0]}")
done
for suffix in '' -core -modules -dtbs -boot; do
    file=/job/inputs/candidate-rpms/fedora-rawhide-aarch64/senemos-uke-linux-kernel-mainline${suffix}-7.2.10-31.fc46.aarch64.rpm
    [[ -f $file ]]
    packages+=("$file")
done
while IFS= read -r -d '' file; do packages+=("$file"); done < <(
    find /job/inputs/device-rpms -maxdepth 1 -type f \( -name '*.aarch64.rpm' -o -name '*.noarch.rpm' \) \
        ! -name 'uke-ssc-fileservice-*' ! -name 'uke-adaptive-display-*' -print0 | sort -z
)
[[ ${#packages[@]} == 20 ]]
deferred=(/job/inputs/device-rpms/uke-ssc-fileservice-2026.09.21-8.fc46.aarch64.rpm
    /job/inputs/device-rpms/uke-adaptive-display-0.1.0-7.fc46.noarch.rpm)
rpm --root "$root" --import /job/inputs/uke-copr.asc
rpmkeys --root "$root" --checksig "${packages[@]}" "${deferred[@]}" > /job/logs/device-rpm-signatures.log
command=(dnf5 --use-host-config --installroot="$root" --releasever=rawhide
    --disable-repo='*' --enable-repo=rawhide --enable-repo=uke-linux
    --setopt=cachedir=/job/cache --setopt=keepcache=True
    --setopt=gpgcheck=True --setopt=localpkg_gpgcheck=True --setopt=install_weak_deps=False
    --setopt=tsflags=nodocs --setopt=excludepkgs='*-debuginfo,*-debugsource,kernel,kernel-core,kernel-modules*,sddm*')
"${command[@]}" -y install "${packages[@]}" kde-plasma-uke-meta > /job/logs/device-install.log 2>&1
"${command[@]}" check > /job/logs/device-dependency-check.log 2>&1
rpm --root "$root" --restore -a
rpm --root "$root" -qa --qf '%{NAME}\t%{EPOCHNUM}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\t%{SOURCERPM}\n' |
    LC_ALL=C sort > /job/installed-rpms.tsv
[[ $(rpm --root "$root" -q senemos-uke-linux-kernel-mainline --qf '%{VERSION}-%{RELEASE}') == 7.2.10-31.fc46 ]]
[[ $(rpm --root "$root" -q mesa-dri-drivers --qf '%{VERSION}-%{RELEASE}') == 26.2.4-2.fc46 ]]
systemctl --root="$root" enable uke-install-profile.service uke-wifi-factory.service uke-touchscreen.service
# SSC's real firmware file dependencies are retained. Install these two RPMs
# only after verified device-local provisioning; never invent file providers.
mkdir -p /job/deferred-rpms
cp "${deferred[@]}" /job/deferred-rpms/
printf 'device-packages-complete\n' > /job/device-packages.complete
