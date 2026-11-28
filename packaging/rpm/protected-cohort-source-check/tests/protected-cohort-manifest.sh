#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Native COPR fixture. All keys, contexts, payload hashes and devices are test inputs.
set -Eeuo pipefail
trap 'printf "UKE_COHORT_MANIFEST_TEST_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
[[ $# == 2 && $(uname -m) == aarch64 && -x $1 && ! -e $2 && ! -L $2 ]]
tool=$(realpath "$1") report=$(realpath -m "$2")
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$repo/src/image/fastboot-singleboot-layout.sh"
# shellcheck disable=SC1091
source "$repo/src/image/rescue-verity-layout.sh"
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
cd "$work"
cohort_id=11111111111111111111111111111111
kernel_release=7.3.3-26-unstable
kernel_source=c7adc996350e3692b4492ab007cad63070dde6c2
hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
make_geometry() {
    local layout verity rescue
    layout=$(fastboot_super_layout "$1")
    rescue=$(jq -er '.partitions[1].bytes' <<< "$layout")
    verity=$(rescue_verity_layout "$rescue")
    jq -n --argjson layout "$layout" --argjson verity "$verity" --argjson userdata "$2" --arg hash "$hash" \
      '{super_bytes:$layout.super_bytes,userdata_bytes:$userdata,logical_block_bytes:4096,
        rescue_start_bytes:$layout.partitions[1].start_byte,rescue_bytes:$layout.partitions[1].bytes,
        swap_start_bytes:$layout.partitions[0].start_byte,swap_bytes:$layout.partitions[0].bytes,
        verity:{data_blocks:$verity.data_blocks,hash_start_blocks:$verity.data_blocks,
          hash_blocks:$verity.hash_blocks,root_sha256:$hash,salt:$hash,container_sha256:$hash}}'
}
# One deliberately synthetic geometry plus the measured 512-GB capacity tuple.
# The synthetic tuple is NOT a measurement of a 256-GB model.
make_geometry 8589934592 34359738368 > synthetic.json
make_geometry 11274289152 497535680512 > measured.json
jq -n --arg id "$cohort_id" --arg release "$kernel_release" --arg source "$kernel_source" --arg hash "$hash" \
  --slurpfile synthetic synthetic.json --slurpfile measured measured.json \
  '{schema_version:1,platform:"xiaomi,uke",cohort_id:$id,kernel_release:$release,kernel_source_commit:$source,
    payloads:{kernel_image:{bytes:4096,sha256:$hash},boot:{bytes:8192,sha256:$hash},
      vendor_boot:{bytes:8192,sha256:$hash},dtbo:{bytes:4096,sha256:$hash},
      super_seed:{bytes:4294967296,sha256:$hash},userdata_seed:{bytes:15032385536,sha256:$hash}},
    geometries:[$synthetic[0],$measured[0]]}' > valid.json
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out key.pem 2> keygen.log
openssl pkey -in key.pem -pubout -out key.pub
openssl pkey -pubin -in key.pub -outform DER -out key.der
pin=$(sha256sum key.der | cut -d ' ' -f1)
context=("$cohort_id" "$kernel_release" "$kernel_source" 11274289152 497535680512 4096
    100663296 100663296 100663296 100663296 25165824 25165824)
sign() {
    { printf 'UKE-PROTECTED-COHORT-v1\n'; cat "$1"; } > candidate
    openssl dgst -sha256 -sign key.pem -sigopt rsa_padding_mode:pss \
      -sigopt rsa_pss_saltlen:32 -sigopt rsa_mgf1_md:sha256 -out candidate.sig candidate
}
run() { timeout 5s "$tool" key.pub "$pin" candidate candidate.sig "$@"; }
sign valid.json
sha256sum valid.json key.pub candidate candidate.sig > original.sha256
run "${context[@]}" > positive.json
jq -e '.signature_verified and .manifest_schema_valid and .kernel_context_matched and .exact_geometry_selected and
  .super_bytes==11274289152 and .userdata_bytes==497535680512 and .rescue_bytes==2255486976 and
  .data_blocks==546352 and .hash_blocks==4304 and (.boot_payloads_verified|not) and
  (.physical_identity_verified|not) and (.avb_signature_verified|not) and (.role_admitted|not) and
  (.snapshot_authenticated|not) and (.hardware_trust_qualified|not)' positive.json >/dev/null
synthetic_context=("${context[@]}")
synthetic_context[3]=8589934592 synthetic_context[4]=34359738368
run "${synthetic_context[@]}" > synthetic-positive.json
jq -e '.exact_geometry_selected and .super_bytes==8589934592 and .userdata_bytes==34359738368' synthetic-positive.json >/dev/null
sha256sum -c original.sha256 > unchanged.log
jq '.geometries=(.geometries[1] as $g|[range(0;8) as $i|$g|.userdata_bytes+=($i*4096)])' valid.json > eight.json
sign eight.json
run "${context[@]}" > eight-positive.json
jq -e '.signature_verified and .exact_geometry_selected' eight-positive.json >/dev/null
refused=0
reject() {
    local status=0
    run "$@" > refused.json 2> refused.log || status=$?
    [[ $status == 1 && ! -s refused.json && $(cat refused.log) == UKE_COHORT_MANIFEST_REJECTED ]]
    ((refused+=1))
}
# Every semantic-invalid candidate below is signed correctly. Signature success
# must not hide schema, cross-field, context or capacity errors.
while IFS= read -r mutation; do
    [[ -n $mutation ]]
    jq "$mutation" valid.json > changed.json
    sign changed.json
    reject "${context[@]}"
