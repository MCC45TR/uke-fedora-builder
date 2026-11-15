#!/usr/bin/bash
# Native ARM64 host-container packaging only. No connected device is opened.
set -Eeuo pipefail
export LC_ALL=C.UTF-8
umask 077
[[ $# == 4 && $(uname -m) == aarch64 && $(id -u) == 0 ]]
input=$(realpath "$1") geometry=$(realpath "$2") output=$(realpath -m "$3") producer=$4
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
[[ -d $input && -f $geometry && ! -e $output && $producer =~ ^[a-f0-9]{40}$ ]]
for file in boot.img userdata.img manifest.json kernel-info.json SHA256SUMS; do
    [[ -f $input/$file && ! -L $input/$file ]]
done
(cd "$input"; sha256sum -c --strict SHA256SUMS)
manifest=$input/manifest.json
jq -e --arg builder "$producer" '
 .builder_commit==$builder and .device=="uke" and .architecture=="aarch64" and
 .desktop=="kde" and .filesystem=="ext4" and .partition=="userdata" and
 .kernel_release=="7.3.3-28-unstable" and
 .kernel_source_commit=="8eb8316d3af498f4bbd25e89896d648d0ba37202" and
 .kernel_profile=="unstable" and .image_built and .rpm_transaction_validated and
 .filesystem_contents_readback and .filesystem_metadata_readback and
 .selinux_policy_contexts_verified and .independent_aosp_decoder_verified and
 (.device_private_data_included|not) and (.credentials_included|not) and
 .root_raw_bytes==8589934592' "$manifest" >/dev/null
[[ $(sha256sum "$input/boot.img" | cut -d ' ' -f1) == "$(jq -er .boot_sha256 "$manifest")" ]]
[[ $(sha256sum "$input/userdata.img" | cut -d ' ' -f1) == "$(jq -er .root_sparse_sha256 "$manifest")" ]]
raw_bytes=$(jq -er .root_raw_bytes "$manifest")
(( $(df -B1 --output=avail "$(dirname "$output")" | tail -n1) >= raw_bytes*3+4294967296 ))
mkdir -m700 "$output" "$output/files" "$output/receipts"
work=$(mktemp -d "$(dirname "$output")/ext4-test-work.XXXXXXXX")
trap 'find "$work" -depth -delete' EXIT
for tool in simg2img guestfish e2fsck zip unzip jq sha256sum; do command -v "$tool" >/dev/null; done
mkdir -p /cache /job/artifacts
# Only the signature-verified COPR codec is executed; no host compilation.
# shellcheck source=../public/repository-tools.sh
# shellcheck disable=SC1091
source "$repo/src/public/repository-tools.sh"
"$UKE_IMAGE_TOOLS/boot-image" inspect "$input/boot.img" > "$output/receipts/boot-header.json"
"$UKE_IMAGE_TOOLS/boot-image" extract "$input/boot.img" "$work/boot.Image"
simg2img "$input/userdata.img" "$work/root.raw"
[[ $(stat -c %s "$work/root.raw") == "$raw_bytes" ]]
[[ $(sha256sum "$work/root.raw" | cut -d ' ' -f1) == "$(jq -er .root_raw_sha256 "$manifest")" ]]
# The original Fedora appliance touches only this new regular-file image.
# shellcheck source=../public/guest-appliance.sh
# shellcheck disable=SC1091
source "$repo/src/public/guest-appliance.sh"
public_guest_appliance "$work/appliance"
guestfish --rw --format=raw -a "$work/root.raw" <<GUEST > "$work/before-labels"
run
mount /dev/sda /
getxattr /etc/senemos/kernel-update.conf security.selinux
getxattr /etc/senemos/userdata-update.conf security.selinux
download /usr/lib/modules/7.3.3-28-unstable/vmlinuz $work/root.Image
umount-all
GUEST
cmp "$work/boot.Image" "$work/root.Image"
printf 'automatic=1\n' > "$work/kernel-update.conf"
printf 'automatic=1\nvrr_min_hz=0\n' > "$work/userdata-update.conf"
guestfish --rw --format=raw -a "$work/root.raw" <<GUEST > "$work/after-labels"
run
mount /dev/sda /
upload $work/kernel-update.conf /etc/senemos/kernel-update.conf
upload $work/userdata-update.conf /etc/senemos/userdata-update.conf
getxattr /etc/senemos/kernel-update.conf security.selinux
getxattr /etc/senemos/userdata-update.conf security.selinux
download /etc/senemos/kernel-update.conf $work/kernel-readback.conf
download /etc/senemos/userdata-update.conf $work/userdata-readback.conf
sync
umount-all
GUEST
cmp "$work/before-labels" "$work/after-labels"
cmp "$work/kernel-update.conf" "$work/kernel-readback.conf"
cmp "$work/userdata-update.conf" "$work/userdata-readback.conf"
e2fsck -fn "$work/root.raw" > "$output/receipts/ext4-check.txt" 2>&1
"$UKE_IMAGE_TOOLS/android-sparse" encode "$work/root.raw" "$output/files/userdata.img" > "$output/receipts/sparse-encode.json"
simg2img "$output/files/userdata.img" "$work/readback.raw"
cmp "$work/root.raw" "$work/readback.raw"
cp --reflink=auto "$input/boot.img" "$output/files/boot.img"
(( $(stat -c %s "$output/files/boot.img") <= $(jq -er .partitions.boot_b "$geometry") ))
(( raw_bytes <= $(jq -er .partitions.userdata "$geometry") ))
# shellcheck source=test-fastboot-profile.sh
# shellcheck disable=SC1091
source "$repo/src/image/test-fastboot-profile.sh"
test_fastboot_requirements "$geometry" > "$output/files/android-info.txt"
test_fastboot_tasks > "$output/files/fastboot-info.txt"
cp "$manifest" "$output/receipts/input-manifest.json"
cp "$geometry" "$output/receipts/geometry.json"
jq --arg raw "$(sha256sum "$work/root.raw" | cut -d ' ' -f1)" \
   --arg sparse "$(sha256sum "$output/files/userdata.img" | cut -d ' ' -f1)" \
   --arg packager "$(git -c safe.directory="$repo" -C "$repo" rev-parse HEAD)" '
 . + {artifact_kind:"ext4-singleboot-fastboot-test",packager_commit:$packager,
 archive_name:"fedora-rawhide-linux-kde-plasma-uke-senemos-fb-test-141126.zip",
 required_current_slot:"b",destinations:["boot_b","userdata"],
 untouched_partitions:["boot_a","super","dtbo_a","dtbo_b","vendor_boot_a","vendor_boot_b","vbmeta_a","vbmeta_b"],
 root_raw_sha256:$raw,root_sparse_sha256:$sparse,automatic_kernel_activation:true,
 userdata_automatic_activation:true,vrr_min_hz:0,initial_approval:"existing native Uke boot health checks",
 post_policy_ext4_check:true,post_policy_independent_aosp_roundtrip:true,policy_selinux_labels_preserved:true,
 secure_boot_qualified:false,hardware_auto_unlock_qualified:false,hibernate_qualified:false,
 independent_rescue_boot_qualified:false,common_256_512_qualified:false,
 replaces_existing_userdata:true,physical_boot_tested:false,full_singleboot_goal_complete:false}' \
 "$manifest" > "$output/files/manifest.json"
cat > "$output/files/README.txt" <<'TEXT'
Uke EXT4 / original Fedora Plasma fresh-install test — 14 November naming date

Command: fastboot update fedora-rawhide-linux-kde-plasma-uke-senemos-fb-test-141126.zip

This test replaces userdata, including its current files and accounts. It flashes
the matching cumulative kernel only to boot_b. The measured 512-GB Uke must
already have slot B selected and its accepted matching OEM firmware. Requirements
are checked before slot selection or payload transfer. A mismatch must be
investigated; do not remove the requirements or force the update.

boot_a, super, DTBO, vendor_boot, vbmeta and early firmware are preserved.
Complete the original Plasma account setup. EXT4 grows before graphical setup.
Seamless staging is enabled; the existing native health checks approve the kernel.
SSH remains disabled by default. After account/network setup it can be enabled
with: sudo systemctl enable --now sshd

This is an installation/boot test, not the final sbfb image. Hardware automatic
unlock, OEM-to-Linux Secure Boot, hibernation, the new swap/rescue layout, matching
new kernels in both slots and 256-GB qualification remain separate open work.
No bootloader relock, key enrollment or verification-disable operation is included.
TEXT
(cd "$output/files"; sha256sum android-info.txt fastboot-info.txt boot.img userdata.img manifest.json README.txt > SHA256SUMS)
(cd "$output/files"; zip -q -1 "$output/fedora-rawhide-linux-kde-plasma-uke-senemos-fb-test-141126.zip" android-info.txt fastboot-info.txt boot.img userdata.img manifest.json README.txt SHA256SUMS)
unzip -t "$output/fedora-rawhide-linux-kde-plasma-uke-senemos-fb-test-141126.zip" > "$output/receipts/zip-check.txt"
cp "$output/files/manifest.json" "$output/manifest.json"
(cd "$output"; sha256sum fedora-rawhide-linux-kde-plasma-uke-senemos-fb-test-141126.zip > SHA256SUMS)
find "$output/files" -depth -delete
