#!/usr/bin/env bash
# Reproduce the two boot wrappers attested by the signed Stable core RPM.
set -Eeuo pipefail
[[ $# == 4 ]]
bundle=$1 image=$2 kernel=$3 output=$4
codec=$bundle/boot-image
receipt=$bundle/super-profiles.json
release=$(jq -er .kernel_release "$kernel")
image_sha=$(sha256sum "$image" | cut -d ' ' -f1)
jq -e --arg release "$release" --arg image "$image_sha" '
    .schema_version==1 and .kernel_release==$release and .raw_image_sha256==$image and
    .capacity_bytes==100663296 and .seed_contract_bytes==4294967296 and
    .kernel_capability_verified and .original_default_userdata_profile
' "$receipt" > /dev/null
for profile in userdata-super rescue; do
    case $profile in
        userdata-super) file=boot.img; key=userdata_super_sha256;;
        rescue) file=rescue-boot.img; key=rescue_sha256;;
    esac
    sha=$(jq -er --arg key "$key" '.[$key] | select(test("^[a-f0-9]{64}$"))' "$receipt")
    "$codec" create-bootloader-compat "$image" "$output/$file" "$profile"
    (cd "$output"; printf '%s  %s\n' "$sha" "$file" | sha256sum -c --strict)
    "$codec" inspect "$output/$file" | jq -e '
        .header_version==4 and .image_bytes==100663296 and .os_version_encoded==570425768 and
        .ramdisk_bytes==0 and .signature_bytes==0 and (.avb_footer_present|not)
    ' > /dev/null
    "$codec" extract "$output/$file" "$output/readback.Image"
    cmp "$image" "$output/readback.Image"
    unlink "$output/readback.Image"
done
cp "$receipt" "$output/super-profiles.json"