done <<'MUTATIONS'
.unexpected=true
.schema_version=2
.schema_version=1.0
.platform="qcom,sm7675"
.cohort_id="22222222222222222222222222222222"
.kernel_release="7.3.3-26"
.kernel_source_commit="1111111111111111111111111111111111111111"
del(.payloads.vendor_boot)
.payloads.unknown={bytes:4096,sha256:.payloads.boot.sha256}
.payloads.boot.bytes=0
.payloads.boot.bytes=100663297
.payloads.boot.bytes=-1
.payloads.boot.bytes="8192"
.payloads.boot.bytes=8192.5
.payloads.kernel_image.bytes=8193
.payloads.dtbo.sha256="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
.payloads.vendor_boot.sha256="0000000000000000000000000000000000000000000000000000000000000000"
.payloads.super_seed.bytes=8589938688
.payloads.userdata_seed.bytes=34359742464
.payloads.super_seed.bytes=4294967297
.geometries=[]
.geometries=(.geometries[0] as $g|[range(0;9)|$g])
.geometries=[.geometries[1],.geometries[0]]
.geometries=[.geometries[0],.geometries[0],.geometries[1]]
.geometries=[.geometries[0]]
.geometries[1].super_bytes=2199023259648
.geometries[1].userdata_bytes=0
.geometries[1].userdata_bytes=-1
.geometries[1].userdata_bytes=497535680512.5
.geometries[1].logical_block_bytes=512
.geometries[1].rescue_start_bytes=0
.geometries[1].swap_start_bytes+=1048576
.geometries[1].swap_bytes-=1048576
.geometries[1].rescue_bytes+=1048576
.geometries[1].verity.data_blocks-=1
.geometries[1].verity.hash_start_blocks=0
.geometries[1].verity.hash_blocks+=1
.geometries[1].verity.root_sha256=""
.geometries[1].verity.container_sha256="abcd"
.geometries[1].verity.salt="xyz"
.geometries[1].verity.ignore_corruption=true
.geometries[0].verity.data_blocks-=1
MUTATIONS
# Duplicate decoded keys, including nested and escaped spellings, cannot be
# silently collapsed by the original JSON parser into a last-value choice.
sed 's/"schema_version": 1/"schema_version": 1, "schema_version": 1/' valid.json > changed.json
sign changed.json; reject "${context[@]}"
sed 's/"platform": "xiaomi,uke"/"platform": "xiaomi,uke", "\\u0070latform": "xiaomi,uke"/' valid.json > changed.json
sign changed.json; reject "${context[@]}"
sed 's/"hash_blocks": 4304/"hash_blocks": 4304, "hash_blocks": 4304/' valid.json > changed.json
sign changed.json; reject "${context[@]}"
{ cat valid.json; printf '{}'; } > changed.json
sign changed.json; reject "${context[@]}"
{ cat valid.json; printf '\000{}'; } > changed.json
sign changed.json; reject "${context[@]}"
{ printf '\357\273\277'; cat valid.json; } > changed.json
sign changed.json; reject "${context[@]}"
{ printf '//comment\n'; cat valid.json; } > changed.json
sign changed.json; reject "${context[@]}"
{ printf '{"x":"\377"}'; } > changed.json
sign changed.json; reject "${context[@]}"
jq '.unexpected=([range(0;20)]|reduce .[] as $x ({}; {x:.}))' valid.json > changed.json
sign changed.json; reject "${context[@]}"
jq '.unexpected=([range(0;600)]|map({x:.}))' valid.json > changed.json
sign changed.json; reject "${context[@]}"
sign valid.json
for index in 0 1 2 3 4 5 6 7 8 9 10 11; do
    changed_context=("${context[@]}")
    case $index in
        0) changed_context[index]=00000000000000000000000000000000;;
        1) changed_context[index]=7.3.3-27-unstable;;
        2) changed_context[index]=1111111111111111111111111111111111111111;;
        3) changed_context[index]=11274285056;;
        4) changed_context[index]=497535676416;;
        5) changed_context[index]=512;;
        *) changed_context[index]=4096;;
    esac
    # A larger signed DTBO must fail if either slot has only 4K capacity.
    if ((index >= 10)); then
        jq '.payloads.dtbo.bytes=8192' valid.json > changed.json
        sign changed.json
    fi
    reject "${changed_context[@]}"
    sign valid.json
done
head -n2 original.sha256 | sha256sum -c - > original-template-unchanged.log
[[ $refused == 64 ]]
jq -n --argjson cases "$refused" \
  '{schema_version:1,native_architecture:"aarch64",real_signature_then_semantic_validation:true,
    measured_512_capacity_tuple_selected:true,synthetic_capacity_selected:true,maximum_eight_geometries_passed:true,
    measured_256gb_geometry:false,
    signed_invalid_cases_refused:$cases,decoded_duplicate_keys_refused:true,context_and_both_slot_limits_checked:true,
    all_listed_geometries_validated:true,original_inputs_unchanged:true,keys_are_ephemeral_fixtures:true,
    boot_payloads_verified:false,physical_identity_verified:false,avb_signature_verified:false,
    role_admitted:false,snapshot_authenticated:false,hardware_trust_qualified:false,
    storage_or_key_release_executed:false}' > "$report"
