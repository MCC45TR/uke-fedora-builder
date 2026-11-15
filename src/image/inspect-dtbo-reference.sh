#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Host-only, regular-file inventory. No DTS compilation, merging or admission.
set -Eeuo pipefail
export LC_ALL=C
umask 077
fail() { printf 'UKE_DTBO_REFERENCE_REJECTED: %s\n' "$*" >&2; exit 1; }
[[ $# == 2 ]] || fail 'expected an exact DTBO v0 prefix and a vendor_boot DTB section'
for tool in od stat sha256sum dd jq dtc fdtget mktemp df; do
    command -v "$tool" >/dev/null || fail "missing host tool: $tool"
done
for input in "$@"; do
    [[ -f $input && ! -L $input ]] || fail 'only regular, non-symlink files are accepted'
done
exec 3< "$1"
exec 4< "$2"
table=/proc/self/fd/3
bases=/proc/self/fd/4
table_bytes=$(stat -Lc %s "$table")
base_bytes=$(stat -Lc %s "$bases")
(( table_bytes >= 64 && table_bytes <= 33554432 && base_bytes >= 40 && base_bytes <= 16777216 )) || fail 'input exceeds inspection bounds'
table_sha=$(sha256sum "$table" | cut -d ' ' -f1)
base_sha=$(sha256sum "$bases" | cut -d ' ' -f1)
u32() { od -An -v --endian=big -tu4 -j "$2" -N4 "$1" | tr -d '[:space:]'; }
[[ $(u32 "$table" 0) == 3619138334 ]] || fail 'invalid DT table magic'
[[ $(u32 "$table" 4) == "$table_bytes" ]] || fail 'input must end at the declared prefix, without an AVB footer or padding'
[[ $(u32 "$table" 8) == 32 && $(u32 "$table" 12) == 32 && $(u32 "$table" 28) == 0 ]] || fail 'only reviewed v0 headers and entries are supported'
count=$(u32 "$table" 16)
offset=$(u32 "$table" 20)
page=$(u32 "$table" 24)
(( count > 0 && count <= 16 && offset >= 32 && offset <= table_bytes && count*32 <= table_bytes-offset && page == 4096 )) || fail 'unsupported table geometry'
tmp_root=${TMPDIR:-/tmp}
available=$(df -B1 --output=avail "$tmp_root" | tail -n 1 | tr -d '[:space:]')
(( available >= table_bytes+base_bytes+268435456 )) || fail 'insufficient temporary-space reserve'
work=$(mktemp -d "$tmp_root/uke-dtbo-reference.XXXXXXXX")
cleanup() { find "$work" -depth -delete; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
hash() { sha256sum "$1" | cut -d ' ' -f1; }
cells() { fdtget -t u "$1" / "$2" | jq -R 'split(" ")|map(select(length>0)|tonumber)'; }
identity() {
    # Decompile to /dev/null to walk the FDT, without producing a new binary.
    dtc -q -I dtb -O dts -o /dev/null "$1" 2>/dev/null || fail 'malformed FDT'
    local model compatible msm board
    model=$(fdtget -t s "$1" / model) || fail 'missing model'
    compatible=$(fdtget -t s "$1" / compatible) || fail 'missing compatible'
    msm=$(cells "$1" qcom,msm-id) || fail 'missing msm-id'
    board=$(cells "$1" qcom,board-id) || fail 'missing board-id'
    jq -cn --arg model "$model" --arg compatible "$compatible" --argjson msm "$msm" --argjson board "$board" \
        '{model:$model,compatible:($compatible|split(" ")),msm_id_cells:$msm,board_id_cells:$board}'
}
entries='[]'
previous_end=$((offset+count*32))
for ((index=0; index<count; ++index)); do
    entry=$((offset+index*32))
    bytes=$(u32 "$table" "$entry")
    start=$(u32 "$table" "$((entry+4))")
    (( bytes >= 40 && start >= previous_end && start <= table_bytes && bytes <= table_bytes-start )) || fail 'overlapping or truncated DT table payload'
    dd if="$table" of="$work/overlay.dtbo" bs=65536 iflag=skip_bytes,count_bytes,fullblock skip="$start" count="$bytes" status=none
    [[ $(u32 "$work/overlay.dtbo" 0) == 3490578157 && $(u32 "$work/overlay.dtbo" 4) == "$bytes" ]] || fail 'DT table payload is not an exact FDT'
    values=$(od -An -v --endian=big -tu4 -j "$((entry+8))" -N24 "$table" | jq -Rs 'split("\n")|join(" ")|split(" ")|map(select(length>0)|tonumber)')
    item=$(jq -cn --argjson index "$index" --argjson bytes "$bytes" --argjson start "$start" --argjson values "$values" --arg sha "$(hash "$work/overlay.dtbo")" --argjson identity "$(identity "$work/overlay.dtbo")" \
        '{index:$index,bytes:$bytes,offset:$start,id:$values[0],revision:$values[1],custom:$values[2:6],sha256:$sha,root:$identity}')
    entries=$(jq -cn --argjson prior "$entries" --argjson item "$item" '$prior+[$item]')
    previous_end=$((start+bytes))
done
cursor=0
index=0
base_entries='[]'
while (( cursor < base_bytes )); do
    (( index < 16 && base_bytes-cursor >= 40 )) || fail 'invalid concatenated DTB section'
    [[ $(u32 "$bases" "$cursor") == 3490578157 ]] || fail 'invalid base DTB magic'
    bytes=$(u32 "$bases" "$((cursor+4))")
    (( bytes >= 40 && bytes <= base_bytes-cursor )) || fail 'truncated base DTB'
    dd if="$bases" of="$work/base.dtb" bs=65536 iflag=skip_bytes,count_bytes,fullblock skip="$cursor" count="$bytes" status=none
    item=$(jq -cn --argjson index "$index" --argjson bytes "$bytes" --argjson start "$cursor" --arg sha "$(hash "$work/base.dtb")" --argjson identity "$(identity "$work/base.dtb")" \
        '{index:$index,bytes:$bytes,offset:$start,sha256:$sha,root:$identity}')
    base_entries=$(jq -cn --argjson prior "$base_entries" --argjson item "$item" '$prior+[$item]')
    cursor=$((cursor+bytes)); index=$((index+1))
done
[[ $(stat -Lc %s "$table") == "$table_bytes" && $(hash "$table") == "$table_sha" && $(stat -Lc %s "$bases") == "$base_bytes" && $(hash "$bases") == "$base_sha" ]] || fail 'input changed during inspection'
jq -n --arg table_sha "$table_sha" --arg base_sha "$base_sha" --argjson table_bytes "$table_bytes" --argjson base_bytes "$base_bytes" --argjson entries "$entries" --argjson base_entries "$base_entries" \
    '{schema_version:1,scope:"host-regular-file-reference-inspection",dtbo:{version:0,page_size:4096,bytes:$table_bytes,sha256:$table_sha,entries:$entries},vendor_dtb_section:{bytes:$base_bytes,sha256:$base_sha,bases:$base_entries},source_compiled:false,new_dtbo_image_produced:false,overlays_merged:false,bootloader_fixups_present:false,selected_base_authenticated:false,physical_ownership_verified:false,boot_or_hardware_qualified:false,role_or_key_admitted:false}'
