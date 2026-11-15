#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# COPR host fixture, using owned regular files; never open a physical device.
set -Eeuo pipefail
trap 'printf "UKE_COHORT_CONTENT_TEST_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
[[ $# == 3 && $(uname -m) == aarch64 && -x $1 && -x $2 && ! -e $3 && ! -L $3 ]]
tool=$(realpath "$1") codec=$(realpath "$2") report=$(realpath -m "$3")
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$repo/src/image/fastboot-singleboot-layout.sh"
# shellcheck disable=SC1091
source "$repo/src/image/rescue-verity-layout.sh"
[[ $(sha256sum /usr/bin/avbtool | cut -d ' ' -f1) == "$(jq -er .fedora_avbtool_sha256 "$repo/packaging/libavb-source.json")" ]]
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
cd "$work"
put_le() {
    local file=$1 offset=$2 value=$3 width=$4 byte octal
    for ((byte=0;byte<width;byte++)); do
        printf -v octal '%03o' "$(((value>>(byte*8))&255))"
        printf '%b' "\\$octal" | dd of="$file" bs=1 seek="$((offset+byte))" conv=notrunc status=none
    done
}
flip() {
    local value octal
    value=$(od -An -tu1 -j "$2" -N1 "$1" | tr -d '[:space:]')
    printf -v octal '%03o' "$((value^1))"
    printf '%b' "\\$octal" | dd of="$1" bs=1 seek="$2" conv=notrunc status=none
}
truncate -s65536 kernel
put_le kernel 16 65536 8
printf '\101\122\115\144' | dd of=kernel bs=1 seek=56 conv=notrunc status=none
printf 'Owned kernel fixture, never executable as an OS.\n' | dd of=kernel bs=1 seek=512 conv=notrunc status=none
# Reuse the existing native v4 codec with a small owned template. No change to
# the legacy 96MiB image producer and no upstream Python boot encoder is needed.
truncate -s131072 stock
printf 'ANDROID!\100\000\000\000' | dd of=stock conv=notrunc status=none
put_le stock 20 1584 4
put_le stock 40 4 4
"$codec" pack stock kernel boot.img 131072
prefix=$("$codec" inspect boot.img | jq -er .payload_end)
[[ $prefix == 69632 ]]
truncate -s "$prefix" boot.img
cp boot.img saved-boot
truncate -s8192 vendor_boot.img
truncate -s4096 dtbo.img
printf 'Owned vendor fixture\n' | dd of=vendor_boot.img conv=notrunc status=none
printf 'Owned DTBO fixture\n' | dd of=dtbo.img conv=notrunc status=none
sha256sum kernel saved-boot vendor_boot.img dtbo.img > original.sha256
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out key.pem 2> keygen.log
openssl pkey -in key.pem -pubout -out key.pub
openssl pkey -pubin -in key.pub -outform DER -out key.der
avbtool extract_public_key --key key.pem --output key.avb
avb_pin=$(sha256sum key.avb | cut -d ' ' -f1)
spki_pin=$(sha256sum key.der | cut -d ' ' -f1)
hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
layout=$(fastboot_super_layout 11274289152)
verity=$(rescue_verity_layout "$(jq -er '.partitions[1].bytes' <<< "$layout")")
descriptor() {
    local name=$1 file=$2 bytes capacity
    bytes=$(stat -c %s "$file")
    capacity=$(((bytes+4095)/4096*4096+1048576))
    # The virtual size gives the formatter room for intermediate metadata.
    # --do_not_append leaves the real input unchanged; only image_size is used.
    avbtool add_hash_footer --image "$file" --partition_name "$name" --partition_size "$capacity" \
      --salt "$hash" --output_vbmeta_image "$name.desc" --do_not_append_vbmeta_image
    [[ $(stat -c %s "$file") == "$bytes" ]]
}
reuse_descriptors=false
publish() {
    local mutation=${1:-.} name
    if [[ $reuse_descriptors != true ]]; then
        for name in boot vendor_boot dtbo; do descriptor "$name" "$name.img"; done
    fi
    jq -n --arg hash "$hash" --argjson l "$layout" --argjson v "$verity" \
      --arg kernel "$(sha256sum kernel | cut -d ' ' -f1)" \
      --arg boot "$(sha256sum boot.img | cut -d ' ' -f1)" \
      --arg vendor "$(sha256sum vendor_boot.img | cut -d ' ' -f1)" \
      --arg dtbo "$(sha256sum dtbo.img | cut -d ' ' -f1)" --argjson bytes "$(stat -c %s boot.img)" \
      '{schema_version:1,platform:"xiaomi,uke",cohort_id:"11111111111111111111111111111111",
        kernel_release:"7.3.3-26-unstable",kernel_source_commit:"c7adc996350e3692b4492ab007cad63070dde6c2",
        payloads:{kernel_image:{bytes:65536,sha256:$kernel},boot:{bytes:$bytes,sha256:$boot},
          vendor_boot:{bytes:8192,sha256:$vendor},dtbo:{bytes:4096,sha256:$dtbo},
          super_seed:{bytes:4294967296,sha256:$hash},userdata_seed:{bytes:15032385536,sha256:$hash}},
        geometries:[{super_bytes:$l.super_bytes,userdata_bytes:497535680512,logical_block_bytes:4096,
          rescue_start_bytes:$l.partitions[1].start_byte,rescue_bytes:$l.partitions[1].bytes,
          swap_start_bytes:$l.partitions[0].start_byte,swap_bytes:$l.partitions[0].bytes,
          verity:{data_blocks:$v.data_blocks,hash_start_blocks:$v.data_blocks,hash_blocks:$v.hash_blocks,
            root_sha256:$hash,salt:$hash,container_sha256:$hash}}]}' | jq "$mutation" > manifest.json
    { printf 'UKE-PROTECTED-COHORT-v1\n'; cat manifest.json; } > cohort
    openssl dgst -sha256 -sign key.pem -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:32 \
      -sigopt rsa_mgf1_md:sha256 -out cohort.sig cohort
    avbtool make_vbmeta_image --algorithm SHA256_RSA4096 --key key.pem --rollback_index 42 \
      --include_descriptors_from_image boot.desc --include_descriptors_from_image vendor_boot.desc \
      --include_descriptors_from_image dtbo.desc --prop_from_file com.uke.protected.cohort:cohort \
      --prop_from_file com.uke.protected.signature:cohort.sig \
      --prop_from_file com.uke.protected.public_key:key.pub --output vbmeta.img
}
context=("$avb_pin" "$spki_pin" 11111111111111111111111111111111 7.3.3-26-unstable
    c7adc996350e3692b4492ab007cad63070dde6c2 11274289152 497535680512 4096
    100663296 100663296 100663296 100663296 25165824 25165824)
slot=a inputs=(3 4 5)
invoke() { timeout 8s "$tool" vbmeta.img "${context[@]}" "$slot" "${inputs[@]}"; }
open_inputs() { exec 3<boot.img 4<vendor_boot.img 5<dtbo.img; }
close_inputs() { exec 3<&- 4<&- 5<&-; }
run() { local status=0; open_inputs; invoke || status=$?; close_inputs; return "$status"; }
publish
run > positive.json
jq -e '.fd_contents_verified and .plain_and_salted_prefixes_matched and .kernel_image_slice_matched and
 .verified_bytes==81920 and .block_input_count==0 and .io_buffer_bytes==65536 and .owned_handles_released and
 .caller_positions_unchanged and (.physical_identity_verified|not) and (.selected_slot_bound|not) and
 (.booted_kernel_verified|not) and (.role_admitted|not)' positive.json >/dev/null
refused=0
reject_open() {
    local status=0
    invoke > refused.json 2> refused.log || status=$?
    [[ $status == 1 && ! -s refused.json && $(tail -n1 refused.log) == UKE_COHORT_CONTENT_REJECTED ]]
    ((refused+=1))
}
reject() { open_inputs; reject_open; close_inputs; }
# Independently reject an incorrect plain digest, salted digest and kernel
# slice, although the metadata signatures are valid in each case.
publish '.payloads.boot.sha256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'; reject
publish '.payloads.kernel_image.sha256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'; reject
publish '.payloads.kernel_image.bytes=65535'; reject
publish
cp boot.img bad-boot; flip bad-boot 5000; descriptor boot bad-boot
reuse_descriptors=true; publish; reject; reuse_descriptors=false
publish
for item in 'boot.img:5000' 'vendor_boot.img:10' 'dtbo.img:10'; do
    file=${item%:*} offset=${item##*:}
    flip "$file" "$offset"; reject; flip "$file" "$offset"
done
truncate -s "$((prefix-1))" boot.img; reject
cp saved-boot boot.img
# Sign malformed boot headers as well, so structure/kernel-range rejection is
# separate from detecting a changed file with an old expected digest.
for field in '0:88:1' '20:1580:4' '40:3:4' '12:4:4' '1580:4:4' '24:1:4' \
    '8:65535:4' '8:131072:4' '4152:0:4' '4112:1:8' '4112:536870913:8' '4120:1:8'; do
    cp saved-boot boot.img
    IFS=: read -r offset value width <<< "$field"
    put_le boot.img "$offset" "$value" "$width"
    publish; reject
done
cp saved-boot boot.img
put_le boot.img 8 69632 4
publish '.payloads.kernel_image.bytes=69632'; reject
cp saved-boot boot.img
put_le boot.img 8 32 4
publish '.payloads.kernel_image.bytes=32'; reject
cp saved-boot boot.img
dd if=/dev/zero bs=1536 count=1 status=none | tr '\000' A | dd of=boot.img bs=1 seek=44 conv=notrunc status=none
publish; reject
cp saved-boot boot.img
publish
inputs=(3 3 5); reject; inputs=(3 4 5)
inputs=(3 99 5); reject; inputs=(3 4 5)
inputs=(0 4 5); reject; inputs=(3 4 5)
slot=x; reject; slot=a
exec 3<>boot.img 4<vendor_boot.img 5<dtbo.img; reject_open; close_inputs
exec 3</dev/null 4<vendor_boot.img 5<dtbo.img; reject_open; close_inputs
exec 3< <(printf x) 4<vendor_boot.img 5<dtbo.img; reject_open; close_inputs
# Force failure after two successful duplicates. The inspection CLI checks
# actual descriptor counts on its success and exception exits.
(ulimit -n 8; open_inputs; invoke) > exhausted.json 2> exhausted.log && exit 1
[[ ! -s exhausted.json && $(tail -n1 exhausted.log) == UKE_COHORT_CONTENT_REJECTED ]]
((refused+=1))
# Replacing the original pathname after the caller opened it must not replace
# the bytes hashed through the retained descriptor.
open_inputs
mv boot.img pinned-boot
cp pinned-boot boot.img; flip boot.img 5000
invoke > pinned.json
close_inputs
unlink boot.img; mv pinned-boot boot.img
jq -e '.fd_contents_verified and .owned_handles_released' pinned.json >/dev/null
# pread must preserve the shared caller offset.
open_inputs
read -r -N1 first <&3
[[ $first == A ]]
invoke > offset.json
read -r -N1 second <&3
[[ $second == N ]]
close_inputs
# A trailer outside the authenticated prefix is admitted as transport data;
# its complete size still belongs to the independent before-write flash audit.
printf 'optional-trailer' >> boot.img
run > trailer.json
jq -e '.verified_bytes==81920 and .fd_contents_verified' trailer.json >/dev/null
truncate -s "$prefix" boot.img
cmp boot.img saved-boot
sha256sum -c original.sha256 > original-unchanged.log
# One large sparse prefix checks process RSS and bounded userspace buffering.
# Kernel page cache is separate; the host formatter is a separate process.
truncate -s100663296 boot.img
publish
slot=b
run > streaming.json
jq -e '.verified_bytes==100675584 and .fd_contents_verified and .kernel_image_slice_matched and
 .peak_rss_kib<65536 and .owned_handles_released' streaming.json >/dev/null
[[ $refused == 31 ]]
jq -n --argjson refused "$refused" --slurpfile large streaming.json \
 '{schema_version:1,native_architecture:"aarch64",owned_regular_files_only:true,
  real_signed_metadata_then_fd_content_verification:true,plain_and_salted_hashes_checked_independently:true,
  kernel_slice_checked:true,malformed_signed_boot_headers_refused:true,caller_offsets_preserved:true,
  pathname_replacement_kept_pinned_input:true,partial_duplicate_failure_cleaned_up:true,
  owned_handles_released:true,original_inputs_unchanged:true,refused_cases:$refused,
  large_streaming_result:$large[0],physical_block_branch_tested:false,physical_identity_verified:false,
  selected_slot_bound:false,booted_kernel_verified:false,role_admitted:false,
  operating_system_booted:false,storage_or_key_release_executed:false}' > "$report"
