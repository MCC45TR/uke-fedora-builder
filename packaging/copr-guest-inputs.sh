#!/usr/bin/env bash
# COPR source worker only: public signed Fedora inputs, no native compilation.
set -Eeuo pipefail
[[ $# == 2 && -d $1 && -d $2 && -n ${COPR_RESULTDIR:-} ]]
recipe=$1 output=$2
mkdir -p "$output/rpms" "$output/keydb" "$output/closures" "$output/download-cache"
key=$recipe/configs/keys/fedora-46.asc
[[ $(gpg --batch --show-keys --with-colons "$key" | awk -F: '$1=="fpr" {print $10;exit}') == D924B10D3E810DABDD8B56B596E7E91491211FCE ]]
bash "$recipe/packaging/copr-root-closure.sh" "$recipe" "$output/closures/full-root" "$output/download-cache"
# Resolve every dependency, including packages already installed on this worker.
# The SDK is build-only; no worker filesystem, database or identity is archived.
sdk_packages=(bash coreutils dnf5 dnf5-plugins rpm rpm-build fedora-release-common
    filesystem setup systemd chrony util-linux shadow-utils jq tar cpio
    grep sed gawk findutils diffutils gnupg2 curl kmod policycoreutils attr acl xz zstd
    e2fsprogs libcap)
mapfile -t fixture_packages < <(jq -er '.[]' "$recipe/configs/copr-image-fixture-packages.json")
shopt -s nullglob
for closure in sdk fixture; do
    solver=$output/solver-$closure
    stored=$output/transaction-$closure
    mkdir -p "$solver/usr/lib/sysimage/rpm"
    rpm --dbpath "$solver/usr/lib/sysimage/rpm" --initdb
    refresh_options=()
    if [[ $closure == sdk ]]; then
        packages=("${sdk_packages[@]}")
        # The preceding full-goal audit can outlive a Rawhide compose change.
        refresh_options=(--refresh)
    else
        packages=("${fixture_packages[@]}")
    fi
    # Resolve the whole requested set together. `download --resolve` resolves
    # individual packages and can miss conditional requirements between them.
    # Store downloads only; it neither installs nor replays a transaction here.
    dnf5 "${refresh_options[@]}" --forcearch=aarch64 --releasever=rawhide --installroot="$solver" \
        --disable-repo='*' \
        --repofrompath=copr-public-fedora,https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Everything/aarch64/os/ \
        --setopt=copr-public-fedora.baseurl= \
        --setopt='copr-public-fedora.metalink=https://mirrors.fedoraproject.org/metalink?repo=rawhide&arch=aarch64&protocol=https' \
        --enable-repo=copr-public-fedora --setopt=cachedir="$output/download-cache" \
        --setopt=copr-public-fedora.gpgkey="file://$key" --setopt=install_weak_deps=False \
        --setopt=copr-public-fedora.metadata_expire=-1 \
        --assumeyes install --store="$stored" "${packages[@]}"
    jq -e '.version=="1.0" and (.rpms|length)>0 and all(.rpms[];.action=="Install")' "$stored/transaction.json" > /dev/null
    cp "$stored/transaction.json" "$output/closures/$closure.json"
    : > "$output/closures/$closure-rpms.list"
    archives=("$stored/packages/"*.rpm)
    (( ${#archives[@]} > 0 ))
    for archive in "${archives[@]}"; do
        name=${archive##*/}
        printf '%s\n' "$name" >> "$output/closures/$closure-rpms.list"
        if [[ -e $output/rpms/$name ]]; then cmp "$archive" "$output/rpms/$name"
        else ln "$archive" "$output/rpms/$name"; fi
    done
    LC_ALL=C sort -o "$output/closures/$closure-rpms.list" "$output/closures/$closure-rpms.list"
    find "$solver" "$stored" -depth -delete
done
find "$output/download-cache" -depth -delete
rpmkeys --dbpath "$output/keydb" --import "$key"
: > "$output/rpms.tsv"
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
