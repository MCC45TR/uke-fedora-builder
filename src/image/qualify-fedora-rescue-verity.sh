#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Native host assembly qualification, not an initrd/device installer.
set -Eeuo pipefail
trap 'printf "UKE_FEDORA_VERITY_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
[[ $# == 2 && $(uname -m) == aarch64 && -f /.uke-rescue-worker &&
   -d $1 && ! -L $1 && -f $1/rescue-composition.json && -f $1/rescue.ext4 && ! -e $1/verity ]]
input=$(realpath "$1")
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
# shellcheck disable=SC1091
source "$repo/src/image/fastboot-singleboot-layout.sh"
jq -e '.artifact_kind=="unqualified-fedora-rescue-root" and .architecture=="aarch64" and
    .filesystem=="ext4" and .signatures_verified and .matching_kernel_payload_verified and
    .selinux_labels_verified and .root_read_only and (.userdata_automount|not)' "$input/rescue-composition.json" >/dev/null
expected=$(jq -er .sha256 "$input/rescue-composition.json")
[[ $(sha256sum "$input/rescue.ext4" | cut -d ' ' -f1) == "$expected" ]]
layout=$(fastboot_super_layout "$2")
capacity=$(jq -er '.partitions[1].bytes' <<< "$layout")
mkdir -m700 "$input/verity"
work=$(mktemp -d /job/rescue-verity.XXXXXXXX)
trap 'find "$work" -depth -delete' EXIT
bash "$repo/tests/rescue-verity.sh" "$input/verity/native-small-fixture.json"
epoch=$(date -u +%s)
# Public deterministic salt, never an encryption key.
salt=$(printf 'UKE-rescue-verity-v1:%s:%s\n' "$expected" "$capacity" | sha256sum | cut -d ' ' -f1)
bash "$repo/src/image/build-rescue-verity.sh" "$input/rescue.ext4" "$expected" \
    "$capacity" "$epoch" "$salt" "$work/candidate"
for image in "$input/rescue.ext4" "$work/candidate/rescue.verity"; do
    if [[ $image == "$input/rescue.ext4" ]]; then prefix=before; else prefix=after; fi
    debugfs -R "dump /etc/fstab $work/$prefix-fstab" "$image" >/dev/null 2>&1
    debugfs -R "dump /usr/lib/systemd/systemd $work/$prefix-systemd" "$image" >/dev/null 2>&1
    debugfs -R 'ea_get /usr/lib/systemd/systemd security.selinux' "$image" > "$work/$prefix-label" 2>&1
done
cmp "$work/before-fstab" "$work/after-fstab"
cmp "$work/before-systemd" "$work/after-systemd"
cmp "$work/before-label" "$work/after-label"
grep -F init_exec_t "$work/after-label" >/dev/null
readelf -h "$work/after-systemd" | grep -E 'Machine:.*AArch64' >/dev/null
e2fsck -fn "$work/candidate/rescue.verity" > "$input/verity/filesystem-audit.txt" 2>&1
[[ $(sha256sum "$work/candidate/rescue.verity" | cut -d ' ' -f1) == "$(jq -er .container_sha256 "$work/candidate/rescue-verity.json")" ]]
[[ $(sha256sum "$input/rescue.ext4" | cut -d ' ' -f1) == "$expected" ]]
cp "$work/candidate/rescue-verity.json" "$input/verity/geometry-and-root.json"
cp "$work/candidate/verity-format.log" "$input/verity/"
rpm -q veritysetup cryptsetup-libs e2fsprogs e2fsprogs-libs > "$input/verity/original-tools.txt"
sha256sum "$repo/src/image/"{rescue-verity-layout,build-rescue-verity,qualify-fedora-rescue-verity}.sh \
    "$repo/tests/rescue-verity.sh" > "$input/verity/source-sha256.txt"
jq -n --argjson capacity "$2" \
    '{schema_version:1,native_architecture:"aarch64",actual_fedora_rescue_input:true,
      super_capacity_input_bytes:$capacity,measured_256gb_geometry:false,
      input_unchanged:true,original_fstab_and_systemd_preserved:true,selinux_init_context_preserved:true,
      original_tools_userspace_verity_verification:true,container_not_retained_to_avoid_duplicate_images:true,
      repeated_full_size_candidate_tested:false,kernel_mapping_tested:false,
      metadata_signature_verified:false,operating_system_booted:false,physical_ufs_tested:false,
      common_installable_archive_created:false}' > "$input/verity/qualification.json"
(cd "$input/verity"; find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum) > "$work/SHA256SUMS"
mv "$work/SHA256SUMS" "$input/verity/SHA256SUMS"
