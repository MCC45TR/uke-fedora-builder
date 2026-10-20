#!/usr/bin/env bash
# Host-only private data bundle; recovery integration is a separate stage.
set -Eeuo pipefail
[[ $# == 2 && $2 =~ ^[0-9a-f]{40}$ ]]
job=$(realpath "$1") builder_commit=$2
repo=$(cd "$(dirname "$0")/../.." && pwd)
[[ $(git -C "$repo" rev-parse HEAD) == "$builder_commit" ]]
for flag in f2fs-image.complete f2fs-xattr-audit.complete f2fs-readonly-audit.complete f2fs-fsck-readonly.complete root-audit.complete; do [[ -f $job/$flag ]]; done
release=$(jq -er .kernel_release "$repo/configs/images/userdata-rawhide.json")
bundle=$job/root/usr/lib/senemos/kernel-updates/$release
[[ $(readlink "$job/root/usr/lib/senemos/default-boot.img") == kernel-updates/$release/userdata.img ]]
destination=$job/delivery
[[ ! -e $destination && ! -L $destination ]]
mkdir -m700 "$destination" "$destination/checks"
cp --reflink=auto "$job/image/userdata.f2fs.img.zst" "$destination/userdata.f2fs.img.zst"
"$job/tools/boot-image" create "$job/root/usr/lib/modules/$release/vmlinuz" \
    "$destination/boot-userdata.img" userdata-vrr
cp "$job/installed-rpms.tsv" "$job/audit/installed-origins.tsv" "$job/language-audit.json" "$destination/checks/"
"$job/tools/boot-image" inspect "$destination/boot-userdata.img" > "$destination/checks/boot-header.json"
cp "$bundle/manifest" "$destination/checks/kernel-manifest"
cp "$job/image/xattrs.expected.tsv" "$destination/checks/file-capabilities-acls.tsv"
raw_hash=$(cut -d ' ' -f1 "$job/image/userdata.f2fs.img.sha256")
raw_bytes=$(stat -c %s "$job/image/userdata.f2fs.img")
boot_hash=$(sha256sum "$destination/boot-userdata.img" | cut -d ' ' -f1)
"$job/tools/check-userdata-payload" "$destination/userdata.f2fs.img.zst" "$raw_bytes" "$raw_hash" \
    "$destination/boot-userdata.img" "$boot_hash" > "$destination/checks/payload-readback.json"
jq -n --arg date "$(date -u +%F)" --arg release "$release" --arg builder "$builder_commit" \
    --arg raw "$raw_hash" --arg compressed "$(sha256sum "$destination/userdata.f2fs.img.zst" | cut -d ' ' -f1)" \
    --arg boot "$boot_hash" --argjson bytes "$raw_bytes" \
    --argjson compressed_bytes "$(stat -c %s "$destination/userdata.f2fs.img.zst")" \
    --argjson boot_bytes "$(stat -c %s "$destination/boot-userdata.img")" \
    '{schema_version:1,created:$date,artifact_kind:"prepared-data-payload",device:"uke",architecture:"aarch64",
      distribution:"Fedora Rawhide",desktop:"original Fedora Plasma",root_partition:"userdata",root_filesystem:"f2fs",root_label:"UKE_LINUX",
      root:{file:"userdata.f2fs.img.zst",raw_bytes:$bytes,raw_sha256:$raw,compressed_bytes:$compressed_bytes,compressed_sha256:$compressed},
      boot:{file:"boot-userdata.img",bytes:$boot_bytes,sha256:$boot,kernel_release:$release,selector:"senemos.root=userdata"},
      sources:{builder_commit:$builder,kernel_commit:"bfe93de225e97d1d8f18b63b410f04bd5ccd069d",kernel_copr_build:11179692,singleboot_commit:"3d18f5c",singleboot_copr_build:11179700},
      kernel_package:"senemos-uke-linux-kernel-mainline-singleboot",copr_project:"mcc45tr/uke-linux-test",
      private_device_test:true,redistributable:false,oem_firmware_included:true,device_private_data_included:true,
      root_locked:true,precreated_human_account:false,credentials_included:false,ssh_installed:true,ssh_enabled:false,
      only_copr:"mcc45tr/uke-linux-test",selinux:"enforcing",firewalld_enabled:true,
      automatic_kernel_activation:true,kernel_activation_policy:"guarded-userdata-updater",boot_ab_qualified:false,vrr_min_hz:30,
      physical_boot_tested:false,recovery_installation_tested:false,hardware_tested:false,
      validation:{signed_public_packages:true,private_archives_match_live_device:true,full_f2fs_contents_and_metadata:true,
        explicit_xattr_and_acl_readback:true,selinux_label_readback:true,fsck_f2fs:true,
        readonly_metadata_remount:true,fsck_dry_run_unchanged:true},
      continuation:"Manual userdata/boot test; recovery installer and filesystem growth remain separate."}' > "$destination/payload.json"
# SHA256SUMS is explicitly excluded from the input inventory.
# shellcheck disable=SC2094
(cd "$destination"; find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS)
printf 'Private prepared payload verified; no device write or hardware acceptance.\n'
