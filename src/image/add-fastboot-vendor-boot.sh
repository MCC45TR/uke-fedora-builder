#!/usr/bin/env bash
# Extend a verified Actions ZIP with a matching local OEM firmware input.
set -Eeuo pipefail
umask 077
export LC_ALL=C

fail() { printf 'Vendor boot packaging: %s\n' "$*" >&2; exit 1; }
if [[ $# != 5 ]]; then
    fail "Usage: ${0##*/} ACTIONS_ZIP ACTIONS_SHA256 VENDOR_BOOT_IMG VENDOR_SHA256 NEW_OUTPUT_DIRECTORY"
fi
[[ -f $1 && -f $3 && ! -e $5 && ! -L $5 ]] || fail 'Expected two input files and a new output directory.'
[[ $2 =~ ^[0-9a-f]{64}$ && $4 =~ ^[0-9a-f]{64}$ ]] || fail 'Expected two SHA-256 digests.'
input=$(realpath -- "$1")
vendor=$(realpath -- "$3")
output=$(realpath -m -- "$5")
archive=${input##*/}
[[ $archive =~ ^fedora-rawhide-uke-(kde-plasma|gnome|cutefish)-[0-9]{6}-[0-9]{4}[.]zip$ ]] ||
    fail 'Expected a dated Rawhide Fastboot artifact.'
hash() { sha256sum < "$1" | cut -d ' ' -f1; }
[[ $(hash "$input") == "$2" && $(hash "$vendor") == "$4" ]] || fail 'Input SHA-256 mismatch.'

repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
profile=$repo/configs/images/rawhide-fastboot
vendor_bytes=$(stat -c %s -- "$vendor")
partition_bytes=$(jq -er .partition_bytes "$profile/vendor-boot.json")
((vendor_bytes >= 4096 && vendor_bytes <= partition_bytes)) || fail 'Vendor boot exceeds the measured Uke partition size.'
[[ $(head -c 8 -- "$vendor") == VNDRBOOT ]] || fail 'Expected a vendor boot image.'
u32() { od --endian=little -An -tu4 -j "$2" -N 4 -- "$1" | tr -d ' '; }
[[ $(u32 "$vendor" 8) == 4 && $(u32 "$vendor" 12) == 4096 && $(u32 "$vendor" 2096) == 2128 ]] ||
    fail 'Vendor boot header or page size differs from the Uke v4 layout.'
ramdisk_bytes=$(u32 "$vendor" 24)
dtb_bytes=$(u32 "$vendor" 2100)
table_bytes=$(u32 "$vendor" 2112)
table_entries=$(u32 "$vendor" 2116)
entry_bytes=$(u32 "$vendor" 2120)
bootconfig_bytes=$(u32 "$vendor" 2124)
page_aligned() { printf '%s\n' "$(( ($1 + 4095) / 4096 * 4096 ))"; }
dtb_start=$((4096 + $(page_aligned "$ramdisk_bytes")))
active_bytes=$((dtb_start + $(page_aligned "$dtb_bytes") + $(page_aligned "$table_bytes") + $(page_aligned "$bootconfig_bytes")))
((ramdisk_bytes > 0 && dtb_bytes == $(jq -er .dtb_bytes "$profile/vendor-boot.json") && table_entries == 1 &&
    table_bytes == 108 && entry_bytes == 108 && bootconfig_bytes > 0 && active_bytes <= vendor_bytes)) ||
    fail 'Vendor boot sections differ from the compatible Uke layout.'
dtb_digest=$(dd if="$vendor" iflag=skip_bytes,count_bytes bs=65536 skip="$dtb_start" count="$dtb_bytes" status=none | sha256sum | cut -d ' ' -f1)
[[ $dtb_digest == "$(jq -er .dtb_sha256 "$profile/vendor-boot.json")" ]] ||
    fail 'Vendor boot contains a different base DTB cohort.'

files=(android-info.txt fastboot-info.txt manifest.json README.txt SHA256SUMS super_empty.img
    boot.img dtbo.img rescue-boot.img super.img userdata.img)
printf '%s\n' "${files[@]}" | sort | cmp - <(unzip -Z -1 "$input" | sort) ||
    fail 'Unexpected entries in the Actions ZIP.'
for file in android-info.txt fastboot-info.txt; do
    unzip -p "$input" "$file" | cmp - "$profile/$file" || fail "Unexpected $file in the Actions ZIP."
done

(( $(df -PB1 "${output%/*}" | awk 'NR==2 {print $4}') >= 2 * $(stat -c %s "$input") + vendor_bytes + 1073741824 )) ||
    fail 'Insufficient space for the ZIP, its update workspace and 1 GiB of reserve.'
work=$(mktemp -d "${output%/*}/vendor-fastboot.XXXXXXXX")
trap 'find "$work" -depth -delete' EXIT
for file in "${files[@]:0:5}"; do unzip -p "$input" "$file" > "$work/$file"; done
jq -e '
    .artifact_kind=="uke-rawhide-super-fastboot" and .device=="uke" and
    .mode=="singleboot" and .installation=="fastboot update" and
    .targets==["super","userdata","dtbo_active","boot_active"] and
    .dtbo_sha256=="74958f51ed384f86e542fefe42c2252c4f309339df5c0850287e983db89fcfda"
' "$work/manifest.json" >/dev/null || fail 'Manifest does not describe the matching Uke boot cohort.'
jq --arg hash "$4" --arg dtb "$dtb_digest" --argjson bytes "$vendor_bytes" '
    .images["vendor_boot.img"]={sha256:$hash,stored_bytes:$bytes,expanded_bytes:$bytes} |
    .targets |= (.[0:2]+["vendor_boot_active"]+.[2:]) |
    .vendor_boot={source:"local compatible OEM input",dtb_sha256:$dtb,physical_flash_tested:false}
' "$work/manifest.json" > "$work/manifest.new"
mv "$work/manifest.new" "$work/manifest.json"
printf -v capacities '0x%x|0x%08x|0x%016x' "$partition_bytes" "$partition_bytes" "$partition_bytes"
{
    printf 'require has-slot:vendor_boot=yes\n'
    printf 'require partition-size:vendor_boot_a=%s\n' "$capacities"
    printf 'require partition-size:vendor_boot_b=%s\n' "$capacities"
} >> "$work/android-info.txt"
sed -i '/^flash dtbo/i flash vendor_boot vendor_boot.img' "$work/fastboot-info.txt"
sed -i 's/with working, compatible vendor_boot and bootloader firmware/with matching bootloader firmware/;
    s/The archive writes super, userdata, and the active slot.s DTBO and boot\./The archive writes super, userdata, and the active slot\x27s vendor_boot, DTBO and boot./;
    s/the other slot.s boot and DTBO, vendor_boot,/the other slot\x27s boot, DTBO and vendor_boot,/' "$work/README.txt"
printf '\nVendor boot uses the verified local OEM input. Physical installation of this variant remains to be tested.\n' >> "$work/README.txt"
ln -s -- "$vendor" "$work/vendor_boot.img"
(
    cd "$work"
    sed -i -E '/  (android-info[.]txt|fastboot-info[.]txt|manifest[.]json|README[.]txt)$/d' SHA256SUMS
    sha256sum android-info.txt fastboot-info.txt manifest.json README.txt vendor_boot.img >> SHA256SUMS
    cp --reflink=auto -- "$input" "$archive"
    zip -q -1 "$archive" android-info.txt fastboot-info.txt manifest.json README.txt SHA256SUMS vendor_boot.img
    unzip -tq "$archive"
    for file in android-info.txt fastboot-info.txt manifest.json README.txt SHA256SUMS vendor_boot.img; do
        unzip -p "$archive" "$file" | cmp - "$file"
    done
    printf '%s\n' "${files[@]}" vendor_boot.img | sort | cmp - <(unzip -Z -1 "$archive" | sort)
    sha256sum "$archive" > archive.sha256
    mkdir -- "$output"
    mv -- "$archive" "$output/"
    mv -- archive.sha256 "$output/SHA256SUMS"
)
printf '%s/%s\n' "$output" "$archive"
