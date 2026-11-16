#!/usr/bin/bash
# COPR only. This recovers flattened-source text, not missing OEM source layers.
set -Eeuo pipefail
[[ $# == 3 && $(uname -m) == aarch64 ]]
inputs=$(realpath "$1");pins=$(realpath "$2");output=$(realpath -m "$3")
[[ ! -e $output && ! -L $output ]]
mkdir -p "$output/"{source,rebuilt,applied,logs}
while IFS=$'\t' read -r name bytes hash;do
 [[ $name =~ ^(dtbo[.]img|base-[0-3][.]dtb)$ && -f $inputs/$name && ! -L $inputs/$name ]]
 [[ $(stat -c %s "$inputs/$name") == "$bytes" ]]
 printf '%s  %s\n' "$hash" "$inputs/$name" | sha256sum -c --strict --quiet -
done < <(jq -r '.inputs[]|[.name,(.bytes|tostring),.sha256]|@tsv' "$pins")
dd if="$inputs/dtbo.img" of="$output/original-overlay.dtbo" bs=65536 iflag=skip_bytes,count_bytes skip=64 count=591793 status=none
printf '%s  %s\n' "$(jq -er .overlay_sha256 "$pins")" "$output/original-overlay.dtbo" | sha256sum -c --strict --quiet -
for name in overlay base-0 base-1 base-2 base-3;do
 input=$inputs/$name.dtb
 [[ $name != overlay ]] || input=$output/original-overlay.dtbo
 dtc -I dtb -O dts -o "$output/source/$name.dts" "$input" 2> "$output/logs/$name-decompile.log"
 dtc -@ -I dts -O dtb -o "$output/rebuilt/$name.dtb" "$output/source/$name.dts" 2> "$output/logs/$name-compile.log"
 if ! cmp "$input" "$output/rebuilt/$name.dtb";then
  stat -c '%n bytes=%s' "$input" "$output/rebuilt/$name.dtb"
  dtc -I dtb -O dts -o "$output/logs/$name-rebuilt.dts" "$output/rebuilt/$name.dtb" 2>/dev/null
  diff -u "$output/source/$name.dts" "$output/logs/$name-rebuilt.dts" | head -n 60 || :
  printf 'Byte-exact source recovery refused for %s; no payload admitted.\n' "$name" >&2
  exit 1
 fi
done
# Reuse only the pinned v0 table header and transport padding. The payload
# comes from native DTS compilation and must reproduce every original byte.
cp "$inputs/dtbo.img" "$output/rebuilt/dtbo.img"
dd if="$output/rebuilt/overlay.dtb" of="$output/rebuilt/dtbo.img" bs=65536 oflag=seek_bytes seek=64 conv=notrunc status=none
cmp "$inputs/dtbo.img" "$output/rebuilt/dtbo.img"
for index in 0 1 2 3;do
 fdtoverlay -i "$inputs/base-$index.dtb" -o "$output/applied/reference-$index.dtb" "$output/original-overlay.dtbo"
 fdtoverlay -i "$output/rebuilt/base-$index.dtb" -o "$output/applied/rebuilt-$index.dtb" "$output/rebuilt/overlay.dtb"
 cmp "$output/applied/reference-$index.dtb" "$output/applied/rebuilt-$index.dtb"
done
rpm -q dtc libfdt glibc > "$output/distribution-tools.txt"
jq -n --slurpfile reference "$pins" '{schema_version:1,scope:"Native byte-exact recovery from public flattened references only",reference:$reference[0],base_count:4,overlay_and_bases_recompiled_byte_identically:true,dtbo_transport_byte_identical:true,all_four_applied_graphs_byte_identical:true,original_oem_source_reproduction:false,installed_vendor_boot_replacement_qualified:false,physical_update_qualified:false}' > "$output/report.json"
(cd "$output";find source rebuilt -type f -print0 | sort -z | xargs -0 sha256sum > output.sha256;sha256sum applied/*.dtb > applied.sha256)
printf 'Recovered public DTS recompiles byte-identically with the original Fedora DTC; no original-source, installed-base substitution or physical admission.\n'
