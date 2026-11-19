#!/usr/bin/bash
# Package the completed, independently read back image on the Actions runner.
set -Eeuo pipefail
umask 077
[[ $# == 2 ]]
artifacts=$(realpath "$1") output=$(realpath -m "$2")
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
manifest=$artifacts/manifest.json
geometry=$repo/configs/images/uke-512gb-test-geometry.json
[[ -d $artifacts && ! -e $output ]]

# shellcheck source=fastboot-requirements.sh
# shellcheck disable=SC1091
source "$repo/src/image/fastboot-requirements.sh"
fastboot_requirements "$geometry" > /dev/null
jq -e '
    .device=="uke" and .architecture=="aarch64" and .channel=="stable" and
    .mode=="singleboot" and .partition=="userdata" and .filesystem=="ext4" and
    .desktop=="kde" and .default_shell=="bash" and .kernel_profile=="normal" and
    .kernel_release=="7.4.5-senemos" and .kernel_repository=="mcc45tr/uke-linux" and
    .kernel_rpm_signature=="verified COPR signature" and .kernel_rpms_locally_built==false and
    .image_built and .rpm_transaction_validated and .filesystem_contents_readback and
    .filesystem_metadata_readback and .independent_aosp_decoder_verified and
    .selinux_policy_contexts_verified and .cohort_validation.final_filesystem_hashes_verified and
    (.root_raw_bytes|type=="number" and .==floor and .>0 and .<=2199023255552) and
    (.device_private_data_included|not) and (.credentials_included|not)
' "$manifest" >/dev/null

boot_sha=$(jq -er .boot_sha256 "$manifest")
userdata_sha=$(jq -er .root_sparse_sha256 "$manifest")
# This is the reconstructed v0 overlay installed and booted with the measured
# OEM vendor_boot cohort on the 512 GB Uke.
dtbo_sha=74958f51ed384f86e542fefe42c2252c4f309339df5c0850287e983db89fcfda
jq -e --arg hash "$dtbo_sha" '
    .schema_version==1 and .dtbo_sha256==$hash and .common_dtbo and
    .reconstructed_flattened_source and (.automatic_partition_writes|not)
' "$artifacts/dtbo-source-cohort.json" >/dev/null
for sha in "$boot_sha" "$userdata_sha" "$dtbo_sha"; do [[ $sha =~ ^[a-f0-9]{64}$ ]]; done
(
    cd "$artifacts"
    printf '%s  %s\n' "$boot_sha" boot.img "$dtbo_sha" dtbo.img "$userdata_sha" userdata.img |
        sha256sum -c --strict
)
(( $(stat -c %s "$artifacts/boot.img") <= $(jq -er .partitions.boot_a "$geometry") ))
(( $(stat -c %s "$artifacts/dtbo.img") <= $(jq -er .partitions.dtbo_a "$geometry") ))
(( $(jq -er .root_raw_bytes "$manifest") <= $(jq -er .partitions.userdata "$geometry") ))

mkdir "$output"
scratch=$(mktemp -d "$(dirname "$output")/fastboot-metadata.XXXXXXXX")
trap 'find "$scratch" -depth -delete' EXIT
archive=uke-fedora-rawhide-stable-kde-bash-singleboot-7.4.5-senemos-fastboot.zip
{
    fastboot_requirements "$geometry"
    printf 'require current-slot=a\n'
} > "$scratch/android-info.txt"
printf '%s\n' 'version 1' 'flash dtbo_a dtbo.img' 'flash boot_a boot.img' 'flash userdata userdata.img' > "$scratch/fastboot-info.txt"
jq --arg hash "$dtbo_sha" --slurpfile source "$artifacts/dtbo-source-cohort.json" '
    . + {artifact_kind:"stable-singleboot-fastboot-test",targets:["dtbo_a","boot_a","userdata"],
         dtbo_sha256:$hash,dtbo_source:$source[0],required_current_slot:"a",
         product_capacity:"measured 512 GB",replaces_existing_userdata:true}
' "$manifest" > "$scratch/manifest.json"
cat > "$scratch/README.txt" <<TEXT
Fedora Rawhide Stable, KDE Plasma, Bash, EXT4 singleboot.

This installation erases userdata, including all files and accounts.
Use the measured 512 GB Uke with slot A selected and the matching working OEM
vendor boot and partition layout. The archive checks product, slot and measured
partition capacities before writing. Stop if a requirement fails.

fastboot update $archive

The archive writes the matching DTBO and Linux boot image to slot A, then writes
userdata. Complete the Plasma account setup after reboot.
TEXT
(
    cd "$scratch"
    sha256sum android-info.txt fastboot-info.txt manifest.json README.txt > SHA256SUMS
    printf '%s  %s\n' "$boot_sha" boot.img "$dtbo_sha" dtbo.img "$userdata_sha" userdata.img >> SHA256SUMS
    zip -q -1 "$output/$archive" android-info.txt fastboot-info.txt manifest.json README.txt SHA256SUMS
)
(cd "$artifacts"; zip -q -1 "$output/$archive" boot.img dtbo.img userdata.img)
unzip -tq "$output/$archive"
cp "$scratch/manifest.json" "$output/manifest.json"
(cd "$output"; sha256sum "$archive" > SHA256SUMS)
