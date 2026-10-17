#!/usr/bin/env bash
set -Eeuo pipefail
builder=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture"/{bin,root/usr/share/uke,root/etc/pki/rpm-gpg,root/etc/yum.repos.d,root/etc/dnf}
touch "$fixture/root/usr/share/uke/alpha-release.json" "$fixture/root/etc/pki/rpm-gpg/RPM-GPG-KEY-uke-copr"
printf 'excludepkgs=senemos-uke-linux-kernel-mainline*\n' > "$fixture/root/etc/dnf/dnf.conf"
printf '#!/bin/sh\nexit 0\n' > "$fixture/bin/rpm"
cat > "$fixture/bin/gpg" <<'SH'
#!/bin/sh
printf 'fpr:::::::::%s:\n' "${TEST_KEY:-DAFC3C5A881FB49C7167EE2D6F772E3D487BD13E}"
SH
chmod +x "$fixture/bin/"*
export PATH=$fixture/bin:$PATH
touch "$fixture/root/etc/yum.repos.d/uke-development.repo"
bash "$builder/src/image/prepare-copr.sh" "$fixture/root"
repo=$fixture/root/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:mcc45tr:uke-linux-test.repo
[[ ! -e $fixture/root/etc/yum.repos.d/uke-development.repo ]]
grep -Fx 'enabled=1' "$repo"
grep -Fx 'gpgcheck=1' "$repo"
# shellcheck disable=SC2016
grep -F 'fedora-rawhide-$basearch/' "$repo"
before=$(sha256sum "$repo")
if TEST_KEY=0000000000000000000000000000000000000000 bash "$builder/src/image/prepare-copr.sh" "$fixture/root" >/dev/null 2>&1; then exit 1; fi
[[ $(sha256sum "$repo") == "$before" ]]
echo 'Default native COPR configuration, signature policy and foreign-key refusal fixtures passed.'
