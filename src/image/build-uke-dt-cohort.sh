#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# COPR-only source compilation. No private firmware or device access.
set -Eeuo pipefail
export LC_ALL=C
umask 077
fail() { printf 'UKE_DT_SOURCE_REJECTED: %s\n' "$*" >&2; exit 1; }
[[ $# == 5 ]] || fail 'expected OEM source directory, pin record, mkdtimg, fdtoverlaymerge and new output directory'
[[ $(uname -m) == aarch64 ]] || fail 'compile only on the native COPR target'
source_root=$(realpath "$1")
pins=$(realpath "$2")
formatter=$(realpath "$3")
merger=$(realpath "$4")
output=$(realpath -m "$5")
[[ -d $source_root && -f $pins && ! -e $output ]] || fail 'invalid inputs or existing output'
for tool in gcc dtc fdtget fdtput fdtoverlay jq sha256sum stat realpath timeout; do
 command -v "$tool" >/dev/null || fail "missing original host tool: $tool"
done
[[ -x $formatter && -x $merger ]]
[[ $(df -Pm "$(dirname "$output")" | awk 'NR==2{print $4}') -gt 512 ]] || fail 'insufficient storage reserve'
jq -e '.schema_version==1 and .source_file_count==(.inputs|length) and .source_file_count<=512 and .source_bytes<=16777216 and (.roots|length)==9 and .base_order==[614,632,643,642] and (.storage_capacity_selects_dtbo|not)' "$pins" >/dev/null
verify_sources() {
 local kind owner path digest target file actual
 while IFS=$'\t' read -r kind owner path digest target; do
  [[ $owner =~ ^[a-z_]+$ && $path =~ ^[A-Za-z0-9_.,+/-]+$ && $path != /* && $path != *..* && $digest =~ ^[a-f0-9]{64}$ ]] || fail 'invalid source-pin path'
  file=$source_root/$owner/$path
  case $kind in
   regular)
    [[ -f $file && ! -L $file ]] || fail "missing regular input: $owner/$path"
    actual=$(sha256sum "$file" | cut -d ' ' -f1);;
   symlink)
    [[ -L $file && $(readlink "$file") == "$target" ]] || fail 'changed source symlink'
    [[ $(realpath -e "$file") == "$source_root/$owner/"* ]] || fail 'escaping source symlink'
    actual=$(printf '%s' "$target" | sha256sum | cut -d ' ' -f1);;
   *) fail 'unknown source-pin type';;
  esac
  [[ $actual == "$digest" ]] || fail "source hash mismatch: $owner/$path"
 done < <(jq -r '.inputs[]|[.kind,.owner,.path,.sha256,(.link_target//"-")]|@tsv' "$pins")
}
verify_sources
mkdir -p "$output"/{preprocessed,compiled,base,applied,logs}
source_pin_sha=$(sha256sum "$pins" | cut -d ' ' -f1)
compile() {
 local owner=$1 path=$2 target=$3
 local -a includes=( -I "$source_root/kernel/include" )
 [[ $owner != camera ]] || includes+=( -I "$source_root/camera_kernel" )
 # Match the OEM CPP contract, preserving symbols for later layer composition.
 (ulimit -Sv 262144; ulimit -Sf 16384; timeout 30s gcc -E -P -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
  "${includes[@]}" -MMD -MF "$output/preprocessed/$target.d" -o "$output/preprocessed/$target.dts" "$source_root/$owner/$path")
 (ulimit -Sv 262144; ulimit -Sf 16384; timeout 30s dtc -@ -I dts -O dtb -b 0 \
  -i "$(dirname "$source_root/$owner/$path")" -Wno-unit_address_vs_reg -Wno-avoid_unnecessary_addr_size \
  -Wno-alias_paths -Wno-graph_child_address -Wno-simple_bus_reg -Wno-unique_unit_address \
  -Wno-interrupt_provider -o "$output/compiled/$target.dtb" "$output/preprocessed/$target.dts") \
  2> "$output/logs/$target.dtc.log" || { tail -n 50 "$output/logs/$target.dtc.log" >&2; fail "DTC failed: $target"; }
}
while IFS=$'\t' read -r owner path target; do
 [[ $owner =~ ^[a-z_]+$ && $target =~ ^[a-z0-9-]+$ ]]
 compile "$owner" "$path" "$target"
done < <(jq -r '.roots[]|[.owner,.path,.target]|@tsv' "$pins")

# An update receipt, not a trust anchor: it identifies the overlay that reached
# Linux after boot. It carries no key authority or hardware configuration.
printf '/dts-v1/;\n/plugin/;\n/ { fragment@0 { target-path = "/chosen"; __overlay__ { uke,dtbo-source = "%s"; }; }; };\n' \
 "$source_pin_sha" > "$output/source-marker.dts"
dtc -@ -I dts -O dtb -o "$output/compiled/source-marker.dtb" "$output/source-marker.dts"

for repeat in dtbo-payload.dtbo dtbo-payload-repeat.dtbo; do
 (ulimit -Sv 262144; ulimit -Sf 16384; timeout 30s "$merger" -i "$output/compiled/uke-board.dtb" \
  "$output/compiled/uke-camera.dtb" "$output/compiled/uke-display.dtb" "$output/compiled/source-marker.dtb" -o "$output/$repeat")
done
cmp "$output/dtbo-payload.dtbo" "$output/dtbo-payload-repeat.dtbo"
[[ $(fdtget -t s "$output/dtbo-payload.dtbo" / model) == 'Qualcomm Technologies, Inc. Uke based on SM8635' ]]
[[ $(fdtget -t s "$output/dtbo-payload.dtbo" / compatible) == 'qcom,cliffs-mtp qcom,cliffs qcom,mtp' ]]
[[ $(fdtget -t u "$output/dtbo-payload.dtbo" / qcom,board-id) == '8 0' ]]
[[ $(fdtget -t u "$output/dtbo-payload.dtbo" / xiaomi,miboard-id) == '11 0' ]]
[[ $(fdtget -t u "$output/dtbo-payload.dtbo" / qcom,msm-id | xargs) == '614 65536 632 65536 642 65536 643 65536' ]]

: > "$output/vendor-dtbs.img"
while IFS=$'\t' read -r target expected_msm; do
 raw=$output/compiled/$target.dtb
 base=$output/base/$target.dtb
 fdtoverlay -i "$raw" -o "$base" "$output/compiled/camera-platform.dtb" "$output/compiled/display-platform.dtb"
 [[ $(fdtget -t u "$base" / qcom,msm-id) == "$expected_msm 65536" ]]
 [[ $(fdtget -t u "$base" / qcom,board-id) == '0 0' ]]
 [[ $(fdtget -t s "$base" / model) == "$(fdtget -t s "$raw" / model)" ]]
 [[ $(fdtget -t s "$base" / compatible) == "$(fdtget -t s "$raw" / compatible)" ]]
 [[ $(fdtget -t x "$base" /memory reg) == "$(fdtget -t x "$raw" /memory reg)" ]]
 fdtoverlay -i "$base" -o "$output/applied/$target.dtb" "$output/dtbo-payload.dtbo"
 [[ $(fdtget -t s "$output/applied/$target.dtb" /chosen uke,dtbo-source) == "$source_pin_sha" ]]
 # The full selected graph must resolve against each supported base.
 dtc -q -I dtb -O dts -o /dev/null "$output/applied/$target.dtb"
 cat "$base" >> "$output/vendor-dtbs.img"
done < <(jq -r '.roots[]|select(.kind=="base")|[.target,(.msm_id|tostring)]|@tsv' "$pins")

# Prove that the omitted platform camera layer is a real graph dependency.
fdtoverlay -i "$output/compiled/cliffs7p.dtb" -o "$output/applied/missing-camera-platform.dtb" "$output/compiled/display-platform.dtb"
if fdtoverlay -i "$output/applied/missing-camera-platform.dtb" -o "$output/applied/invalid.dtb" "$output/dtbo-payload.dtbo" > "$output/logs/missing-camera.log" 2>&1; then
 fail 'source selection accepted a missing platform camera layer'
fi
"$formatter" create "$output/dtbo.img" --page_size=4096 --version=0 --id=0 --rev=0 "$output/dtbo-payload.dtbo"
(( $(stat -c %s "$output/dtbo.img") <= 25165824 )) || fail 'common DTBO exceeds either slot'
(( $(stat -c %s "$output/vendor-dtbs.img") <= 16777216 )) || fail 'base section exceeds reviewed bound'
verify_sources
jq -n --arg dtbo "$(sha256sum "$output/dtbo.img" | cut -d ' ' -f1)" \
 --arg bases "$(sha256sum "$output/vendor-dtbs.img" | cut -d ' ' -f1)" --arg pins "$(sha256sum "$pins" | cut -d ' ' -f1)" \
 --argjson dtbo_bytes "$(stat -c %s "$output/dtbo.img")" --argjson base_bytes "$(stat -c %s "$output/vendor-dtbs.img")" \
 '{schema_version:1,architecture:"aarch64",source_pins_sha256:$pins,dtbo_sha256:$dtbo,dtbo_bytes:$dtbo_bytes,vendor_dtb_section_sha256:$bases,vendor_dtb_section_bytes:$base_bytes,base_count:4,base_order:[614,632,643,642],source_inputs_unchanged:true,common_dtbo:true,board_camera_display_layers:true,overlay_applies_to_all_bases:true,source_marker_preserved_in_all_bases:true,source_marker_is_not_a_trust_anchor:true,repeat_merge_identical:true,missing_camera_platform_refused:true,original_base_memory_placeholder_preserved:true,original_base_identity_preserved:true,existing_kernel_transform_preapplied:false,vendor_boot_image_produced:false,bootloader_live_fixups_tested:false,kernel_source_compatibility_qualified:false,boot_qualified:false,hardware_qualified:false,role_or_key_admitted:false}' > "$output/source-cohort.json"
