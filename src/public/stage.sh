#!/usr/bin/env bash
# Runs only inside disposable host workers, never on the tablet.
set -Eeuo pipefail
[[ $# == 1 && -f /job/request.json && -d /cache ]]
request=/job/request.json
policy=/builder/configs/public-build.json
stage=$1
if [[ ${UKE_OUTPUT_OWNER:-none} != none ]]; then
    [[ $UKE_OUTPUT_OWNER =~ ^[0-9]+:[0-9]+$ ]]
    # Preserve the numeric owners in the staging root used for filesystem readback.
    trap 'chown -R "$UKE_OUTPUT_OWNER" /job/artifacts' EXIT
fi
channel=$(jq -er .channel "$request")
filesystem=$(jq -er .filesystem "$request")
partition=$(jq -er .partition "$request")
jobs=$(jq -er .jobs "$request")
source_commit=$(jq -er .kernel.commit "$policy")
[[ $source_commit =~ ^[0-9a-f]{40}$ ]]
cache_flags=()
[[ ${UKE_OFFLINE:-0} != 1 ]] || cache_flags+=(--cacheonly)
rpm -qa --qf '%{NEVRA}\n' | LC_ALL=C sort > "/job/artifacts/worker-$stage-rpms.txt"
local_repository() {
    createrepo_c --update --excludes='*.src.rpm' /job/artifacts
    cat > /etc/yum.repos.d/uke-source-build.repo <<'REPO'
[uke-source-build]
name=Locally compiled pinned Uke sources
baseurl=file:///job/artifacts
enabled=1
gpgcheck=0
priority=1
REPO
}
if [[ $stage == kernel ]]; then
    [[ $(uname -m) == aarch64 ]]
    source=/cache/kernel-$source_commit
    if [[ ! -d $source/.git ]]; then
        [[ ${UKE_OFFLINE:-0} != 1 ]]
        git clone --no-checkout "$(jq -er .kernel.url "$policy")" "$source"
    fi
    git -C "$source" checkout --detach "$source_commit"
    [[ $(git -C "$source" rev-parse HEAD) == "$source_commit" && -z $(git -C "$source" status --porcelain --untracked-files=no) ]]
    # The signed upstream source and every adaptation hash are checked by make srpm.
    make -C "$source" srpm outdir=/job/srpm
    mkdir -p /job/rpmbuild
    srpms=(/job/srpm/*.src.rpm)
    [[ ${#srpms[@]} == 1 && -f ${srpms[0]} ]]
    rpmbuild --rebuild --target aarch64 --define '_topdir /job/rpmbuild' \
        --define "_smp_build_ncpus $jobs" --define 'dist .fc46' "${srpms[0]}"
    mkdir -p /job/artifacts/kernel
    cp "${srpms[@]}" /job/artifacts/kernel/
    cp /job/rpmbuild/RPMS/aarch64/*.rpm /job/artifacts/kernel/
    rpm -qp --qf '%{NEVRA}\t%{SOURCERPM}\n' /job/artifacts/kernel/*.aarch64.rpm | sort > /job/artifacts/kernel/packages.tsv
    # Read back the payload without executing RPM scriptlets.
    mkdir /job/kernel-payload
    for package in /job/artifacts/kernel/*.aarch64.rpm; do
        rpm2cpio "$package" > /job/payload.cpio
        (cd /job/kernel-payload; cpio -idmu --quiet --no-absolute-filenames < /job/payload.cpio)
    done
    release=$(jq -er .kernel.release "$policy")
    bundle=/job/kernel-payload/usr/lib/senemos/kernel-updates/$release
    modules=/job/kernel-payload/usr/lib/modules/$release
    [[ -f $bundle/linux.img && -f $bundle/userdata.img && -f $modules/vmlinuz ]]
    (cd "$modules"; sha256sum -c "$bundle/modules.sha256")
    c++ -std=c++20 -O2 -Wall -Wextra -Werror "$source/src/boot/boot-image.cpp" -o /job/boot-image
    for profile in linux userdata; do
        /job/boot-image inspect "$bundle/$profile.img" > "/job/artifacts/kernel/boot-$profile.json"
        /job/boot-image extract "$bundle/$profile.img" "/job/$profile.Image"
        cmp "$modules/vmlinuz" "/job/$profile.Image"
        cp "$bundle/$profile.img" "/job/artifacts/boot-$profile.img"
    done
    # The native RPM producer audits its linked initramfs with no Python exception.
    jq --arg source "$source_commit" --arg release "$release" \
        '. + {kernel_source_commit:$source,kernel_release:$release,kernel_rpms_locally_built:true,
          local_kernel_rpm_signature:"unsigned local build; signed upstream source verified by producer",
          physical_boot_tested:false,hardware_tested:false,automatic_kernel_activation:false}' \
        "$request" > /job/artifacts/manifest.json
    exit
fi
if [[ $stage == hardware ]]; then
    [[ $(uname -m) == aarch64 && $channel == stable ]]
    hardware_commit=$(jq -er .hardware.commit "$policy")
    [[ $hardware_commit =~ ^[0-9a-f]{40}$ ]]
    hardware=/cache/hardware-$hardware_commit
    if [[ ! -d $hardware/.git ]]; then
        [[ ${UKE_OFFLINE:-0} != 1 ]]
        git clone --no-checkout "$(jq -er .hardware.url "$policy")" "$hardware"
    fi
    git -C "$hardware" checkout --detach "$hardware_commit"
    [[ -z $(git -C "$hardware" status --porcelain --untracked-files=no) ]]
    mkdir -p /job/artifacts/runtime
    local_repository
    for family in uke-additional uke-sensors uke-hw uke-power uke-core uke-metas; do
        top=/job/hardware-$family
        make -C "$hardware/packaging/families" srpm FAMILY="$family" outdir="$top/source"
        srpms=("$top/source/SRPMS/"*.src.rpm)
        [[ ${#srpms[@]} == 1 && -f ${srpms[0]} ]]
        dnf5 "${cache_flags[@]}" -y builddep "${srpms[0]}"
        for attempt in 1 2 3 4; do
            printf 'Building %s, dependency pass %s\n' "$family" "$attempt"
            result=0
            rpmbuild --rebuild --target aarch64 --define "_topdir $top" \
                --define "_smp_build_ncpus $jobs" --define 'dist .fc46' "${srpms[0]}" || result=$?
            [[ $result != 0 ]] || break
            [[ $result == 11 ]] || exit "$result"
            requirements=("$top/SRPMS/"*.buildreqs.nosrc.rpm)
            [[ -f ${requirements[0]} ]]
            dnf5 "${cache_flags[@]}" -y builddep "${requirements[@]}"
            rm -- "${requirements[@]}"
        done
        [[ $result == 0 ]]
        cp "${srpms[@]}" /job/artifacts/runtime/
        find "$top/RPMS" -type f -name '*.rpm' -exec cp -t /job/artifacts/runtime/ {} +
        local_repository
    done
    jq --arg source "$hardware_commit" '. + {hardware_source_commit:$source,
        hardware_rpms_locally_built:true,local_runtime_repository:"unsigned RPMs compiled from the pinned public source"}' \
        /job/artifacts/manifest.json > /job/manifest.tmp
    mv /job/manifest.tmp /job/artifacts/manifest.json
    exit
fi
[[ $stage == root || $stage == filesystem ]]
if [[ $stage == filesystem ]]; then
    bash /builder/src/public/filesystem.sh
    exit
fi
[[ $(uname -m) == aarch64 ]]
root=/job/root
[[ ! -e $root ]]
mkdir -p "$root" /job/original-fedora /job/keydb
project=$(jq -er --arg channel "$channel" '.channels[$channel].project' "$policy")
fingerprint=$(jq -er --arg channel "$channel" '.channels[$channel].fingerprint' "$policy")
key=/cache/$project.asc
if [[ ${UKE_OFFLINE:-0} != 1 ]]; then
    curl --proto '=https' --tlsv1.2 -fL --retry 3 "https://download.copr.fedorainfracloud.org/results/mcc45tr/$project/pubkey.gpg" -o "$key.part"
    mv "$key.part" "$key"
fi
[[ $(gpg --show-keys --with-colons "$key" | awk -F: '$1=="fpr" {print $10;exit}') == "$fingerprint" ]]
install -m644 "$key" /etc/pki/rpm-gpg/RPM-GPG-KEY-uke-selected
install -m644 /builder/configs/keys/fedora-46.asc /etc/pki/rpm-gpg/RPM-GPG-KEY-uke-fedora46
cat > /etc/yum.repos.d/uke-selected.repo <<REPO
[uke-selected]
name=Uke $channel
baseurl=https://download.copr.fedorainfracloud.org/results/mcc45tr/$project/fedora-rawhide-\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-uke-selected
skip_if_unavailable=False
priority=40
includepkgs=uke-*,senemos-uke-linux-kernel-*
REPO
packages=(fedora-release fedora-repos bash coreutils dnf5 dnf5-plugins glibc-all-langpacks
    systemd systemd-udev systemd-pam NetworkManager NetworkManager-wifi bluez chrony
    firewalld openssh-server sudo shadow-utils selinux-policy-targeted policycoreutils
    e2fsprogs f2fs-tools btrfs-progs xfsprogs util-linux kbd less nano fastfetch
    pipewire pipewire-pulseaudio wireplumber
    uke-core uke-hw uke-power uke-sensors uke-additional uke-firmware
    uke-touchscreen uke-ssc-fileservice uke-adaptive-display uke-battery-observer
    uke-charge-control uke-offline-charge)
desktop=$(jq -er .desktop "$request")
if [[ $desktop == kde ]]; then
    packages+=(uke-kde-plasma-meta plasma-setup kde-settings-plasmalogin)
else
    packages+=(gnome-shell gnome-session-wayland-session gdm gnome-initial-setup
        gnome-control-center gnome-software gnome-console nautilus)
fi
release=$(jq -er .kernel.release "$policy")
base=senemos-uke-linux-kernel-mainline
local_rpms=()
for component in '' -core -modules -dtbs -boot; do
    package=/job/artifacts/kernel/$base$component-$release.fc46.aarch64.rpm
    [[ -f $package ]]
    local_rpms+=("$package")
done
if [[ $partition == userdata ]]; then
    local_rpms+=("/job/artifacts/kernel/$base-singleboot-$release.fc46.aarch64.rpm")
fi
# Source-built local RPMs are unsigned. Remote RPM signature checks stay enabled.
dnf=(dnf5 "${cache_flags[@]}" --use-host-config --installroot="$root" --releasever=rawhide
    --disable-repo='*' --enable-repo=rawhide --enable-repo=uke-selected
    --setopt=cachedir="/cache/dnf-$channel" --setopt=keepcache=True
    --setopt=install_weak_deps=False --setopt=gpgcheck=True --setopt=installonly_limit=0
    --setopt=tsflags=nodocs --setopt=excludepkgs='kernel,kernel-core,kernel-modules*,*-debuginfo,*-debugsource,uke-local-touch-data,senemos-uke-linux-kernel-mainline-kvm*,senemos-uke-linux-kernel-mainline-unstable*')
if [[ -d /job/artifacts/runtime ]]; then
    local_repository
    dnf+=(--enable-repo=uke-source-build)
fi
"${dnf[@]}" -y install "${local_rpms[@]}" "${packages[@]}"
"${dnf[@]}" check
rpm --root "$root" -qa --qf '%{NEVRA}\t%{SOURCERPM}\t%{VENDOR}\n' | LC_ALL=C sort > /job/artifacts/installed-rpms.tsv
[[ $(rpm --root "$root" -q "$base-core" --qf '%{VERSION}-%{RELEASE}') == "$release.fc46" ]]
bundle=$root/usr/lib/senemos/kernel-updates/$release
(cd "$root/usr/lib/modules/$release"; sha256sum -c "$bundle/modules.sha256")
cp "$bundle/$partition.img" /job/artifacts/boot.img
cmp /job/artifacts/boot.img "/job/artifacts/boot-$partition.img"
# Prove Python exceptions against independently signature-verified Fedora bytes.
rpmkeys --dbpath /job/keydb --import /builder/configs/keys/fedora-46.asc
: > /job/artifacts/fedora-inputs.tsv
while IFS= read -r -d '' archive; do
    [[ $(rpm -qp --qf '%{VENDOR}' "$archive") == 'Fedora Project' ]] || continue
    name=$(rpm -qp --qf '%{NAME}' "$archive")
    [[ $(rpm --root "$root" -q "$name" --qf '%{NEVRA}' 2>/dev/null) == "$(rpm -qp --qf '%{NEVRA}' "$archive")" ]] || continue
    rpmkeys --dbpath /job/keydb --checksig "$archive" | grep -F 'signatures OK'
    printf '%s\t%s\n' "$(rpm -qp --qf '%{NEVRA}' "$archive")" "$(sha256sum "$archive" | cut -d ' ' -f1)" >> /job/artifacts/fedora-inputs.tsv
    rpm2cpio "$archive" > /job/payload.cpio
    (cd /job/original-fedora; cpio -idmu --quiet --no-absolute-filenames < /job/payload.cpio)
done < <(find "/cache/dnf-$channel" -type f -name '*.rpm' -print0)
[[ -s /job/artifacts/fedora-inputs.tsv ]]
bash /builder/src/audit/check-target-payload.sh --original-kde-payload /job/original-fedora "$root"
chroot "$root" /usr/sbin/usermod -L root
systemctl --root="$root" enable NetworkManager.service firewalld.service bluetooth.service chronyd.service
systemctl --root="$root" disable sshd.service sshd.socket
systemctl --root="$root" mask debug-shell.service uke-boot-guard.service
systemctl --root="$root" set-default graphical.target
if [[ $desktop == kde ]]; then
    chroot "$root" /usr/bin/kwriteconfig6 --file /etc/xdg/plasmasetuprc --group Accounts --key UserGroups wheel
    chroot "$root" /usr/bin/systemd-sysusers /usr/lib/sysusers.d/plasma-setup-sysuser.conf
    systemctl --root="$root" enable plasma-setup.service plasmalogin.service
else
    systemctl --root="$root" enable gdm.service
fi
mkdir -p "$root/etc/senemos" "$root/etc/uke-control" "$root/etc/dnf" "$root/var/lib/uke-touch"
printf 'automatic=0\n' > "$root/etc/senemos/kernel-update.conf"
printf 'automatic=0\n' > "$root/etc/senemos/userdata-update.conf"
internal_channel=$channel
[[ $channel != testing ]] || internal_channel='test'
printf '%s\n' "$internal_channel" > "$root/etc/uke-control/channel"
printf 'PARTLABEL=%s / %s defaults,noatime 0 0\n' "$partition" "$filesystem" > "$root/etc/fstab"
cat /builder/configs/images/uke-persist.fstab >> "$root/etc/fstab"
mkdir -p "$root/mnt/vendor/persist"
chmod 700 "$root/mnt/vendor/persist"
printf 'SELINUX=enforcing\nSELINUXTYPE=targeted\n' > "$root/etc/selinux/config"
install -m644 /etc/pki/rpm-gpg/RPM-GPG-KEY-uke-selected "$root/etc/pki/rpm-gpg/"
install -m644 /etc/yum.repos.d/uke-selected.repo "$root/etc/yum.repos.d/"
cat > "$root/etc/dnf/dnf.conf" <<'DNF'
[main]
install_weak_deps=False
installonly_limit=0
excludepkgs=kernel,kernel-core,kernel-modules*,*-debuginfo,*-debugsource
DNF
private=false
if [[ -f /job/inputs/reference.bin ]]; then
    [[ ! -L /job/inputs/reference.bin && $(stat -c %s /job/inputs/reference.bin) == 5432 ]]
    install -m600 /job/inputs/reference.bin "$root/var/lib/uke-touch/reference.bin"
    private=true
fi
# Generic images can complete setup using USB input until their own touch data exist.
mkdir -p "$root/etc/systemd/system/uke-touchscreen.service.d"
printf '[Unit]\nConditionPathExists=/var/lib/uke-touch/reference.bin\n' > "$root/etc/systemd/system/uke-touchscreen.service.d/local-data.conf"
for unit in uke-touchscreen.service uke-wifi-factory.service uke-install-profile.service; do
    systemctl --root="$root" enable "$unit"
done
# The source initramfs grows only provisioned F2FS userdata before mounting it.
find "$root/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*' -delete
find "$root/var/log" "$root/tmp" "$root/var/tmp" -mindepth 1 -depth -delete
for file in etc/machine-id var/lib/dbus/machine-id var/lib/systemd/random-seed; do
    rm -f "$root/$file"
done
: > "$root/etc/machine-id"
[[ ! -e $root/var/lib/uke-touch/reference.bin || $private == true ]]
jq --argjson private "$private" '. + {device_private_data_included:$private,
    oem_firmware_included:true,redistribution_review_required:true,
    touch_reference_validation:"shape and permissions only; physical acceptance is separate",
    python_policy:"only byte-identical signature-verified original Fedora packages",
    credentials_included:false,ssh_enabled:false}' /job/artifacts/manifest.json > /job/manifest.tmp
mv /job/manifest.tmp /job/artifacts/manifest.json
tar --create --numeric-owner --one-file-system --sort=name --acls --xattrs --xattrs-include=security.capability -f /job/rootfs.tar -C "$root" .
