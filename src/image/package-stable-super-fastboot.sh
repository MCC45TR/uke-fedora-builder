#!/usr/bin/env bash
# Assemble the final ZIP on GitHub from the verified desktop and rescue jobs.
set -Eeuo pipefail
export LC_ALL=C
umask 077
(( $# == 3 || ( $# >= 6 && $# <= 8 ) ))
[[ -d $1 && -d $2 && ! -e $3 ]]
release=${4:-7.4.5-senemos}
evr=${5:-7.3.5-13.fc46}
source=${6:-717f7d6c8fd26d3c066f936101b8c2011391cbf2}
channel=stable
desktop_profile=${8:-kde}
desktop_name='KDE Plasma'
fresh=false
if (( $# >= 6 )); then
    fresh=true
    channel=${7:-unstable}
    [[ $evr =~ ^7[.]3[.]5-[1-9][0-9]*[.]fc46$ && $source =~ ^[0-9a-f]{40}$ ]]
    case $channel in
        unstable) [[ $release =~ ^7[.]4[.][1-9][0-9]+-senemos$ ||
                     ( $release == "${evr%.fc46}" && $release =~ ^7[.]3[.]5-([2-9][0-9]|[1-9][0-9]{2,})$ ) ]];;
        stable) [[ $release == "${evr%.fc46}" && $release =~ ^7[.]3[.]5-([2-9][0-9]|[1-9][0-9]{2,})$ ]];;
        *) exit 1;;
    esac
fi
desktop=$(realpath "$1") components=$(realpath "$2") output=$(realpath -m "$3")
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
previous=uke-fedora-rawhide-stable-kde-bash-singleboot-7.4.5-senemos-fastboot.zip
archive=fedora-rawhide-stable-kde-bash-singleboot-7.4.5-senemos-r2-fastboot.zip
if [[ $channel == unstable ]]; then
    archive=fedora-rawhide-pad7-kde-bash-singleboot-$release-fastboot.zip
elif [[ $fresh == true ]]; then
    archive=fedora-rawhide-stable-kde-bash-singleboot-$release-fastboot.zip
fi
case $desktop_profile in
    kde) ;;
    cutefish)
        [[ $channel == unstable ]]
        desktop_name=Cutefish
        archive=fedora-rawhide-unstable-cutefish-bash-singleboot-$release-fastboot.zip
        ;;
    *) exit 1;;
esac
profile=$repo/configs/images/stable-super-fastboot
(cd "$desktop"; sha256sum -c --strict SHA256SUMS)
for dir in super-boots super-seed; do (cd "$components/$dir"; sha256sum -c --strict SHA256SUMS); done
mkdir "$output"
work=$(mktemp -d "${output%/*}/stable-super-archive.XXXXXXXX")
trap 'find "$work" -depth -delete' EXIT
if [[ $fresh == false ]]; then
    unzip -j "$desktop/$previous" manifest.json dtbo.img userdata.img -d "$work"
    cmp "$desktop/manifest.json" "$work/manifest.json"
    mv "$work/manifest.json" "$work/desktop.json"
else
    for file in userdata.img dtbo.img; do ln -s "$desktop/$file" "$work/$file"; done
    dtbo_sha=74958f51ed384f86e542fefe42c2252c4f309339df5c0850287e983db89fcfda
    jq -e --arg hash "$dtbo_sha" '
        .schema_version==1 and .dtbo_sha256==$hash and .common_dtbo and
        .reconstructed_flattened_source and (.automatic_partition_writes|not)
    ' "$desktop/dtbo-source-cohort.json" >/dev/null
    jq --arg hash "$dtbo_sha" --slurpfile dtbo "$desktop/dtbo-source-cohort.json" \
        '. + {dtbo_sha256:$hash,dtbo_source:$dtbo[0]}' "$desktop/manifest.json" > "$work/desktop.json"
