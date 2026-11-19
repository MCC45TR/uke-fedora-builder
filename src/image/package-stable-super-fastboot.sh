#!/usr/bin/env bash
# Assemble the final ZIP on GitHub from the verified KDE root and rescue jobs.
set -Eeuo pipefail
export LC_ALL=C
umask 077
[[ $# == 3 && -d $1 && -d $2 && ! -e $3 ]]
desktop=$(realpath "$1") components=$(realpath "$2") output=$(realpath -m "$3")
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
previous=uke-fedora-rawhide-stable-kde-bash-singleboot-7.4.5-senemos-fastboot.zip
archive=uke-fedora-rawhide-stable-kde-bash-singleboot-7.4.5-senemos-super-fastboot.zip
(cd "$desktop"; sha256sum -c --strict SHA256SUMS)
for dir in super-boots super-seed; do (cd "$components/$dir"; sha256sum -c --strict SHA256SUMS); done
mkdir "$output"
work=$(mktemp -d "${output%/*}/stable-super-archive.XXXXXXXX")
trap 'find "$work" -depth -delete' EXIT
unzip -j "$desktop/$previous" manifest.json dtbo.img userdata.img -d "$work"
cmp "$desktop/manifest.json" "$work/manifest.json"
mv "$work/manifest.json" "$work/desktop.json"
desktop_manifest=$work/desktop.json
boots=$components/super-boots
seed=$components/super-seed
jq -e --slurpfile rescue "$seed/rescue-source/kernel-info.json" '
    .channel=="stable" and .fedora_release=="rawhide" and .architecture=="aarch64" and
    .device=="uke" and .desktop=="kde" and .default_shell=="bash" and .mode=="singleboot" and
    .partition=="userdata" and .filesystem=="ext4" and .root_raw_bytes==8589934592 and
    .builder_commit=="bc158a877d92d050fd3d7d6a08247df8e112b253" and
    .cohort_validation.final_filesystem_hashes_verified and .independent_aosp_decoder_verified and
    .selinux_policy_contexts_verified and (.credentials_included|not) and (.device_private_data_included|not) and
    .kernel_release=="7.4.5-senemos" and .rpm_version_release=="7.3.5-13" and
    ($rescue[0] as $k | .kernel_release==$k.kernel_release and .kernel_source_commit==$k.kernel_source_commit and
        .payload_sha256==$k.payload_sha256 and .rpm_version_release==$k.rpm_version_release and .rpm_dist==$k.rpm_dist and
        .kernel_key_fingerprint==$k.kernel_key_fingerprint and .kernel_rpm_signature==$k.kernel_rpm_signature)
' "$desktop_manifest" >/dev/null
jq -e '
    .liblp_three_slot_readback and .independent_aosp_decode and .both_logical_payloads_byte_matched and
    .layout.super_bytes==4294967296 and .layout.phase=="seed" and (.layout.partition_table_changes|not) and
    [.layout.partitions[] | [.name,.label,.percentage]]==[["system_a","linux_swap",80],["system_b","FEDORA_RESCUE",20]]
' "$seed/super-composition.json" >/dev/null
jq -e --slurpfile super "$seed/super-composition.json" '
    .seed_super_sparse_sha256==$super[0].super_sparse_sha256 and .rescue_raw_sha256==$super[0].rescue_raw_sha256 and
    .source_scripts_verified and .unit_files_verified and .locked_root_verified and .human_account_absent and
    .activation_links_verified and .inspection_read_only
' "$seed/rescue-console-readback.json" >/dev/null
for file in boot.img rescue-boot.img; do ln -s "$boots/$file" "$work/$file"; done
ln -s "$seed/super.img" "$work/super.img"
hash() { sha256sum "$1" | cut -d ' ' -f1; }
[[ $(hash "$work/dtbo.img") == "$(jq -er .dtbo_sha256 "$desktop_manifest")" ]]
[[ $(hash "$work/userdata.img") == "$(jq -er .root_sparse_sha256 "$desktop_manifest")" ]]
[[ $(hash "$work/boot.img") == "$(jq -er .userdata_super_sha256 "$boots/super-profiles.json")" ]]
[[ $(hash "$work/rescue-boot.img") == "$(jq -er .rescue_sha256 "$boots/super-profiles.json")" ]]
[[ $(hash "$work/super.img") == "$(jq -er .super_sparse_sha256 "$seed/super-composition.json")" ]]
# Verify that the reused desktop root has the native swap manager and that its
# kernel matches the signed wrappers rather than trusting its filename.
simg2img "$work/userdata.img" "$work/userdata.raw"
[[ $(stat -c %s "$work/userdata.raw") == 8589934592 ]]
[[ $(hash "$work/userdata.raw") == "$(jq -er .root_raw_sha256 "$desktop_manifest")" ]]
debugfs -R "dump /usr/lib/modules/7.4.5-senemos/vmlinuz $work/vmlinuz" "$work/userdata.raw"
[[ $(hash "$work/vmlinuz") == "$(jq -er .raw_image_sha256 "$boots/super-profiles.json")" ]]
debugfs -R 'cat /etc/systemd/system/uke-swap-ready.service' "$work/userdata.raw" |
    grep -Fx 'ExecStart=/usr/bin/uke-control swap apply'
debugfs -R 'stat /usr/libexec/uke-control/super-swap/prepare.sh' "$work/userdata.raw" |
    grep -Eq 'Type: regular[[:space:]]+Mode:[[:space:]]+0755'
debugfs -R 'cat /etc/senemos/kernel-update.conf' "$work/userdata.raw" | grep -Fx 'automatic=1'
debugfs -R 'cat /etc/senemos/userdata-update.conf' "$work/userdata.raw" | grep -Fx 'automatic=1'
unlink "$work/userdata.raw"
unlink "$work/vmlinuz"
files=(boot.img dtbo.img rescue-boot.img super.img userdata.img)
for file in "${files[@]}"; do
    stored=$(stat -Lc %s "$work/$file")
    case $file in
        super.img) expanded=4294967296;;
        userdata.img) expanded=8589934592;;
        *) expanded=$stored;;
    esac
    jq -nc --arg file "$file" --arg hash "$(hash "$work/$file")" --argjson stored "$stored" --argjson expanded "$expanded" '
        {key:$file,value:{sha256:$hash,stored_bytes:$stored,expanded_bytes:$expanded}}
    '
