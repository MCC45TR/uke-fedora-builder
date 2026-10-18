#!/usr/bin/env bash
# Host-only data bundle, intentionally without an Android installer entrypoint.
set -Eeuo pipefail
[[ $# == 2 && $2 =~ ^[0-9a-f]{40}$ ]]
job=$(realpath "$1") builder_commit=$2
[[ -f $job/f2fs-image.complete && -f $job/f2fs-xattr-audit.complete && -f $job/root-audit.complete && ! -e $job/delivery ]]
root=$job/root
release=7.2.10-31
bundle=$root/usr/lib/senemos/kernel-updates/$release
destination=$job/delivery
mkdir -m755 "$destination" "$destination/sources" "$destination/checks"
[[ -d $job/deferred-rpms ]]
cp -a "$job/deferred-rpms" "$destination/"
cp --reflink=auto "$job/image/userdata.f2fs.img.zst" "$destination/userdata.f2fs.img.zst"
cp "$bundle/userdata.img" "$destination/boot-userdata.img"
cp "$job/installed-rpms.tsv" "$destination/checks/installed-rpms.tsv"
cp "$job/audit/installed-origins.tsv" "$destination/checks/installed-origins.tsv"
cp "$job/language-audit.json" "$destination/checks/language-audit.json"
cp "$job/audit/original-fedora-rpms.tsv" "$destination/checks/original-fedora-rpms.tsv"
cp "$job/audit/namespace-policy.json" "$destination/checks/namespace-policy.json"
cp "$job/image/xattrs.expected.tsv" "$destination/checks/file-capabilities-acls.tsv"
cp "$job/audit/kernel/userdata-header.json" "$destination/checks/boot-header.json"
cp "$bundle/manifest" "$destination/checks/kernel-manifest"
for archive_input in "$job"/inputs/candidate-rpms/fedora-rawhide-aarch64/*.aarch64.rpm \
    "$job"/inputs/device-rpms/*.aarch64.rpm "$job"/inputs/device-rpms/*.noarch.rpm; do
    name=${archive_input##*/} phase=selected source='mcc45tr/uke-linux main snapshot'
    case "$name" in
        uke-cdc-debug-*|uke-esp32-cdc-*|uke-boot-recovery-*) continue;;
        senemos-uke-linux-kernel-mainline*) source='mcc45tr/uke-linux:custom:userdata-rc1 build 11167317';;
        uke-boot-integration-*|uke-installation-profile-*|uke-kernel-update-*|uke-wifi-factory-*) source='mcc45tr/uke-linux:custom:userdata-rc1 build 11167080';;
        uke-ssc-fileservice-*|uke-adaptive-display-*) phase=deferred-until-device-local-firmware;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$name" "$phase" "$source" \
        "$(sha256sum "$archive_input" | cut -d ' ' -f1)" >> "$destination/checks/device-inputs.tsv"
done
[[ $(wc -l < "$destination/checks/device-inputs.tsv") == 22 ]]
repo=$(cd "$(dirname "$0")/../.." && pwd)
cp "$repo/src/image/check-userdata-payload.cpp" "$destination/sources/"
cp "$repo/LICENSE" "$destination/sources/LICENSE"
git -C "$repo" archive --format=tar "$builder_commit" | gzip -n -9 > "$destination/sources/builder-source.tar.gz"
raw_hash=$(cut -d ' ' -f1 "$job/image/userdata.f2fs.img.sha256")
root_hash=$(sha256sum "$destination/userdata.f2fs.img.zst" | cut -d ' ' -f1)
boot_hash=$(sha256sum "$destination/boot-userdata.img" | cut -d ' ' -f1)
root_size=$(stat -c %s "$destination/userdata.f2fs.img.zst")
"$job/tools/check-userdata-payload" "$destination/userdata.f2fs.img.zst" 15032385536 "$raw_hash" \
    "$destination/boot-userdata.img" "$boot_hash" > "$destination/checks/payload-readback.json"
