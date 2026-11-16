#!/usr/bin/env bash
# Host-only composition from a qualified filesystem input, never a device.
set -Eeuo pipefail
trap 'printf "UKE_SUPER_SEED_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
[[ $# == 3 && -d $1 && ! -L $1 && ! -e $3 && ! -L $3 ]]
input=$(realpath "$1")
minimum=$2
output=$(realpath -m "$3")
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
composition=$input/rescue-composition.json
image=$input/rescue.ext4
for file in "$composition" "$image" "$input/kernel-info.json" "$input/source-sha256.txt" "$input/rescue-console-readback.json"; do
    [[ -f $file && ! -L $file ]]
done
jq -e '.artifact_kind=="unqualified-fedora-rescue-root" and .architecture=="aarch64" and
  .filesystem=="ext4" and .label=="FEDORA_RESCUE" and .signatures_verified==true and
  .python_payload_audited==true and .matching_kernel_payload_verified==true and .ext4_readback_verified==true and
  .selinux_labels_verified==true and .root_read_only==true and .userdata_automount==false and
  (.raw_bytes|type=="number" and floor==. and .>=536870912 and .<=1073741824) and
  (.sha256|test("^[a-f0-9]{64}$")) and .kernel.kernel_profile=="unstable" and
  .kernel.kernel_family=="senemos-uke-linux-kernel-mainline-unstable" and
  .kernel.kernel_rpm_signature=="verified COPR signature" and
  (.kernel.kernel_release|test("^7[.]3[.][0-9]+-[1-9][0-9]*-unstable$"))' "$composition" >/dev/null
[[ $(jq -Sc .kernel "$composition") == "$(jq -Sc . "$input/kernel-info.json")" ]]
bytes=$(jq -er .raw_bytes "$composition")
[[ $(stat -c %s "$image") == "$bytes" &&
   $(sha256sum "$image" | cut -d ' ' -f1) == "$(jq -er .sha256 "$composition")" ]]
[[ $(blkid -p -s TYPE -o value "$image") == ext4 && $(blkid -p -s LABEL -o value "$image") == FEDORA_RESCUE ]]
jq -e --arg hash "$(jq -er .sha256 "$composition")" '
 .artifact_kind=="uke-rescue-console-source-readback" and .rescue_raw_sha256==$hash and
 .source_scripts_verified and .unit_files_verified and .locked_root_verified and
 .human_account_absent and .activation_links_verified and .inspection_read_only' "$input/rescue-console-readback.json" >/dev/null
# Check a fixed allowlist instead of executing paths supplied by a receipt.
expected=$(mktemp)
trap 'unlink "$expected"' EXIT
sha256sum "$repo/src/image/"{compose-fedora-rescue,configure-fedora-rescue,rescue-seed-manifest,fastboot-singleboot-layout}.sh \
    "$repo/src/image/"{rescue-console-login,rescue-admin-policy,select-uke-userdata}.sh \
    "$repo/src/image/"uke-rescue-{usb,console}.service "$repo/src/image/40-uke-rescue-serial.conf" \
    "$repo/scripts/verify-rescue-console.sh" \
    "$repo/src/public/"{repository-tools,repository-kernel,cohort,root-transaction}.sh \
    "$repo/src/audit/check-target-payload.sh" "$repo/configs/images/rescue-rawhide.json" |
    sed "s|  $repo/|  /builder/|" > "$expected"
cmp "$expected" "$input/source-sha256.txt"
# shellcheck source=fastboot-singleboot-layout.sh
# shellcheck disable=SC1091
source "$repo/src/image/fastboot-singleboot-layout.sh"
layout=$(fastboot_seed_layout "$bytes" "$minimum")
layout_file=$(mktemp)
trap 'unlink "$expected"; unlink "$layout_file"' EXIT
jq -M . <<< "$layout" > "$layout_file"
bash "$repo/src/image/build-fastboot-super.sh" "$layout_file" "$image" "$output"
cp "$input/rescue-console-readback.json" "$output/"
mkdir "$output/rescue-source"
for file in rescue-composition.json kernel-info.json source-sha256.txt packages.tsv installed-nevras.txt \
    python-audit.txt selinux-audit.txt units-audit.txt filesystem-audit.txt kernel-payload-audit.txt; do
    [[ -f $input/$file && ! -L $input/$file ]]
    cp "$input/$file" "$output/rescue-source/"
done
jq -n --slurpfile root "$composition" --argjson minimum "$minimum" --argjson layout "$layout" \
    '{schema_version:1,artifact_kind:"unqualified-fastboot-super-seed",rescue_input:$root[0],
      seed_layout:$layout,minimum_super_input_bytes:$minimum,expanded_seed_fits_supplied_minimum:true,
      measured_256gb_geometry_qualified:false,common_archive_qualified:false,
      protected_early_boot_integrated:false,physical_ufs_tested:false,operating_system_booted:false,
      secure_boot_qualified:false,hardware_encryption_qualified:false,installable_archive_created:false}' \
    > "$output/super-seed.json"
sha256sum "$repo/src/image/"{compose-fastboot-super-seed,build-fastboot-super,fastboot-singleboot-layout,inspect-fastboot-super}.sh \
    "$repo/src/image/"{plan-super-provision,provision-fastboot-super,map-fastboot-rescue}.sh \
    "$repo/src/image/select-uke-super.sh" "$repo/tests/fastboot-physical-super.sh" \
    "$repo/tests/fastboot-super-grow.sh" > "$output/seed-source-sha256.txt"
(cd "$output"; find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) > "$expected"
mv "$expected" "$output/SHA256SUMS"
trap 'unlink "$layout_file"' EXIT
printf 'Real Fedora rescue composed into an expanded-size-bounded super seed; boot/security qualification remains open.\n'
