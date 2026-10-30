#!/usr/bin/env bash
# COPR source worker only: public signed Fedora inputs, no native compilation.
set -Eeuo pipefail
[[ $# == 2 && -d $1 && -d $2 && -n ${COPR_RESULTDIR:-} ]]
recipe=$1 output=$2
mkdir -p "$output/rpms" "$output/keydb"
key=$recipe/configs/keys/fedora-46.asc
[[ $(gpg --batch --show-keys --with-colons "$key" | awk -F: '$1=="fpr" {print $10;exit}') == D924B10D3E810DABDD8B56B596E7E91491211FCE ]]
# Resolve every dependency, including packages already installed on this worker.
# The SDK is build-only; no worker filesystem, database or identity is archived.
packages=(bash coreutils dnf5 dnf5-plugins rpm rpm-build fedora-release-common
    filesystem setup systemd chrony util-linux shadow-utils jq tar cpio
    grep sed gawk findutils diffutils gnupg2 curl kmod policycoreutils attr acl xz zstd)
dnf5 --forcearch=aarch64 --releasever=rawhide --disable-repo='*' \
    --repofrompath=copr-public-fedora,https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Everything/aarch64/os/ \
    --enable-repo=copr-public-fedora \
    --setopt=install_weak_deps=False download --resolve --alldeps \
    --destdir="$output/rpms" "${packages[@]}"
rpmkeys --dbpath "$output/keydb" --import "$key"
: > "$output/rpms.tsv"
shopt -s nullglob
archives=("$output/rpms/"*.rpm)
(( ${#archives[@]} > 0 ))
for archive in "${archives[@]}"; do
    [[ $(rpm -qp --qf '%{VENDOR}' "$archive") == 'Fedora Project' ]]
    case $(rpm -qp --qf '%{ARCH}' "$archive") in aarch64|noarch) ;; *) exit 1;; esac
    rpmkeys --dbpath "$output/keydb" --checksig "$archive" | grep -F 'signatures OK'
    rpm -qp --qf '%{NEVRA}\t%{SOURCERPM}\n' "$archive" >> "$output/rpms.tsv"
done
LC_ALL=C sort -o "$output/rpms.tsv" "$output/rpms.tsv"
# Package signatures are mandatory in the guest; metadata has no secret key.
createrepo_c --no-database "$output/rpms"
find "$output/keydb" -depth -delete
(cd "$output"; find rpms -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS)
tar -cJf "$COPR_RESULTDIR/guest-fedora-inputs.tar.xz" -C "$output" .
