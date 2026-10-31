#!/usr/bin/env bash
# Retrieve one signed, matched kernel family; never execute its scriptlets here.
set -Eeuo pipefail
channel=$(jq -er .channel /job/request.json)
[[ $channel == testing || $channel == unstable ]]
# shellcheck source=channel.sh
# shellcheck disable=SC1091
source /builder/src/public/channel.sh
public_channel "$channel" /builder/configs/public-build.json
base=senemos-uke-linux-kernel-mainline
project=$PUBLIC_PROJECT
key=/cache/$project.asc
if [[ ${UKE_OFFLINE:-0} != 1 ]]; then
    curl --proto '=https' --tlsv1.2 -fL --retry 3 \
        "https://download.copr.fedorainfracloud.org/results/mcc45tr/$project/pubkey.gpg" -o "$key.part"
    mv "$key.part" "$key"
fi
expected=$PUBLIC_FINGERPRINT
[[ $(gpg --show-keys --with-colons "$key" | awk -F: '$1=="fpr" {print $10;exit}') == "$expected" ]]
mkdir -p /job/kernel-keydb /job/artifacts/kernel /job/kernel-payload
rpmkeys --dbpath /job/kernel-keydb --import "$key"
kernel_repository=https://download.copr.fedorainfracloud.org/results/mcc45tr/$project/fedora-rawhide-aarch64/
if [[ -n ${UKE_COPR_ROOT_INPUTS:-} ]]; then
    [[ $UKE_COPR_ROOT_INPUTS == /inputs/target && ${UKE_OFFLINE:-0} == 1 && -f /.uke-copr-sdk && $(< /.uke-copr-sdk) == 1 ]]
    kernel_repository=file:///inputs/target/rpms/uke
fi
cat > /etc/yum.repos.d/uke-kernel.repo <<REPO
[uke-kernel]
name=Uke $channel kernel inputs
baseurl=$kernel_repository
enabled=0
gpgcheck=1
skip_if_unavailable=False
REPO
dnf=(dnf5 --forcearch=aarch64 --disable-repo='*' --enable-repo=uke-kernel
    --setopt=cachedir=/cache/kernel-repository --setopt=keepcache=True)
[[ ${UKE_OFFLINE:-0} != 1 || -n ${UKE_COPR_ROOT_INPUTS:-} ]] || dnf+=(--cacheonly)
# Freeze this release branch; remote package updates must not change its kernel tuple.
release=$(jq -er .kernel_rpm_request /job/request.json)
if [[ $release == latest ]]; then
    release=$("${dnf[@]}" repoquery --latest-limit=1 --arch=aarch64 --qf '%{version}-%{release}' "$base-core")
fi
[[ $release =~ ^7[.]3[.][0-9]+-[1-9][0-9]*[.]fc46$ ]]
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
rpm_evr=$release
release=${release%.fc46}
version=${release%-*}
rpm_release=$release
source_commit=$(cat "/job/kernel-payload/usr/share/senemos/uke/$release/source-commit")
[[ $source_commit =~ ^[0-9a-f]{40}$ ]]
if [[ -n ${UKE_COPR_ROOT_INPUTS:-} ]]; then
    [[ $(jq -er .kernel_commit /job/request.json) == "$source_commit" &&
       $(jq -er .kernel_version /job/request.json) == "$version" ]] || {
        echo 'Frozen kernel source or version differs from the requested tuple' >&2
        exit 1
    }
fi
bundle=/job/kernel-payload/usr/lib/senemos/kernel-updates/$release
modules=/job/kernel-payload/usr/lib/modules/$release
[[ -f $bundle/linux.img && -f $bundle/userdata.img && -f $modules/vmlinuz ]]
(cd "$modules"; sha256sum -c "$bundle/modules.sha256")
if [[ $channel == unstable ]]; then
    cp "$UKE_IMAGE_TOOLS/boot-image" /job/boot-image
else
    c++ -std=c++20 -O2 -Wall -Wextra -Werror /builder/src/boot/boot-image.cpp -o /job/boot-image
fi
for profile in linux userdata; do
    /job/boot-image inspect "$bundle/$profile.img" > "/job/artifacts/kernel/boot-$profile.json"
    /job/boot-image extract "$bundle/$profile.img" "/job/$profile.Image"
    cmp "$modules/vmlinuz" "/job/$profile.Image"
    cp "$bundle/$profile.img" "/job/artifacts/boot-$profile.img"
done
rpm -qp --qf '%{NEVRA}\t%{SOURCERPM}\n' "${archives[@]}" | LC_ALL=C sort > /job/artifacts/kernel/packages.tsv
(cd /job/artifacts/kernel; sha256sum -- *.rpm) > /job/artifacts/kernel/RPM-SHA256SUMS
jq -n --arg release "$release" --arg version "$version" --arg dist .fc46 --arg family "$base" --arg source "$source_commit" --arg fingerprint "$expected" --arg rpm "$rpm_release" --arg repository "mcc45tr/$project" \
    '{rpm_dist:$dist,kernel_profile:"normal",kernel_family:$family,rpm_version_release:$rpm,kernel_commit:$source,kernel_source_commit:$source,kernel_version:$version,kernel_release:$release,kernel_rpms_locally_built:false,kernel_repository:$repository,
      kernel_rpm_signature:"verified COPR signature",kernel_key_fingerprint:$fingerprint,
      physical_boot_tested:false,hardware_tested:false,automatic_kernel_activation:false}' > /job/artifacts/kernel/kernel-info.json
jq --slurpfile info /job/artifacts/kernel/kernel-info.json '. + $info[0]' /job/request.json > /job/request.tmp
mv /job/request.tmp /job/request.json
cp /job/request.json /job/artifacts/manifest.json
jq -n --arg route repository --arg evr "$rpm_evr" --arg fingerprint "$expected" --arg repository "mcc45tr/$project" '{route:$route,rpm_evr:$evr,repository:$repository,signer_fingerprint:$fingerprint}' > /job/artifacts/kernel/producer.json
# Consumers only need the retained RPMs and receipts; discard the temporary extraction.
rm -rf /job/kernel-payload /job/payload.cpio /job/linux.Image /job/userdata.Image
