#!/usr/bin/bash
# COPR only. This recovers flattened-source text, not missing OEM source layers.
set -Eeuo pipefail
[[ $# == 3 && $(uname -m) == aarch64 ]]
inputs=$(realpath "$1");pins=$(realpath "$2");output=$(realpath -m "$3")
[[ ! -e $output && ! -L $output ]]
mkdir -p "$output/"{source,rebuilt,applied,logs}
phase=inputs
detail_log=
report_failure() {
 local status=$1 line=$2
 printf 'DT reference check failed: phase=%s line=%s status=%s\n' "$phase" "$line" "$status" >&2
 if [[ -n $detail_log && -f $detail_log ]];then tail -n 16 "$detail_log" >&2;fi
 exit "$status"
}
trap 'report_failure "$?" "$LINENO"' ERR
boot_cpu() { od -An -v -tx1 -j28 -N4 "$1" | tr -d ' \n'; }
same_content() {
 dtc -I dtb -O dts -o "$output/logs/check-left.dts" "$1" 2>/dev/null || return
 dtc -I dtb -O dts -o "$output/logs/check-right.dts" "$2" 2>/dev/null || return
 cmp -s "$output/logs/check-left.dts" "$output/logs/check-right.dts" || return
 [[ $(boot_cpu "$1") == "$(boot_cpu "$2")" ]]
}
printf '[]\n' > "$output/observations.json"
while IFS=$'\t' read -r name bytes hash;do
 [[ $name =~ ^(dtbo[.]img|base-[0-3][.]dtb)$ && -f $inputs/$name && ! -L $inputs/$name ]]
 [[ $(stat -c %s "$inputs/$name") == "$bytes" ]]
 printf '%s  %s\n' "$hash" "$inputs/$name" | sha256sum -c --strict --quiet -
done < <(jq -r '.inputs[]|[.name,(.bytes|tostring),.sha256]|@tsv' "$pins")
dd if="$inputs/dtbo.img" of="$output/original-overlay.dtbo" bs=65536 iflag=skip_bytes,count_bytes skip=64 count=591793 status=none
printf '%s  %s\n' "$(jq -er .overlay_sha256 "$pins")" "$output/original-overlay.dtbo" | sha256sum -c --strict --quiet -
for name in overlay base-0 base-1 base-2 base-3;do
 phase=recover-$name
 input=$inputs/$name.dtb
 [[ $name != overlay ]] || input=$output/original-overlay.dtbo
 dtc -I dtb -O dts -o "$output/source/$name.dts" "$input" 2> "$output/logs/$name-decompile.log"
 cpu_hex=$(boot_cpu "$input")
 detail_log=$output/logs/$name-compile.log
 dtc -@ -b "$((16#$cpu_hex))" -I dts -O dtb -o "$output/rebuilt/$name.dtb" "$output/source/$name.dts" 2> "$detail_log"
 if ! same_content "$input" "$output/rebuilt/$name.dtb";then
  stat -c '%n bytes=%s' "$input" "$output/rebuilt/$name.dtb"
  diff -u "$output/logs/check-left.dts" "$output/logs/check-right.dts" | head -n 60 || :
  printf 'Full canonical content recovery refused for %s; no payload admitted.\n' "$name" >&2
  exit 1
 fi
 identical=false;cmp -s "$input" "$output/rebuilt/$name.dtb" && identical=true
 jq --arg name "$name" --argjson same "$identical" --argjson before "$(stat -c %s "$input")" \
  --argjson after "$(stat -c %s "$output/rebuilt/$name.dtb")" \
  '. + [{name:$name,byte_identical:$same,original_bytes:$before,rebuilt_bytes:$after,full_canonical_tree_and_boot_cpu_identical:true}]' \
  "$output/observations.json" > "$output/next-observations.json"
 mv "$output/next-observations.json" "$output/observations.json"
done
# Layout bytes need not reproduce DTC's old padding/NOP/string allocation.
# Produce no DTBO transport here; a separately qualified formatter must set
# its actual new FDT length, table size and padding for a runtime candidate.
for index in 0 1 2 3;do
 phase=applied-$index
 detail_log=
 fdtoverlay -i "$inputs/base-$index.dtb" -o "$output/applied/reference-$index.dtb" "$output/original-overlay.dtbo"
 fdtoverlay -i "$output/rebuilt/base-$index.dtb" -o "$output/applied/rebuilt-$index.dtb" "$output/rebuilt/overlay.dtb"
 same_content "$output/applied/reference-$index.dtb" "$output/applied/rebuilt-$index.dtb"
done
phase=negative-model
detail_log=$output/logs/negative-model.log
sed 's/model = "[^"]*";/model = "Uke invalid model fixture";/' "$output/source/overlay.dts" > "$output/bad-model.dts"
dtc -@ -I dts -O dtb -o "$output/bad-model.dtb" "$output/bad-model.dts" 2> "$detail_log"
if same_content "$output/original-overlay.dtbo" "$output/bad-model.dtb";then exit 1;fi
cpu_hex=$(boot_cpu "$output/original-overlay.dtbo")
phase=negative-boot-cpu
detail_log=$output/logs/negative-boot-cpu.log
dtc -@ -b "$((16#$cpu_hex ^ 1))" -I dts -O dtb -o "$output/bad-cpu.dtb" "$output/source/overlay.dts" 2> "$detail_log"
if same_content "$output/original-overlay.dtbo" "$output/bad-cpu.dtb";then exit 1;fi
phase=negative-reservation
detail_log=$output/logs/negative-reservation.log
# DTS version and optional /plugin/ headers precede all memory reservations.
awk '/^\/ \{$/{print "/memreserve/ 0x10 0x10;";roots++}{print}END{if(roots!=1)exit 1}' "$output/source/overlay.dts" > "$output/bad-reserve.dts"
dtc -@ -I dts -O dtb -o "$output/bad-reserve.dtb" "$output/bad-reserve.dts" 2> "$detail_log"
if same_content "$output/original-overlay.dtbo" "$output/bad-reserve.dtb";then exit 1;fi
phase=report
detail_log=
rpm -q dtc libfdt glibc > "$output/distribution-tools.txt"
jq -n --slurpfile reference "$pins" --slurpfile observations "$output/observations.json" '{schema_version:1,scope:"Native full-content DTS recovery from public flattened references only",reference:$reference[0],base_count:4,overlay_and_bases_full_canonical_content_identical:true,boot_cpu_headers_preserved:true,all_four_applied_canonical_trees_identical:true,layout_observations:$observations[0],wrong_model_boot_cpu_and_reserved_memory_refused:true,dtbo_transport_produced:false,original_oem_source_reproduction:false,installed_vendor_boot_replacement_qualified:false,physical_update_qualified:false}' > "$output/report.json"
(cd "$output";find source rebuilt -type f -print0 | sort -z | xargs -0 sha256sum > output.sha256;sha256sum applied/*.dtb > applied.sha256)
printf 'Recovered DTS retains complete public tree/property content, reservations and boot CPU; wrong model/CPU/reservation refused. Layout bytes reported separately; no runtime transport or physical admission.\n'