fi
desktop_manifest=$work/desktop.json
boots=$components/super-boots
seed=$components/super-seed
jq -e --slurpfile rescue "$seed/rescue-source/kernel-info.json" --arg channel "$channel" --argjson fresh "$fresh" \
    --arg release "$release" --arg evr "$evr" --arg source "$source" --arg builder "${GITHUB_SHA:-}" --arg desktop "$desktop_profile" '
    .channel==$channel and .fedora_release=="rawhide" and .architecture=="aarch64" and
    .device=="uke" and .desktop==$desktop and .default_shell=="bash" and .mode=="singleboot" and
    .partition=="userdata" and .filesystem=="ext4" and .root_raw_bytes==8589934592 and
    (if $fresh then ($builder|test("^[0-9a-f]{40}$")) and .builder_commit==$builder
     else .builder_commit=="bc158a877d92d050fd3d7d6a08247df8e112b253" end) and
    .cohort_validation.final_filesystem_hashes_verified and .independent_aosp_decoder_verified and
    .selinux_policy_contexts_verified and (.credentials_included|not) and (.device_private_data_included|not) and
    (if $desktop=="cutefish" then .account_setup=="uke-cutefish-firstboot" and
      .firstboot_backend_input_tests and .systemd_units_verified and .root_password_locked and
      .autologin_enabled==false else true end) and
    .kernel_release==$release and (.rpm_version_release+.rpm_dist)==$evr and .kernel_source_commit==$source and
    .kernel_profile=="normal" and .kernel_rpm_signature=="verified COPR signature" and
    ($rescue[0] as $k | .kernel_release==$k.kernel_release and .kernel_source_commit==$k.kernel_source_commit and
        .payload_sha256==$k.payload_sha256 and .rpm_version_release==$k.rpm_version_release and .rpm_dist==$k.rpm_dist and
        .kernel_repository==$k.kernel_repository and .kernel_key_fingerprint==$k.kernel_key_fingerprint and .kernel_rpm_signature==$k.kernel_rpm_signature)
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
bash "$repo/src/image/compose-super-empty.sh" "$seed/super-layout.json" "$work/super_empty.img"
# Check the metadata-only entry against each independent readback of super.img.
lp_projection='{partitions:(.partitions|sort_by(.name)),groups:(.groups|sort_by(.name)),block_devices,super_device}'
lpdump --json "$work/super_empty.img" | jq -Sc "$lp_projection" > "$work/empty-layout.json"
for slot in 0 1 2; do
    jq -Sc "$lp_projection" "$seed/lp-slot-$slot.json" | cmp - "$work/empty-layout.json"
done
hash() { sha256sum "$1" | cut -d ' ' -f1; }
[[ $(hash "$work/dtbo.img") == "$(jq -er .dtbo_sha256 "$desktop_manifest")" ]]
[[ $(hash "$work/userdata.img") == "$(jq -er .root_sparse_sha256 "$desktop_manifest")" ]]
[[ $(hash "$work/boot.img") == "$(jq -er .userdata_super_sha256 "$boots/super-profiles.json")" ]]
[[ $(hash "$work/rescue-boot.img") == "$(jq -er .rescue_sha256 "$boots/super-profiles.json")" ]]
[[ $(hash "$work/super.img") == "$(jq -er .super_sparse_sha256 "$seed/super-composition.json")" ]]
[[ $(stat -Lc %s "$work/boot.img") == 100663296 && $(stat -Lc %s "$work/rescue-boot.img") == 100663296 ]]
(( $(stat -Lc %s "$work/dtbo.img") <= 25165824 ))
# Verify that the reused desktop root has the native swap manager and that its
# kernel matches the signed wrappers rather than trusting its filename.
simg2img "$work/userdata.img" "$work/userdata.raw"
[[ $(stat -c %s "$work/userdata.raw") == 8589934592 ]]
[[ $(hash "$work/userdata.raw") == "$(jq -er .root_raw_sha256 "$desktop_manifest")" ]]
debugfs -R "dump /usr/lib/modules/$release/vmlinuz $work/vmlinuz" "$work/userdata.raw"
[[ $(hash "$work/vmlinuz") == "$(jq -er .raw_image_sha256 "$boots/super-profiles.json")" ]]
if [[ $fresh == true ]]; then
    grep -aFq 'Uke ABL DT: using firmware ramoops layout' "$work/vmlinuz"
fi
debugfs -R 'cat /etc/systemd/system/uke-swap-ready.service' "$work/userdata.raw" |
    grep -Fx 'ExecStart=/usr/bin/uke-control swap apply'