done > "$work/images.jsonl"
jq --slurpfile images "$work/images.jsonl" --slurpfile super "$seed/super-composition.json" '
    . + {schema_version:1,artifact_kind:"uke-stable-super-fastboot",images:($images|from_entries),
         boot_sha256:($images|from_entries|.["boot.img"].sha256),boot_profile:"userdata-super",
         previous_desktop_run:44546857648,super_layout:$super[0].layout,
         targets:["super","userdata","dtbo_active","boot_active"],required_current_slot:null,
         product_capacity:"Measured from the attached Uke by the installer",
         replaces_existing_userdata:true,rescue_boot_hardware_tested:false,
         xiaomi_pad_7_256gb_hardware_tested:false}
' "$desktop_manifest" > "$work/manifest.json"
printf '%s\n' 'require product=uke-use-measured-host-installer' > "$work/android-info.txt"
printf '%s\n' 'version 1' 'flash super super.img' 'flash userdata userdata.img' 'flash dtbo dtbo.img' 'flash boot boot.img' > "$work/fastboot-info.txt"
cp "$repo/scripts/install-stable-super-fastboot.sh" "$work/"
cat > "$work/README.txt" <<TEXT
Fedora Rawhide Stable / KDE Plasma / Bash / EXT4 singleboot
Kernel 7.4.5-senemos (Stable COPR RPM 7.3.5-13.fc46)

This installation replaces Android super and userdata. Back up all data and
keep the matching Xiaomi stock firmware package before installing. An unlocked
Uke with working, compatible vendor_boot and bootloader firmware is required.

The host installer checks the connected device's active slot and measured
partition sizes, including userdata and super. This supports the 256 GB and
512 GB capacity variants when the measured Uke geometry passes. The workflow
has not boot-tested this image on a physical Xiaomi Pad 7 256 GB.

From a Linux host with fastboot, jq and unzip installed:
  sha256sum -c SHA256SUMS
  bash install-stable-super-fastboot.sh --check $archive
  bash install-stable-super-fastboot.sh --install $archive

Use the host installer. Direct fastboot update is blocked to keep the
capacity check effective with stock fastboot clients. The installer writes
super, userdata, DTBO and boot for the active slot and then reboots. It
preserves GPT, vbmeta, vendor_boot, the other boot slot and device firmware.
For installation, set TMPDIR to a disk with enough room for the sparse images
if the default temporary filesystem is too small.

On first boot the 4 GiB super seed expands in place against measured
capacity, allocating approximately 80% to linux_swap and 20% to FEDORA_RESCUE.
The live rescue root is in super. Extract rescue-boot.img separately for a
temporary boot on a bootloader that supports fastboot boot, after ordinary
Fedora setup has created the administrator.

  unzip -j $archive rescue-boot.img
  fastboot boot rescue-boot.img

Live rescue USB login uses the administrator password and first mounts
userdata read-only. Temporary rescue boot and login still need hardware testing.
TEXT
(
    cd "$work"
    sha256sum android-info.txt fastboot-info.txt manifest.json README.txt install-stable-super-fastboot.sh "${files[@]}" > SHA256SUMS
    zip -q -1 "$output/$archive" android-info.txt fastboot-info.txt manifest.json README.txt install-stable-super-fastboot.sh SHA256SUMS "${files[@]}"
)
unzip -tq "$output/$archive"
cp "$work/"{manifest.json,README.txt,install-stable-super-fastboot.sh} "$output/"
(cd "$output"; sha256sum "$archive" README.txt manifest.json install-stable-super-fastboot.sh > SHA256SUMS)
