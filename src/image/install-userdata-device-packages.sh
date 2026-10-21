#!/usr/bin/env bash
# Update the retained private root from the canonical signed test repository.
set -Eeuo pipefail
[[ $# == 0 && -f /job/packages.complete && ! -e /job/rootfs-frozen ]]
root=/job/root
release=$(jq -er .kernel_release /builder/configs/images/userdata-rawhide.json)
[[ $release =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ && -d $root && ! -L $root ]]
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
    --setopt=rawhide.metadata_expire=0
    --setopt=localpkg_gpgcheck=True --setopt=install_weak_deps=False
    --setopt=allow_vendor_change=True
    --setopt=tsflags=nodocs --setopt=excludepkgs='*-debuginfo,*-debugsource,kernel,kernel-core,kernel-modules*,sddm*')
packages=("senemos-uke-linux-kernel-mainline-singleboot-$release.fc46"
    uke-core-meta uke-kde-plasma-meta uke-core uke-hw
    uke-power uke-sensors uke-additional uke-extras
    uke-control uke-control-tests uke-firmware uke-fastfetch-config
    uke-front-color uke-adaptive-display
    uke-power-profile-backend uke-touchscreen
    uke-bluetooth uke-wifi-factory
    uke-charge-control uke-offline-charge uke-battery-observer
    uke-mesa-dri-drivers uke-mesa-vulkan-drivers uke-ssc-fileservice
    uke-libaccounts-glib uke-libwacom uke-libwacom-data
    ddcutil openssh-server nftables firewalld selinux-policy-targeted policycoreutils)
rollback=()
retired=()
for component in boot core dtbs modules; do
    archive=/job/inputs/kernel17-copr/senemos-uke-linux-kernel-mainline-$component-7.2.11-17.fc46.aarch64.rpm
    [[ -f $archive && ! -L $archive ]]
    rollback+=("$archive")
    retired+=("senemos-uke-linux-kernel-mainline-$component-7.2.11-16.fc46.aarch64")
done
solve() {
    local output=$1 rc=0
    shift
    "${command[@]}" "$@" --assumeno > "$output" 2>&1 || rc=$?
    if [[ $rc == 0 ]]; then
        grep -Fq 'Nothing to do' "$output"
    else
        [[ $rc == 1 ]] && grep -Fq 'Operation aborted by the user' "$output"
    fi
}
if [[ ${UKE_COMPOSE_SOLVE_ONLY:-0} == 1 ]]; then
    solve /job/logs/device-solve.log install --allowerasing "${packages[@]}"
    solve /job/logs/rawhide-sync-solve.log distro-sync --allowerasing --exclude='senemos-uke-linux-kernel-mainline*'
    solve /job/logs/rollback-solve.log install --setopt=installonly_limit=4 "${rollback[@]}"
    solve /job/logs/retire-solve.log remove --setopt=clean_requirements_on_remove=False "${retired[@]}"
    exit
fi
"${command[@]}" -y install --allowerasing "${packages[@]}" > /job/logs/device-install.log 2>&1
# Synchronize the retained Fedora root while preserving the selected kernel tuple.
"${command[@]}" -y distro-sync --allowerasing \
    --exclude='senemos-uke-linux-kernel-mainline*' > /job/logs/rawhide-sync.log 2>&1
# Retain the measured boot-B cohort and the earlier baseline with matching modules.
"${command[@]}" -y install --setopt=installonly_limit=4 "${rollback[@]}" > /job/logs/rollback-install.log 2>&1
"${command[@]}" -y remove --setopt=clean_requirements_on_remove=False "${retired[@]}" > /job/logs/retire-install.log 2>&1
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
