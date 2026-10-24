#!/usr/bin/env bash
# Retrieve one signed, matched kernel family; never execute its scriptlets here.
set -Eeuo pipefail
[[ $(jq -er .channel /job/request.json) == testing ]]
base=senemos-uke-linux-kernel-mainline
project=uke-linux-test
key=/cache/$project.asc
if [[ ${UKE_OFFLINE:-0} != 1 ]]; then
    curl --proto '=https' --tlsv1.2 -fL --retry 3 \
        "https://download.copr.fedorainfracloud.org/results/mcc45tr/$project/pubkey.gpg" -o "$key.part"
    mv "$key.part" "$key"
fi
expected=$(jq -er .channels.testing.fingerprint /builder/configs/public-build.json)
[[ $(gpg --show-keys --with-colons "$key" | awk -F: '$1=="fpr" {print $10;exit}') == "$expected" ]]
mkdir -p /job/kernel-keydb /job/artifacts/kernel /job/kernel-payload
rpmkeys --dbpath /job/kernel-keydb --import "$key"
cat > /etc/yum.repos.d/uke-kernel.repo <<'REPO'
[uke-kernel]
name=Uke testing kernel inputs
baseurl=https://download.copr.fedorainfracloud.org/results/mcc45tr/uke-linux-test/fedora-rawhide-aarch64/
enabled=0
gpgcheck=1
skip_if_unavailable=False
REPO
dnf=(dnf5 --forcearch=aarch64 --disable-repo='*' --enable-repo=uke-kernel
    --setopt=cachedir=/cache/kernel-repository --setopt=keepcache=True)
[[ ${UKE_OFFLINE:-0} != 1 ]] || dnf+=(--cacheonly)
release=$("${dnf[@]}" repoquery --arch=aarch64 --latest-limit=1 --queryformat '%{version}-%{release}' "$base-core")
[[ $release =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.fc46$ ]]
packages=()
for component in '' -core -modules -dtbs -boot -singleboot; do
    packages+=("$base$component-$release.aarch64")
done
"${dnf[@]}" download --destdir=/job/artifacts/kernel "${packages[@]}"
archives=(/job/artifacts/kernel/*.aarch64.rpm)
[[ ${#archives[@]} == 6 ]]
for archive in "${archives[@]}"; do
    rpmkeys --dbpath /job/kernel-keydb --checksig "$archive" | grep -F 'signatures OK'
    [[ $(rpm -qp --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$archive") == "$release.aarch64" ]]
    rpm2cpio "$archive" > /job/payload.cpio
    (cd /job/kernel-payload; cpio -idmu --quiet --no-absolute-filenames --io-size=1048576 < /job/payload.cpio)
done
release=${release%.fc46}
source_commit=$(cat "/job/kernel-payload/usr/share/senemos/uke/$release/source-commit")
[[ $source_commit =~ ^[0-9a-f]{40}$ ]]
bundle=/job/kernel-payload/usr/lib/senemos/kernel-updates/$release
modules=/job/kernel-payload/usr/lib/modules/$release
[[ -f $bundle/linux.img && -f $bundle/userdata.img && -f $modules/vmlinuz ]]
(cd "$modules"; sha256sum -c "$bundle/modules.sha256")
c++ -std=c++20 -O2 -Wall -Wextra -Werror /builder/src/boot/boot-image.cpp -o /job/boot-image
for profile in linux userdata; do
    /job/boot-image inspect "$bundle/$profile.img" > "/job/artifacts/kernel/boot-$profile.json"
    /job/boot-image extract "$bundle/$profile.img" "/job/$profile.Image"
    cmp "$modules/vmlinuz" "/job/$profile.Image"
    cp "$bundle/$profile.img" "/job/artifacts/boot-$profile.img"
done
rpm -qp --qf '%{NEVRA}\t%{SOURCERPM}\n' "${archives[@]}" | LC_ALL=C sort > /job/artifacts/kernel/packages.tsv
(cd /job/artifacts/kernel; sha256sum -- *.rpm) > /job/artifacts/kernel/RPM-SHA256SUMS
jq --arg release "$release" --arg source "$source_commit" --arg fingerprint "$expected" \
    '. + {kernel_source_commit:$source,kernel_release:$release,kernel_rpms_locally_built:false,kernel_repository:"mcc45tr/uke-linux-test",
      kernel_rpm_signature:"verified COPR signature",kernel_key_fingerprint:$fingerprint,
      physical_boot_tested:false,hardware_tested:false,automatic_kernel_activation:false}' \
    /job/request.json > /job/artifacts/manifest.json
