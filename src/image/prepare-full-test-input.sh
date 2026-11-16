#!/usr/bin/bash
# Native assembly worker only. Mutates two configuration files in a new image.
set -Eeuo pipefail
export LC_ALL=C.UTF-8
umask 077
[[ $# == 3 && $(id -u) == 0 && $(uname -m) == aarch64 ]]
input=$(realpath "$1");output=$(realpath -m "$2");producer=$3
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
[[ -d $input && ! -e $output && ! -L $output && $producer =~ ^[a-f0-9]{40}$ ]]
for file in boot.img userdata.img manifest.json SHA256SUMS;do [[ -f $input/$file && ! -L $input/$file ]];done
(cd "$input";sha256sum -c --strict SHA256SUMS)
jq -e --arg producer "$producer" '
 .builder_commit==$producer and .device=="uke" and .architecture=="aarch64" and
 .desktop=="kde" and .mode=="singleboot" and .partition=="userdata" and .filesystem=="ext4" and
 .kernel_profile=="unstable" and .image_built and .rpm_transaction_validated and
 .filesystem_contents_readback and .filesystem_metadata_readback and .selinux_policy_contexts_verified and
 .independent_aosp_decoder_verified and .temporary_setup_cdc and
 (.credentials_included|not) and (.device_private_data_included|not) and
 .root_raw_bytes==8589934592 and
 (.kernel_release|test("^[0-9]+[.][0-9]+[.][0-9]+-[1-9][0-9]*-unstable$")) and
 (.kernel_source_commit|test("^[a-f0-9]{40}$"))' "$input/manifest.json" > /dev/null
release=$(jq -er .kernel_release "$input/manifest.json")
source_commit=$(jq -er .kernel_source_commit "$input/manifest.json")
bytes=$(jq -er .root_raw_bytes "$input/manifest.json")
(( $(df -B1 --output=avail "${output%/*}" | tail -n1) >= bytes*3+4294967296 ))
mkdir -m700 "$output" "$output/receipts"
work=$(mktemp -d "${output%/*}/full-test-input.XXXXXXXX")
trap 'find "$work" -depth -delete' EXIT
mkdir -p /cache /job/artifacts
# shellcheck source=../public/repository-tools.sh
# shellcheck disable=SC1091
source "$repo/src/public/repository-tools.sh"
[[ $(sha256sum "$input/boot.img" | cut -d' ' -f1) == "$(jq -er .boot_sha256 "$input/manifest.json")" ]]
[[ $(sha256sum "$input/userdata.img" | cut -d' ' -f1) == "$(jq -er .root_sparse_sha256 "$input/manifest.json")" ]]
"$UKE_IMAGE_TOOLS/boot-image" extract "$input/boot.img" "$work/boot.Image"
simg2img "$input/userdata.img" "$work/root.raw"
[[ $(stat -c %s "$work/root.raw") == "$bytes" &&
   $(sha256sum "$work/root.raw" | cut -d' ' -f1) == "$(jq -er .root_raw_sha256 "$input/manifest.json")" ]]
cat > "$work/check.sh" <<'CHECK'
#!/usr/bin/bash
set -Eeuo pipefail
export LC_ALL=C
[[ $# == 2 && $(id -u) == 0 && ! -e /etc/plasma-setup-done && ! -L /etc/plasma-setup-done ]]
[[ ! -e /var/lib/uke-control/cdc-on ]]
awk -F: '$3>=1000&&$3<65534{exit 1}' /etc/passwd
awk -F: '$1=="root"&&$2~/^[!*]/{n++} END{exit n!=1}' /etc/shadow
marker=/etc/uke-control/first-setup-cdc
[[ -f $marker && ! -L $marker && $(stat -c '%u:%a:%h' "$marker") == 0:600:1 ]]
printf 'v1\n' | cmp - "$marker"
provides=$(rpm -q uke-control --qf '[%{PROVIDENAME}\t%{PROVIDEFLAGS:depflags}\t%{PROVIDEVERSION}\n]')
for capability in setup-cdc-v1 setup-cdc-reboot-v1 super-root-boot-v1 logical-swap-v1;do
 grep -Fxq $'uke-control('"$capability"$')\t=\t1' <<< "$provides"
done
[[ -x /usr/bin/systemctl && -x /usr/libexec/uke-control/super-swap/prepare.sh ]]
[[ $(cat "/usr/share/senemos/uke/$1/source-commit") == "$2" ]]
for unit in uke-control-setup-cdc.service uke-control-setup-cdc-finish.path;do
 [[ $(systemctl is-enabled "$unit") == enabled ]]
done
rpm -q uke-control uke-control-tui --qf '%{NEVRA}\n' > /var/lib/uke-image-assembly/control-nevras.txt
CHECK
printf 'automatic=1\n' > "$work/kernel-update.conf"
printf 'automatic=1\nvrr_min_hz=0\n' > "$work/userdata-update.conf"
# shellcheck source=../public/guest-appliance.sh
# shellcheck disable=SC1091
source "$repo/src/public/guest-appliance.sh"
public_guest_appliance "$work/appliance"
cat > "$work/write.commands" <<GUEST
set-smp 2
set-memsize 2048
set-network false
run
mount /dev/sda /
getxattr /etc/senemos/kernel-update.conf security.selinux
getxattr /etc/senemos/userdata-update.conf security.selinux
mkdir /var/lib/uke-image-assembly
chmod 0700 /var/lib/uke-image-assembly
upload $work/check.sh /var/lib/uke-image-assembly/check.sh
command-out "/usr/bin/bash /var/lib/uke-image-assembly/check.sh $release $source_commit" -
download /var/lib/uke-image-assembly/control-nevras.txt $output/receipts/control-nevras.txt
rm /var/lib/uke-image-assembly/control-nevras.txt
rm /var/lib/uke-image-assembly/check.sh
rmdir /var/lib/uke-image-assembly
download /usr/lib/modules/$release/vmlinuz $work/root.Image
upload $work/kernel-update.conf /etc/senemos/kernel-update.conf
upload $work/userdata-update.conf /etc/senemos/userdata-update.conf
sync
umount-all
GUEST
timeout --kill-after=10s 300s guestfish --rw --format=raw -a "$work/root.raw" -f "$work/write.commands" > "$output/receipts/write-log.txt" 2>&1
cmp "$work/boot.Image" "$work/root.Image"
cat > "$work/read.commands" <<GUEST
set-smp 1
set-memsize 1024
set-network false
run
mount-options ro,noload /dev/sda /
getxattr /etc/senemos/kernel-update.conf security.selinux
getxattr /etc/senemos/userdata-update.conf security.selinux
download /etc/senemos/kernel-update.conf $work/kernel-readback.conf
download /etc/senemos/userdata-update.conf $work/userdata-readback.conf
umount-all
GUEST
sha256sum "$work/root.raw" > "$work/final-raw.sha256"
timeout --kill-after=10s 180s guestfish --ro --format=raw -a "$work/root.raw" -f "$work/read.commands" > "$output/receipts/read-log.txt" 2>&1
sha256sum -c --strict "$work/final-raw.sha256"
cmp "$output/receipts/write-log.txt" "$output/receipts/read-log.txt"
cmp "$work/kernel-update.conf" "$work/kernel-readback.conf"
cmp "$work/userdata-update.conf" "$work/userdata-readback.conf"
e2fsck -fn "$work/root.raw" > "$output/receipts/ext4-check.txt" 2>&1
"$UKE_IMAGE_TOOLS/android-sparse" encode "$work/root.raw" "$output/userdata.img"
"$UKE_IMAGE_TOOLS/android-sparse" decode "$output/userdata.img" "$work/readback.raw"
cmp "$work/root.raw" "$work/readback.raw"
unlink "$work/readback.raw"
simg2img "$output/userdata.img" "$work/readback.raw"
cmp "$work/root.raw" "$work/readback.raw"
cp --reflink=auto "$input/boot.img" "$output/boot.img"
cp "$input/manifest.json" "$output/receipts/base-manifest.json"
jq --arg raw "$(cut -d' ' -f1 "$work/final-raw.sha256")" \
 --arg kernel_hash "$(sha256sum "$work/root.Image" | cut -d' ' -f1)" \
 --arg sparse "$(sha256sum "$output/userdata.img" | cut -d' ' -f1)" \
 --arg preparer "$(git -c safe.directory="$repo" -C "$repo" rev-parse HEAD)" '
 .+{artifact_kind:"full-singleboot-desktop-input",test_preparer_commit:$preparer,
 root_raw_sha256:$raw,root_sparse_sha256:$sparse,root_kernel_image_sha256:$kernel_hash,automatic_kernel_activation:true,
 userdata_automatic_activation:true,vrr_min_hz:0,control_super_and_swap_capabilities_verified:true,
 setup_cdc_reboot_capability_verified:true,temporary_assembly_files_removed:true,
 post_policy_independent_readback:true,policy_selinux_labels_preserved:true,
 post_policy_ext4_check:true,post_policy_independent_aosp_roundtrip:true,
 physical_boot_tested:false,secure_boot_qualified:false,hardware_auto_unlock_qualified:false,
 encrypted_swap_qualified:false,hibernate_qualified:false,independent_rescue_boot_qualified:false}' \
 "$input/manifest.json" > "$output/manifest.json"
(cd "$output";sha256sum boot.img userdata.img manifest.json > SHA256SUMS)
echo 'Full-test desktop input: native Control interfaces, fresh setup, matching Image, automatic policy, independent readback and sparse roundtrip verified; not a boot or security qualification.'
