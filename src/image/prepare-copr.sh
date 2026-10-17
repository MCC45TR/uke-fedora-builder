#!/usr/bin/env bash
# Host composer only; use the verified Uke development COPR with native DNF5.
set -Eeuo pipefail
[[ $# == 1 && -d $1 && ! -L $1 ]] || exit 2
root=$(realpath -- "$1")
[[ $root != / && -f $root/usr/share/uke/alpha-release.json ]] || exit 2
rpm --root "$root" -q dnf5-plugins >/dev/null
key=$root/etc/pki/rpm-gpg/RPM-GPG-KEY-uke-copr
fingerprint=$(gpg --batch --show-keys --with-colons "$key" 2>/dev/null | awk -F: '$1=="fpr" {print $10;exit}')
[[ $fingerprint == DAFC3C5A881FB49C7167EE2D6F772E3D487BD13E ]]
mkdir -p "$root/etc/yum.repos.d"
rm -f "$root/etc/yum.repos.d/uke-development.repo"
cat > "$root/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:mcc45tr:uke-linux-test.repo" <<'REPO'
[copr:copr.fedorainfracloud.org:mcc45tr:uke-linux-test]
name=Uke Linux development packages
baseurl=https://download.copr.fedorainfracloud.org/results/mcc45tr/uke-linux-test/fedora-rawhide-$basearch/
type=rpm-md
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-uke-copr
skip_if_unavailable=True
REPO
# The current COPR kernel lacks a matched stock-ABL boot payload.
grep -Fxq 'excludepkgs=senemos-uke-linux-kernel-mainline*' "$root/etc/dnf/dnf.conf"
echo 'Verified Uke COPR enabled and discoverable by dnf copr list; unmatched kernel updates remain pinned.'
