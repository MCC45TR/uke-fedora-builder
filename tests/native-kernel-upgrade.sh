#!/usr/bin/env bash
# Disposable AArch64 userspace fixture; no device boot or partition operation.
set -Eeuo pipefail
[[ $# == 7 && -d $1 && -d $2 && -d $3 ]]
builder=$1 packages_dir=$2 out=$3 target=$4 image_hash=$5 dtb_hash=$6 previous=$7
[[ $target =~ ^[0-9.]+-[0-9.]+\.fc[0-9]+\.aarch64$ && $previous =~ ^[0-9.]+-[0-9.]+\.fc[0-9]+\.aarch64$ ]]
[[ $image_hash =~ ^[a-f0-9]{64}$ && $dtb_hash =~ ^[a-f0-9]{64}$ ]]
[[ $(uname -m) == aarch64 ]]
names=(senemos-uke-linux-kernel-mainline{,-core,-modules,-dtbs})
packages=()
rpmkeys --import "$builder/configs/keys/uke-copr.asc"
for name in "${names[@]}"; do
    package=$packages_dir/$name-$target.rpm
    [[ -f $package && ! -L $package ]]
    rpmkeys --checksig "$package" | grep -F 'signatures OK'
    [[ $(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$name") == "$previous" ]]
    packages+=("$package")
done
check_installed() {
    local name root=/usr/lib/modules/7.2.9-senemos-uke
    for name in "${names[@]}"; do
        [[ $(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$name") == "$target" ]]
    done
    [[ $(sha256sum "$root/vmlinuz" | cut -d ' ' -f1) == "$image_hash" ]]
    [[ $(sha256sum "$root/dtb/qcom/sm7675-xiaomi-uke.dtb" | cut -d ' ' -f1) == "$dtb_hash" ]]
    [[ -s $root/kernel/drivers/usb/class/cdc-acm.ko.zst ]]
    rpm -V "${names[@]}"
}
check_absent() {
    local name
    for name in "${names[@]}"; do
        if rpm -q "$name"; then echo "Package remained after removal: $name" >&2; exit 1; fi
    done
    [[ ! -e /usr/lib/modules/7.2.9-senemos-uke/vmlinuz ]]
}
dnf -y --disablerepo='*' --setopt=localpkg_gpgcheck=1 install "${packages[@]}"
check_installed
dnf -y remove "${names[@]}"
check_absent
dnf -y --disablerepo='*' --setopt=localpkg_gpgcheck=1 install "${packages[@]}"
check_installed
rpm -q "${names[@]}" > "$out/fresh-installed-nevra.txt"
dnf -y remove "${names[@]}"
check_absent
echo 'Signed native package upgrade, removal, fresh installation and final removal passed'
