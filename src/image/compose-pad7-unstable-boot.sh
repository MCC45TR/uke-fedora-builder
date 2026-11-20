#!/usr/bin/env bash
# Host-only assembly from an exact signed AArch64 Unstable COPR build.
set -Eeuo pipefail
export LC_ALL=C
[[ $# == 2 && $1 =~ ^[1-9][0-9]{0,9}$ && -d $2 && $(uname -m) == aarch64 ]]
build_id=$1
output=$(realpath -e "$2")
here=$(cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
curl_options=(--proto '=https' --tlsv1.2 -fsSL --retry 2 --max-time 90)
family=senemos-uke-linux-kernel-mainline
project=https://download.copr.fedorainfracloud.org/results/mcc45tr/uke-linux-unstable
build=$(curl "${curl_options[@]}" --max-filesize 32768 "https://copr.fedorainfracloud.org/api_3/build/$build_id")
release=$(jq -er --arg family "$family" --argjson build "$build_id" '
    select(.id==$build and .state=="succeeded" and .ownername=="mcc45tr" and
        .projectname=="uke-linux-unstable" and .source_package.name==$family and
        (.chroots | index("fedora-rawhide-aarch64"))) |
    .source_package.version | select(test("^7[.]3[.]5-[1-9][0-9]*$"))
' <<< "$build")
archive="$work/$family-core-$release.fc46.aarch64.rpm"
curl "${curl_options[@]}" --max-filesize 409600 -o "$work/copr.asc" "$project/pubkey.gpg"
expected=$(jq -er '.channels.unstable.fingerprint' "$here/../../configs/public-build.json")
[[ $(gpg --show-keys --with-colons "$work/copr.asc" | awk -F: '$1=="fpr" && !seen++ {print $10}') == "$expected" ]]
mkdir "$work/keydb" "$work/payload" "$work/boot"
rpmkeys --dbpath "$work/keydb" --import "$work/copr.asc"
curl "${curl_options[@]}" --max-filesize 268435456 -o "$archive" \
    "$project/fedora-rawhide-aarch64/$build_id-$family/${archive##*/}"
rpmkeys --dbpath "$work/keydb" --checksig "$archive" | grep -F 'signatures OK'
[[ $(rpm -qp --qf '%{NEVRA}' "$archive") == "$family-core-$release.fc46.aarch64" ]]
bundle="usr/lib/senemos/kernel-updates/$release"
kernel="usr/lib/modules/$release/vmlinuz"
rpm2cpio "$archive" |
    (cd "$work/payload"; cpio -idm --quiet --no-absolute-filenames "./$bundle/boot-image" "./$bundle/super-profiles.json" "./$kernel")
grep -aFq 'Uke ABL DT: using firmware ramoops layout' "$work/payload/$kernel"
jq -n --arg release "$release" '{kernel_release:$release}' > "$work/kernel-info.json"
bash "$here/compose-signed-super-boots.sh" "$work/payload/$bundle" "$work/payload/$kernel" \
    "$work/kernel-info.json" "$work/boot"
bash "$here/compose-pad7-temporary-boot.sh" "$work/boot/boot.img" "$output/boot.img" "$work/boot/super-profiles.json"
printf '%s\n' "$release" > "$output/kernel-release"
