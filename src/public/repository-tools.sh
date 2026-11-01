#!/usr/bin/env bash
# Sourced inside an isolated AArch64 assembly worker; only signed RPM bytes run.
set -Eeuo pipefail
[[ $(uname -m) == aarch64 ]]
tools_policy=/builder/configs/public-build.json
tools_project=$(jq -er .build_tools.project "$tools_policy")
tools_fingerprint=$(jq -er .build_tools.fingerprint "$tools_policy")
tools_nevra=$(jq -er .build_tools.nevra "$tools_policy")
[[ $tools_project == uke-linux-unstable && $tools_fingerprint == 2204A661EA630A5303500085538797E72A3E4ECA &&
   $tools_nevra =~ ^uke-image-tools-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.fc46\.aarch64$ ]]
tools_key=/cache/$tools_project.asc
if [[ ${UKE_OFFLINE:-0} != 1 ]]; then
    curl --proto '=https' --tlsv1.2 -fL --retry 3 \
        "https://download.copr.fedorainfracloud.org/results/mcc45tr/$tools_project/pubkey.gpg" -o "$tools_key.part"
    mv "$tools_key.part" "$tools_key"
fi
[[ $(gpg --show-keys --with-colons "$tools_key" | awk -F: '$1=="fpr" {print $10;exit}') == "$tools_fingerprint" ]]
mkdir -p /job/tools-keydb /job/artifacts/tools /job/tools-payload
rpmkeys --dbpath /job/tools-keydb --import "$tools_key"
tools_archive=/job/artifacts/tools/$tools_nevra.rpm
if [[ ! -f $tools_archive ]]; then
    cat > /etc/yum.repos.d/uke-image-tools.repo <<REPO
[uke-image-tools]
name=Signed Uke image assembly tools
baseurl=https://download.copr.fedorainfracloud.org/results/mcc45tr/$tools_project/fedora-rawhide-aarch64/
enabled=0
gpgcheck=1
gpgkey=file://$tools_key
skip_if_unavailable=False
REPO
    tools_dnf=(dnf5 --forcearch=aarch64 --disable-repo='*' --enable-repo=uke-image-tools
        --setopt=cachedir=/cache/image-tools-repository --setopt=keepcache=True)
    [[ ${UKE_OFFLINE:-0} != 1 ]] || tools_dnf+=(--cacheonly)
    "${tools_dnf[@]}" download --destdir=/job/artifacts/tools "$tools_nevra"
fi
[[ -f $tools_archive && ! -L $tools_archive &&
   $(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$tools_archive") == "$tools_nevra" ]]
rpmkeys --dbpath /job/tools-keydb --checksig "$tools_archive" | grep -F 'signatures OK'
rpm2cpio "$tools_archive" > /job/tools-payload.cpio
(cd /job/tools-payload; cpio -idmu --quiet --no-absolute-filenames --io-size=1048576 < /job/tools-payload.cpio)
export UKE_IMAGE_TOOLS=/job/tools-payload/usr/libexec/uke-image-tools
for tools_binary in boot-image android-sparse ext4-labels check-userdata-payload audit-languages compare-root-metadata; do
    [[ -f $UKE_IMAGE_TOOLS/$tools_binary && ! -L $UKE_IMAGE_TOOLS/$tools_binary && -x $UKE_IMAGE_TOOLS/$tools_binary ]]
done
rpm -qp --qf '%{NEVRA}\t%{SOURCERPM}\n' "$tools_archive" > /job/artifacts/tools/packages.tsv
(cd /job/artifacts/tools; sha256sum -- "$tools_nevra.rpm") > /job/artifacts/tools/RPM-SHA256SUMS
cp /job/tools-payload/usr/share/uke-image-tools/source-identity.json /job/artifacts/tools/source-identity.json
jq -n --arg package "$tools_nevra" --arg hash "$(sha256sum "$tools_archive" | cut -d ' ' -f1)" \
    --arg signer "$tools_fingerprint" --slurpfile source /job/artifacts/tools/source-identity.json \
    '{package:$package,rpm_sha256:$hash,signer_fingerprint:$signer,source:$source[0]}' > /job/artifacts/tools/manifest.json
