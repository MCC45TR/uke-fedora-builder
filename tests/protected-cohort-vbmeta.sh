#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# COPR host fixture only. Original Fedora avbtool is never a target payload.
set -Eeuo pipefail
trap 'printf "UKE_COHORT_VBMETA_TEST_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
[[ $# == 2 && $(uname -m) == aarch64 && -x $1 && ! -e $2 && ! -L $2 ]]
tool=$(realpath "$1") report=$(realpath -m "$2")
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$repo/src/image/fastboot-singleboot-layout.sh"
# shellcheck disable=SC1091
source "$repo/src/image/rescue-verity-layout.sh"
[[ $(sha256sum /usr/bin/avbtool | cut -d ' ' -f1) == "$(jq -er .fedora_avbtool_sha256 "$repo/packaging/libavb-source.json")" ]]
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
cd "$work"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out key.pem 2> keygen.log
openssl pkey -in key.pem -pubout -out key.pub
openssl pkey -pubin -in key.pub -outform DER -out key.der
spki_pin=$(sha256sum key.der | cut -d ' ' -f1)
avbtool extract_public_key --key key.pem --output key.avb
avb_pin=$(sha256sum key.avb | cut -d ' ' -f1)
hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
cohort_id=11111111111111111111111111111111
kernel_source=c7adc996350e3692b4492ab007cad63070dde6c2
layout=$(fastboot_super_layout 11274289152)
verity=$(rescue_verity_layout "$(jq -er '.partitions[1].bytes' <<< "$layout")")
for name in boot vendor_boot dtbo; do
    if [[ $name == dtbo ]]; then size=4096; else size=8192; fi
    truncate -s "$size" "$name.img"
    printf 'Owned %s fixture, not an operating system.\n' "$name" | dd of="$name.img" conv=notrunc status=none
    avbtool add_hash_footer --image "$name.img" --partition_name "$name" --partition_size 1048576 \
      --salt "$hash" --output_vbmeta_image "$name.desc" --do_not_append_vbmeta_image
done
jq -n --arg id "$cohort_id" --arg source "$kernel_source" --arg hash "$hash" \
  --arg boot "$(sha256sum boot.img | cut -d ' ' -f1)" \
  --arg vendor "$(sha256sum vendor_boot.img | cut -d ' ' -f1)" \
  --arg dtbo "$(sha256sum dtbo.img | cut -d ' ' -f1)" --argjson l "$layout" --argjson v "$verity" \
  '{schema_version:1,platform:"xiaomi,uke",cohort_id:$id,kernel_release:"7.3.3-26-unstable",kernel_source_commit:$source,
    payloads:{kernel_image:{bytes:4096,sha256:$hash},boot:{bytes:8192,sha256:$boot},
      vendor_boot:{bytes:8192,sha256:$vendor},dtbo:{bytes:4096,sha256:$dtbo},
      super_seed:{bytes:4294967296,sha256:$hash},userdata_seed:{bytes:15032385536,sha256:$hash}},
    geometries:[{super_bytes:$l.super_bytes,userdata_bytes:497535680512,logical_block_bytes:4096,
      rescue_start_bytes:$l.partitions[1].start_byte,rescue_bytes:$l.partitions[1].bytes,
      swap_start_bytes:$l.partitions[0].start_byte,swap_bytes:$l.partitions[0].bytes,
      verity:{data_blocks:$v.data_blocks,hash_start_blocks:$v.data_blocks,hash_blocks:$v.hash_blocks,
        root_sha256:$hash,salt:$hash,container_sha256:$hash}}]}' > manifest.json
sign_inner() {
    { printf 'UKE-PROTECTED-COHORT-v1\n'; cat "$1"; } > cohort
    openssl dgst -sha256 -sign key.pem -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:32 \
      -sigopt rsa_mgf1_md:sha256 -out cohort.sig cohort
}
sign_inner manifest.json
props=(--prop_from_file com.uke.protected.cohort:cohort --prop_from_file com.uke.protected.signature:cohort.sig
    --prop_from_file com.uke.protected.public_key:key.pub)
hashes=(--include_descriptors_from_image boot.desc --include_descriptors_from_image vendor_boot.desc
    --include_descriptors_from_image dtbo.desc)
make_outer() {
    avbtool make_vbmeta_image --algorithm SHA256_RSA4096 --key key.pem --rollback_index 42 \
      "${hashes[@]}" "${props[@]}" "$@" --output candidate
}
context=("$avb_pin" "$spki_pin" "$cohort_id" 7.3.3-26-unstable "$kernel_source" 11274289152 497535680512
    4096 100663296 100663296 100663296 100663296 25165824 25165824)
run() { timeout 5s "$tool" "$1" "${context[@]}"; }
make_outer
cp candidate valid
sha256sum valid cohort cohort.sig key.pub boot.img vendor_boot.img dtbo.img > original.sha256
run candidate > positive.json
jq -e '.avb_signature_verified and .cohort_signature_verified and .manifest_schema_valid and
  .exact_geometry_selected and .both_slot_limits_checked and .boot_hash_descriptors_bound and .signed_rollback_index==42 and
  (.boot_payloads_verified|not) and (.rollback_state_verified|not) and (.physical_identity_verified|not) and
  (.hardware_trust_qualified|not) and (.role_admitted|not)' positive.json >/dev/null
cp valid vbmeta.img
avbtool verify_image --image vbmeta.img --key key.pem > original-tool-verify.log
truncate -s 65536 candidate
run candidate > boundary.json
[[ $(jq -er .vbmeta_sha256 positive.json) == "$(jq -er .vbmeta_sha256 boundary.json)" ]]
refused=0
reject() {
    local input=${1:-candidate} status=0
    run "$input" > refused.json 2> refused.log || status=$?
    [[ $status == 1 && ! -s refused.json && $(tail -n1 refused.log) == UKE_COHORT_VBMETA_REJECTED ]]
    ((refused+=1))
}
u64() { od -An -tu8 --endian=big -j "$2" -N8 "$1" | tr -d '[:space:]'; }
flip() {
    local value octal
    value=$(od -An -tu1 -j "$2" -N1 "$1" | tr -d '[:space:]')
    printf -v octal '%03o' "$((value^1))"
    printf '%b' "\\$octal" | dd of="$1" bs=1 seek="$2" conv=notrunc status=none
}
write_be() {
    local file=$1 offset=$2 value=$3 width=$4 byte octal
    for ((byte=width-1;byte>=0;byte--)); do
        printf -v octal '%03o' "$(((value>>(byte*8))&255))"
        printf '%b' "\\$octal" | dd of="$file" bs=1 seek="$((offset+width-1-byte))" conv=notrunc status=none
    done
}
auth_bytes=$(u64 valid 12) aux_bytes=$(u64 valid 20)
((auth_bytes==576 && aux_bytes>0 && aux_bytes<65536))
resign_outer() {
    { head -c256 candidate; dd if=candidate bs=1 skip=832 count="$aux_bytes" status=none; } > signed-input
    openssl dgst -sha256 -binary signed-input > digest
    openssl dgst -sha256 -sign key.pem -out outer.sig signed-input
    dd if=digest of=candidate bs=1 seek=256 conv=notrunc status=none
    dd if=outer.sig of=candidate bs=1 seek=288 conv=notrunc status=none
}
# Unsigned transport mutations.
cp valid candidate; truncate -s255 candidate; reject
cp valid candidate; truncate -s65537 candidate; reject
cp valid candidate; flip candidate 0; reject
cp valid candidate; flip candidate 256; reject
cp valid candidate; flip candidate 288; reject
cp valid candidate; flip candidate 810; reject
cp valid candidate; truncate -s65536 candidate
printf x | dd of=candidate bs=1 seek=65535 conv=notrunc status=none; reject
# Correctly signed, but forbidden header policy and descriptor regions.
for flag in 1 2 4; do make_outer --flags "$flag"; reject; done
cp valid candidate; write_be candidate 8 1 4; resign_outer; reject
cp valid candidate; write_be candidate 124 1 4; resign_outer; reject
cp valid candidate; write_be candidate 176 1 1; resign_outer; reject
cp valid candidate; write_be candidate 96 "$aux_bytes" 8; resign_outer; reject
key_offset=$(u64 valid 64)
cp valid candidate; write_be candidate 96 "$key_offset" 8; write_be candidate 104 16 8; resign_outer; reject
cp valid candidate; write_be candidate 104 0 8; resign_outer; reject
# Known-key policy is independent of valid signatures.
saved=${context[0]}; context[0]=$hash; cp valid candidate; reject; context[0]=$saved
saved=${context[1]}; context[1]=$hash; reject; context[1]=$saved
saved=${context[2]}; context[2]=22222222222222222222222222222222; reject; context[2]=$saved
saved=${context[6]}; context[6]=497535676416; reject; context[6]=$saved
make_outer --prop_from_file com.uke.protected.cohort:cohort; reject
make_outer --prop unexpected:value; reject
make_outer --kernel_cmdline 'root=/dev/zero'; reject
saved_hashes=("${hashes[@]}"); hashes=("${hashes[@]:0:4}"); make_outer; reject; hashes=("${saved_hashes[@]}")
# A signed unsupported descriptor tag cannot extend this policy.
desc_offset=$(u64 valid 96)
cp valid candidate; write_be candidate "$((832+desc_offset))" 99 8; resign_outer; reject
# Inner signatures and typed manifest semantics are still required even when
# the outer AVB signature is valid.
cp cohort.sig saved.sig
flip cohort.sig 0
make_outer; reject
cp saved.sig cohort.sig
jq '.payloads.boot.bytes=4096' manifest.json > changed.json
sign_inner changed.json; make_outer; reject
jq '.cohort_id="22222222222222222222222222222222"' manifest.json > changed.json
sign_inner changed.json; make_outer; reject
sign_inner manifest.json
avbtool make_vbmeta_image --algorithm NONE "${hashes[@]}" "${props[@]}" --output candidate
reject
avbtool make_vbmeta_image --algorithm SHA512_RSA4096 --key key.pem "${hashes[@]}" "${props[@]}" --output candidate
reject
# Regular-file inspection refuses links/special nodes before reading them.
cp valid candidate
ln -s valid linked; reject linked
mkdir parent; cp valid parent/file; ln -s parent linked-parent; reject linked-parent/file
mkfifo fifo; reject fifo
reject /dev/null
reject parent
sha256sum -c <(head -n1 original.sha256; tail -n4 original.sha256) > unchanged.log
[[ $refused == 35 ]]
jq -n --argjson refused "$refused" \
  '{schema_version:1,native_architecture:"aarch64",original_fedora_avbtool_interoperability:true,
    unmodified_upstream_libavb:true,outer_avb_and_inner_pss_verified:true,
    typed_manifest_and_hash_descriptor_sizes_bound:true,maximum_65536_byte_input_passed:true,
    refused_cases:$refused,correctly_signed_invalid_headers_and_descriptors_refused:true,
    descriptor_duplicates_and_unknowns_refused:true,zero_padding_required:true,regular_input_refusals_passed:true,
    dummy_images_only:true,original_boot_inputs_unchanged:true,python_host_tool_only:true,
    boot_payloads_verified:false,rollback_state_verified:false,physical_identity_verified:false,
    operating_system_booted:false,hardware_trust_qualified:false,role_admitted:false,
    storage_or_key_release_executed:false}' > "$report"
