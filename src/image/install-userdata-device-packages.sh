#!/usr/bin/env bash
# Update the retained private root from the canonical signed test repository.
set -Eeuo pipefail
[[ $# == 0 && -f /job/packages.complete && ! -e /job/rootfs-frozen ]]
root=/job/root
release=$(jq -er .kernel_release /builder/configs/images/userdata-rawhide.json)
[[ $release == 7.2.11-16 && -d $root && ! -L $root ]]
install -m644 /job/inputs/compose.repo /etc/yum.repos.d/uke-compose.repo
install -m644 /job/inputs/fedora-46.asc /etc/pki/rpm-gpg/RPM-GPG-KEY-uke-fedora46
install -m644 /job/inputs/uke-copr-test.asc /etc/pki/rpm-gpg/RPM-GPG-KEY-uke-copr-test
printf '%%_install_langs all\n' > /etc/rpm/macros.zz-uke-languages
rpm --root "$root" --import /job/inputs/uke-copr-test.asc
reference=$root/var/lib/uke-touch/reference.bin
[[ -f $reference && ! -L $reference && $(stat -c %a "$reference") == 600 ]]
reference_sha=$(sha256sum "$reference" | cut -d ' ' -f1)
command=(dnf5 --use-host-config --installroot="$root" --releasever=rawhide
    --disable-repo='*' --enable-repo=rawhide --enable-repo=uke-linux-test
    --setopt=cachedir=/job/cache --setopt=keepcache=True --setopt=gpgcheck=True
    --setopt=uke-linux-test.metadata_expire=0
    --setopt=localpkg_gpgcheck=True --setopt=install_weak_deps=False
    --setopt=allow_vendor_change=True
    --setopt=tsflags=nodocs --setopt=excludepkgs='*-debuginfo,*-debugsource,kernel,kernel-core,kernel-modules*,sddm*')
packages=("senemos-uke-linux-kernel-mainline-singleboot-$release.fc46"
    uke-core-meta uke-kde-plasma-meta uke-core-1.0.21-1.fc46 uke-hw-1.1.1-3.fc46
    uke-power-1.1.0-1.fc46 uke-sensors-1.0.1-1.fc46 uke-additional uke-extras
    uke-control-1.0.21-1.fc46 uke-control-tests-1.0.21-1.fc46 uke-firmware uke-fastfetch-config-1.0.1-1.fc46
    uke-front-color-1.0.2-1.fc46 uke-adaptive-display-1.0.15-2.fc46
    uke-power-profile-backend-1.0.4-2.fc46 uke-touchscreen-1.0.13-2.fc46
    uke-bluetooth-1.0.6-2.fc46 uke-wifi-factory-1.1.1-1.fc46
    uke-charge-control-1.1.0-1.fc46 uke-offline-charge-1.1.0-1.fc46 uke-battery-observer-1.1.0-1.fc46
    uke-mesa-dri-drivers uke-mesa-vulkan-drivers uke-ssc-fileservice-2026.09.21-9.fc46
    uke-libaccounts-glib uke-libwacom uke-libwacom-data
    ddcutil openssh-server nftables firewalld selinux-policy-targeted policycoreutils)
if [[ ${UKE_COMPOSE_SOLVE_ONLY:-0} == 1 ]]; then
    rc=0
    "${command[@]}" install --allowerasing "${packages[@]}" --assumeno > /job/logs/device-solve.log 2>&1 || rc=$?
    [[ $rc == 1 ]] && grep -Fq 'Operation aborted by the user' /job/logs/device-solve.log
    exit
fi
"${command[@]}" -y install --allowerasing "${packages[@]}" > /job/logs/device-install.log 2>&1
"${command[@]}" check > /job/logs/device-dependency-check.log 2>&1
[[ $(sha256sum "$reference" | cut -d ' ' -f1) == "$reference_sha" ]]
rpm --root "$root" -q uke-local-touch-data >/dev/null
rpm --root "$root" --restore -a
rpm --root "$root" -qa --qf '%{NAME}\t%{EPOCHNUM}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\t%{SOURCERPM}\n' |
    LC_ALL=C sort > /job/installed-rpms.tsv
[[ $(rpm --root "$root" -q senemos-uke-linux-kernel-mainline-singleboot --qf '%{VERSION}-%{RELEASE}') == "$release.fc46" ]]
systemctl --root="$root" unmask uke-install-profile.service
systemctl --root="$root" enable uke-install-profile.service uke-wifi-factory.service uke-touchscreen.service \
    uke-adaptive-display.target uke-userdata-accept.service uke-control.service
printf 'device-packages-complete\n' > /job/device-packages.complete