debugfs -R 'stat /usr/libexec/uke-control/super-swap/prepare.sh' "$work/userdata.raw" |
    grep -Eq 'Type: regular[[:space:]]+Mode:[[:space:]]+0755'
debugfs -R 'cat /etc/fstab' "$work/userdata.raw" |
    grep -Fx 'PARTLABEL=userdata / ext4 defaults,noatime,x-systemd.growfs 0 0'
debugfs -R 'cat /etc/systemd/system/uke-root-capacity.service' "$work/userdata.raw" |
    grep -Fx 'Requires=systemd-growfs-root.service'
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
jq --slurpfile images "$work/images.jsonl" --slurpfile super "$seed/super-composition.json" \
    --arg empty_sha256 "$(hash "$work/super_empty.img")" --arg channel "$channel" --argjson fresh "$fresh" '
    . + {schema_version:1,artifact_kind:(if $channel=="stable" then "uke-stable-super-fastboot" else "uke-pad7-super-fastboot" end),images:($images|from_entries),
         boot_sha256:($images|from_entries|.["boot.img"].sha256),boot_profile:"userdata-super",
         super_layout:$super[0].layout,
         targets:["super","userdata","dtbo_active","boot_active"],required_current_slot:null,
         super_empty_sha256:$empty_sha256,super_empty_role:"Metadata only, parsed by fastboot and never a flash task",
         installation:"fastboot update",installation_script:false,
         capacity_policy:"Grow to the measured physical userdata and super partitions during first boot",
         replaces_existing_userdata:true,rescue_boot_hardware_tested:false,
         xiaomi_pad_7_128gb_hardware_tested:false,xiaomi_pad_7_256gb_hardware_tested:false} +
    (if $fresh then {pad7_ramoops_fallback_verified:true} else {previous_desktop_run:44546857648} end)
' "$desktop_manifest" > "$work/manifest.json"
cp "$profile/"{android-info,fastboot-info}.txt "$work/"
cat > "$work/README.txt" <<TEXT
Fedora Rawhide / $desktop_name / Bash / EXT4 singleboot
Kernel $release (COPR ${channel} RPM $evr)

This installation replaces Android super and userdata. Back up all data and
keep the matching Xiaomi stock firmware package before installing. An unlocked
Uke with working, compatible vendor_boot and bootloader firmware is required.

Use Android SDK Platform-Tools 37.0.1 and bootloader fastboot on the stock
Xiaomi Pad 7 or POCO Pad X1 partition layout. This archive needs at least
4 GiB in super and 8 GiB in userdata. Install with:

  fastboot update ./$archive

An optional .sig notice or a sparse AVB footer warning may appear in stock
Fastboot. Check the Sending, Writing and Rebooting results for installation
status. super_empty.img contains only the matching liblp layout for Fastboot
to read. super.img contains the payload sent to the physical super partition.

The archive writes super, userdata, and the active slot's DTBO and boot.
It preserves partition sizes, the other slot's boot and DTBO, vendor_boot,
vbmeta, and the device firmware.

On first boot Fedora grows EXT4 to the detected userdata size. The 4 GiB
super seed grows in place to the detected super size, allocating about 80%
to linux_swap and 20% to FEDORA_RESCUE. Xiaomi Pad 7 physical boot
still needs testing.
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
    sha256sum android-info.txt fastboot-info.txt manifest.json README.txt super_empty.img "${files[@]}" > SHA256SUMS
    zip -q -1 "$output/$archive" android-info.txt fastboot-info.txt manifest.json README.txt SHA256SUMS super_empty.img "${files[@]}"
)
unzip -tq "$output/$archive"
for file in android-info.txt fastboot-info.txt; do
    unzip -p "$output/$archive" "$file" | cmp - "$profile/$file"
done
printf '%s\n' android-info.txt fastboot-info.txt manifest.json README.txt SHA256SUMS super_empty.img "${files[@]}" |
    LC_ALL=C sort > "$work/expected-entries"
unzip -Z -1 "$output/$archive" | LC_ALL=C sort | cmp - "$work/expected-entries"
cp "$work/"{manifest.json,README.txt} "$output/"
(cd "$output"; sha256sum "$archive" README.txt manifest.json > SHA256SUMS)
