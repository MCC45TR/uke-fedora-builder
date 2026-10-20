#!/usr/bin/env bash
# Offline private-root package transaction; never installs into the running host.
set -Eeuo pipefail
[[ $# == 0 && -f /job/packages.complete && ! -e /job/rootfs-frozen ]]
root=/job/root
config=/builder/configs/images/userdata-rawhide.json
[[ -d $root && ! -L $root ]]
reference=$root/var/lib/uke-touch/reference.bin
[[ -f $reference && ! -L $reference ]]
reference_sha=$(sha256sum "$reference" | cut -d ' ' -f1)
jq -e '.profile=="plasma-userdata-private-device-test" and .oem_runtime_inputs.required==true' "$config" >/dev/null
for kind in oem firmware; do
    name=oem-runtime-source.json; [[ $kind != firmware ]] || name=local-firmware-candidates.json
    [[ $(sha256sum "/job/inputs/$name" | cut -d ' ' -f1) == "$(jq -er ".oem_runtime_inputs.${kind}_manifest_sha256" "$config")" ]]
done
(cd /job/inputs/oem-rpms && sha256sum -c --strict SHA256SUMS)
shopt -s nullglob
packages=(/job/inputs/oem-rpms/*.noarch.rpm)
[[ ${#packages[@]} == 1 ]]
for file in "${packages[@]}"; do [[ -f $file && ! -L $file ]]; done
for file in "${packages[@]}"; do
    [[ $(sha256sum "$file" | cut -d ' ' -f1) == "$(jq -er --arg name "${file##*/}" '.oem_runtime_inputs.rpm_sha256[$name]' "$config")" ]]
done
nevra=$(jq -er .oem_runtime_inputs.firmware_nevra "$config")
file=/job/inputs/oem-rpms/$nevra.rpm
[[ -f $file && $(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$file") == "$nevra" ]]
[[ -z $(rpm -qp --scripts "$file") ]]
if rpm -qp --requires "$file" | grep -Ei 'python|pypy|libpython'; then exit 1; fi
rpmkeys --define '_pkgverify_level digest' --checksig "${packages[@]}" > /job/logs/oem-rpm-digests.log
# Only this locally built, source-pinned data RPM uses digest admission.
dnf5 --use-host-config --installroot="$root" --releasever=rawhide --disable-repo='*' \
    --setopt=excludepkgs= --setopt=localpkg_gpgcheck=False --setopt=install_weak_deps=False \
    -y install "${packages[@]}" > /job/logs/oem-install.log 2>&1
dnf5 --use-host-config --installroot="$root" --releasever=rawhide --disable-repo='*' \
    --setopt=excludepkgs= check > /job/logs/oem-dependency-check.log 2>&1
# DNF creates an empty runtime directory even for an offline installroot.
if [[ -d $root/run/dnf && ! -L $root/run/dnf ]]; then rmdir "$root/run/dnf"; fi
banned='^(uke-local-(gpu-firmware|sensor-data|bluetooth-firmware)|uke-owner-(adsp-firmware|wpss-firmware|wlan-board|wlan-regdb))$'
if rpm --root "$root" -qa --qf '%{NAME}\n' | grep -E "$banned"; then exit 1; fi
[[ $(rpm --root "$root" -q "${nevra%.noarch}" --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}') == "$nevra" ]]
[[ $(sha256sum "$reference" | cut -d ' ' -f1) == "$reference_sha" ]]
bash /builder/src/image/audit-oem-runtime.sh "$root" /job/inputs/oem-runtime-source.json \
    /job/inputs/local-firmware-candidates.json /job/audit/oem-runtime-inputs.json
systemctl --root="$root" enable uke-adaptive-display.target uke-bluetooth-address.service
for service in uke-adaptive-display.target uke-bluetooth-address.service uke-touchscreen.service; do
    [[ $(systemctl --root="$root" is-enabled "$service") == enabled ]]
done
printf '%s\n' 'Unified OEM firmware installed into the offline candidate; existing private touch inputs retained.' > /job/oem-runtime.complete
