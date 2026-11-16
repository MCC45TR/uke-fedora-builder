#!/usr/bin/bash
# COPR-only transport production from the independently qualified recovered DTS.
set -Eeuo pipefail
[[ $# == 5 && $(uname -m) == aarch64 ]]
producer=$(realpath "$1");inspector=$(realpath "$2");recovered=$(realpath "$3")
qualification=$(realpath "$4");output=$(realpath -m "$5")
[[ ! -e $output && ! -L $output ]]
mkdir "$output"
overlay=$recovered/rebuilt/overlay.dtb
printf '%s  %s\n' "$(jq -er .recovered_overlay_sha256 "$qualification")" "$overlay" | sha256sum -c --strict --quiet -
[[ $(stat -c %s "$overlay") == "$(jq -er .recovered_overlay_bytes "$qualification")" ]]
jq -e '.overlay_and_bases_full_canonical_content_identical and .boot_cpu_headers_preserved and .all_four_applied_canonical_trees_identical and .wrong_model_boot_cpu_and_reserved_memory_refused and (.original_oem_source_reproduction|not)' "$recovered/report.json" >/dev/null
for name in dtbo.img repeat.img;do
 "$producer" create "$output/$name" --page_size=4096 --version=0 --id=0 --rev=0 \
  --custom0=0 --custom1=0 --custom2=0 --custom3=0 "$overlay"
done
cmp "$output/dtbo.img" "$output/repeat.img"
bytes=$(stat -c %s "$overlay")
[[ $(stat -c %s "$output/dtbo.img") == $((bytes+64)) ]]
dd if="$output/dtbo.img" of="$output/payload.dtbo" bs=65536 iflag=skip_bytes,count_bytes skip=64 count="$bytes" status=none
cmp "$overlay" "$output/payload.dtbo"
cat "$recovered/rebuilt/"base-{0,1,2,3}.dtb > "$output/public-bases.img"
bash "$inspector" "$output/dtbo.img" "$output/public-bases.img" > "$output/inventory.json"
jq -e --arg sha "$(sha256sum "$overlay" | cut -d' ' -f1)" --argjson bytes "$bytes" \
 '.dtbo.version==0 and .dtbo.page_size==4096 and (.dtbo.entries|length)==1 and
  .dtbo.bytes==($bytes+64) and .dtbo.entries[0].offset==64 and
  .dtbo.entries[0].bytes==$bytes and .dtbo.entries[0].sha256==$sha and
  .dtbo.entries[0].id==0 and .dtbo.entries[0].revision==0 and
  .dtbo.entries[0].custom==[0,0,0,0] and (.vendor_dtb_section.bases|length)==4' "$output/inventory.json" >/dev/null
jq -n --slurpfile q "$qualification" --slurpfile roundtrip "$recovered/report.json" \
 --slurpfile inventory "$output/inventory.json" --arg sha "$(sha256sum "$output/dtbo.img" | cut -d' ' -f1)" \
 '{schema_version:1,qualification:$q[0],roundtrip:$roundtrip[0],inventory:$inventory[0],dtbo_sha256:$sha,common_dtbo:true,reconstructed_flattened_source:true,original_oem_source_reproduction:false,public_bases_packaged_for_vendor_boot:false,automatic_partition_writes:false,physical_boot_qualified:false}' > "$output/source-cohort.json"
printf 'Recovered DTBO transport has the actual payload length and deterministic v0 header; no partition or vendor_boot write admitted.\n'
