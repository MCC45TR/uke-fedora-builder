#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# COPR host only. All generated DTs are public synthetic format fixtures.
set -Eeuo pipefail
export LC_ALL=C
umask 077
[[ $# == 3 ]] || exit 2
producer=$(realpath "$1")
inspector=$(realpath "$2")
receipt=$(realpath -m "$3")
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
cd "$work"
cat > overlay.dts <<'DTS'
/dts-v1/;
/plugin/;
/ {
    model = "Uke DTBO format fixture";
    compatible = "uke,format-fixture";
    qcom,msm-id = <643 65536>;
    qcom,board-id = <8 0>;
    fragment@0 {
        target-path = "/";
        __overlay__ { fixture-node { fixture-value = <42>; }; };
    };
};
DTS
dtc -@ -I dts -O dtb -o overlay.dtbo overlay.dts
cat /dev/null > bases.img
for index in 0 1 2 3; do
    cat > base.dts <<DTS
/dts-v1/;
/ {
    model = "Uke fixture base $index";
    compatible = "uke,format-fixture";
    qcom,msm-id = <$((614+index)) 65536>;
    qcom,board-id = <0 0>;
};
DTS
    dtc -@ -I dts -O dtb -o base.dtb base.dts
    cat base.dtb >> bases.img
done
for output in first.img second.img; do
    "$producer" create "$output" --page_size=4096 --version=0 --id=0 --rev=0 \
        --custom0=0 --custom1=0 --custom2=0 --custom3=0 overlay.dtbo
done
cmp first.img second.img
payload_bytes=$(stat -c %s overlay.dtbo)
[[ $(stat -c %s first.img) == $((payload_bytes+64)) ]]
dd if=first.img of=extracted.dtbo bs=65536 iflag=skip_bytes,count_bytes,fullblock skip=64 count="$payload_bytes" status=none
cmp overlay.dtbo extracted.dtbo
bash "$inspector" first.img bases.img > inventory.json
jq -e --arg sha "$(sha256sum overlay.dtbo | cut -d ' ' -f1)" --argjson bytes "$payload_bytes" \
    '.dtbo.version==0 and .dtbo.page_size==4096 and (.dtbo.entries|length)==1 and
     .dtbo.bytes==($bytes+64) and .dtbo.entries[0].offset==64 and
     .dtbo.entries[0].bytes==$bytes and .dtbo.entries[0].sha256==$sha and
     .dtbo.entries[0].id==0 and .dtbo.entries[0].revision==0 and
     .dtbo.entries[0].custom==[0,0,0,0] and (.vendor_dtb_section.bases|length)==4 and
     .new_dtbo_image_produced==false and .role_or_key_admitted==false' inventory.json >/dev/null
refusals=0
reject() {
    local label=$1 table=$2 bases=$3 status=0
    bash "$inspector" "$table" "$bases" > out.json 2> rejected.log || status=$?
    [[ $status == 1 && ! -s out.json ]] || { printf 'unexpected result: %s (%s)\n' "$label" "$status"; exit 1; }
    refusals=$((refusals+1))
}
reset() { cp first.img bad.img; }
reset
printf '\000\000\000\000' | dd of=bad.img bs=1 seek=0 conv=notrunc status=none
reject magic bad.img bases.img
reset
printf '\000\000\000\100' | dd of=bad.img bs=1 seek=4 conv=notrunc status=none
reject declared-length bad.img bases.img
reset
printf '\000\000\000\001' | dd of=bad.img bs=1 seek=28 conv=notrunc status=none
reject version bad.img bases.img
reset
printf '\000\000\000\000' | dd of=bad.img bs=1 seek=16 conv=notrunc status=none
reject empty-table bad.img bases.img
reset
printf '\000\000\000\040' | dd of=bad.img bs=1 seek=36 conv=notrunc status=none
reject overlap bad.img bases.img
reset
printf '\377\377\377\377' | dd of=bad.img bs=1 seek=32 conv=notrunc status=none
reject payload-bounds bad.img bases.img
reset
printf '\000\000\000\000' | dd of=bad.img bs=1 seek=64 conv=notrunc status=none
reject payload-magic bad.img bases.img
ln -s first.img linked.img
reject symlink linked.img bases.img
cp bases.img bad-bases.img
printf '\000\000\000\000' | dd of=bad-bases.img bs=1 seek=0 conv=notrunc status=none
reject base-magic first.img bad-bases.img
cp bases.img bad-bases.img
truncate -s "$(( $(stat -c %s bases.img)-1 ))" bad-bases.img
reject base-truncation first.img bad-bases.img
[[ $refusals == 10 ]]
# A formatter failure may leave an output; it must never become a candidate.
printf 'invalid FDT fixture' > invalid.dtbo
status=0
"$producer" create invalid.img --page_size=4096 --version=0 invalid.dtbo > invalid.log 2>&1 || status=$?
[[ $status != 0 ]]
jq -n --arg arch "$(uname -m)" --arg tool_sha "$(sha256sum "$producer" | cut -d ' ' -f1)" --argjson refusals "$refusals" \
    '{schema_version:1,native_architecture:$arch,original_upstream_native_formatter:true,formatter_sha256:$tool_sha,public_synthetic_inputs_only:true,version_zero_layout_verified:true,payload_bytes_preserved:true,repeat_output_identical:true,base_variants_inventoried:4,malformed_inventory_cases_refused:$refusals,invalid_fdt_formatter_refused:true,python_executed:false,installed_firmware_input_used:false,new_uke_image_produced:false,boot_or_hardware_qualified:false,role_or_key_admitted:false}' > "$receipt"