jq -n --arg full "$(sha256sum "$job/logs/f2fs-full-compose.log" | cut -d ' ' -f1)" \
    --argjson packages "$(wc -l < "$job/audit/installed-origins.tsv")" \
    --argjson caps "$(grep -c 'security.capability=' "$job/image/xattrs.expected.tsv")" \
    --argjson acls "$(grep -c 'system.posix_acl_' "$job/image/xattrs.expected.tsv" || true)" \
    '{date:"2026-10-18",evidence_classes:["source","package","host","composition-vm"],payload_packages:$packages,
      rpm_public_key_entries:2,original_fedora_archives_verified:961,device_input_rpms_verified:22,
      original_fedora_python_byte_check:true,privacy_check:true,account_and_service_check:true,dependency_check:true,
      common_kernel_image_readback:true,all_module_digests:true,embedded_initramfs_audit:true,
      full_f2fs_contents_owner_mode_readback:true,selinux_label_readback:true,fsck_f2fs:true,
      capability_records:$caps,posix_acl_records:$acls,explicit_xattr_readback:true,xattr_mismatch_refused:true,
      composition_vm_log_sha256:$full,physical_boot:false,recovery_installation:false,hardware_acceptance:false}' \
    > "$destination/checks/validation.json"
jq -n --arg builder "$builder_commit" --arg raw "$raw_hash" --arg compressed "$root_hash" \
    --arg boot "$boot_hash" --argjson size "$root_size" \
    '{schema_version:1,created:"2026-10-18",artifact_kind:"prepared-data-payload",device:"uke",architecture:"aarch64",
      distribution:"Fedora Rawhide",desktop:"original Fedora Plasma",root_partition:"userdata",root_filesystem:"f2fs",root_label:"UKE_LINUX",
      root:{file:"userdata.f2fs.img.zst",raw_bytes:15032385536,raw_sha256:$raw,compressed_bytes:$size,compressed_sha256:$compressed,zstd_max_window_bytes:33554432},
      boot:{file:"boot-userdata.img",bytes:100663296,sha256:$boot,kernel_release:"7.2.10-31",selector:"senemos.root=userdata"},
      sources:{builder_commit:$builder,kernel_commit:"87eadc3273f48a219c872f3b6096ec5987a5bcc0",installation_profile_commit:"2854221934ad5e06cee157019e45ad76a3f379cc",kernel_copr_build:11167317,installation_profile_copr_build:11167080},
      copr:{installed_project:"mcc45tr/uke-linux",fingerprint:"30DFB81A724CE0762F9DF77F844A293E5068FAFE",candidate_project:"mcc45tr/uke-linux:custom:userdata-rc1",main_channel_promoted:false},
      secure_boot:false,root_locked:true,precreated_human_account:false,all_packaged_languages:true,
      recovery_installable:false,installer_entrypoint_included:false,oem_firmware_included:false,public_regulatory_database_included:true,device_private_data_included:false,
      firmware_provisioning_qualified:false,automatic_kernel_activation:false,physical_boot_tested:false,hardware_tested:false,
      deferred_until_firmware_provisioning:["uke-ssc-fileservice","uke-adaptive-display"],
      continuation:"Complete the reviewed OrangeFox installation and device-local provisioning path before activation; then conduct physical acceptance."}' \
    > "$destination/payload.json"
cp "$repo/docs/USERDATA-DELIVERY.md" "$destination/README.md"
cp "$repo/docs/USERDATA-PREPARATION.md" "$destination/sources/PREPARATION.md"
(cd "$destination"; find . -type f ! -name SHA256SUMS ! -name '*.zip' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$job/delivery.SHA256SUMS")
mv "$job/delivery.SHA256SUMS" "$destination/SHA256SUMS"
archive=$job/uke-fedora-rawhide-plasma-userdata-20261018-prepared.payload.zip
[[ ! -e $archive ]]
(cd "$destination"; zip -q -0 "$archive" userdata.f2fs.img.zst; zip -q -6 -r "$archive" boot-userdata.img payload.json README.md SHA256SUMS checks sources deferred-rpms)
unzip -t "$archive" > "$job/logs/delivery-zip-check.log"
(cd "$job"; sha256sum "${archive##*/}" > "${archive##*/}.sha256")
echo 'Prepared payload archived; no installer entrypoint, device write or hardware acceptance.'
