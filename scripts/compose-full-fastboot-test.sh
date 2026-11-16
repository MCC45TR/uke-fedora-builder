#!/usr/bin/bash
# Compose local test inputs; no hardware access or compilation.
set -Eeuo pipefail
export LC_ALL=C
umask 077
fail(){ printf 'UKE_FULL_TEST_REJECTED: %s\n' "$*" >&2;exit 1; }
[[ $# == 3 && $3 =~ ^[0-9]{6}$ ]] || fail 'usage: compose-full-fastboot-test.sh PRIVATE_COMPONENTS_JSON NEW_OUTPUT_DIRECTORY DDMMYY'
[[ $(uname -m) == x86_64 || $(uname -m) == aarch64 ]] || fail 'little-endian x86_64 or AArch64 host required'
contract=$(realpath "$1");output=$(realpath -m "$2");day=$3
[[ -f $contract && ! -L $1 && ! -e $output && ! -L $output && -d ${output%/*} ]] || fail 'regular contract and new output required'
[[ $(date -u -d "20${day:4:2}-${day:2:2}-${day:0:2}" +%d%m%y) == "$day" ]] || fail 'invalid date'
jq -e '.schema_version==1 and (.desktop_directory|type=="string") and
 (.super_directory|type=="string") and (.boot_directory|type=="string") and
 all(.dtbo,.vendor_boot;(.file|type=="string") and (.sha256|test("^[a-f0-9]{64}$")))' "$contract" > /dev/null || fail 'invalid component contract'
desktop=$(realpath "$(jq -er .desktop_directory "$contract")")
super=$(realpath "$(jq -er .super_directory "$contract")")
boots=$(realpath "$(jq -er .boot_directory "$contract")")
dtbo=$(realpath "$(jq -er .dtbo.file "$contract")")
vendor=$(realpath "$(jq -er .vendor_boot.file "$contract")")
for file in "$desktop/manifest.json" "$desktop/userdata.img" "$super/super-seed.json" "$super/super-composition.json" "$super/rescue-console-readback.json" "$super/super.img" "$super/SHA256SUMS" "$boots/SHA256SUMS" "$boots/boot_a.img" "$boots/boot_b.img" "$boots/rescue-boot.img" "$dtbo" "$vendor";do
 [[ -f $file && ! -L $file ]] || fail "missing regular input: ${file##*/}"
done
jq -e '.artifact_kind=="full-singleboot-desktop-input" and .device=="uke" and .filesystem=="ext4" and
 .control_super_and_swap_capabilities_verified and .setup_cdc_reboot_capability_verified and
 .automatic_kernel_activation and .userdata_automatic_activation and
 (.root_kernel_image_sha256|test("^[a-f0-9]{64}$")) and
 .post_policy_independent_readback and .post_policy_ext4_check and .post_policy_independent_aosp_roundtrip and
 (.credentials_included|not) and (.device_private_data_included|not)' "$desktop/manifest.json" > /dev/null || fail 'desktop lacks native interfaces or fresh-test policy qualification'
release=$(jq -er .kernel_release "$desktop/manifest.json")
commit=$(jq -er .kernel_source_commit "$desktop/manifest.json")
jq -e --arg release "$release" --arg commit "$commit" '
 .rescue_input.kernel.kernel_release==$release and .rescue_input.kernel.kernel_source_commit==$commit and
 .rescue_input.signatures_verified and .rescue_input.python_payload_audited and .rescue_input.ext4_readback_verified and
 .seed_layout.phase=="seed" and .seed_layout.super_bytes==4294967296 and
 (.seed_layout.partition_table_changes|not) and (.seed_layout.opt_partition|not) and
 ([.seed_layout.partitions[]|{name,percentage}]|sort_by(.name))==[{name:"system_a",percentage:80},{name:"system_b",percentage:20}]' "$super/super-seed.json" > /dev/null || fail 'rescue kernel cohort or super layout differs'
jq -e --arg hash "$(jq -er .rescue_raw_sha256 "$super/super-composition.json")" \
 --arg source_hash "$(jq -er .rescue_input.sha256 "$super/super-seed.json")" \
 --arg super_hash "$(sha256sum "$super/super.img" | cut -d' ' -f1)" '
 .schema_version==1 and .artifact_kind=="uke-rescue-console-source-readback" and
 .rescue_raw_sha256==$hash and .source_rescue_raw_sha256==$source_hash and
 .seed_super_sparse_sha256==$super_hash and .source_scripts_verified and .unit_files_verified and
 .locked_root_verified and .human_account_absent and .activation_links_verified and
 .inspection_read_only' "$super/rescue-console-readback.json" > /dev/null || fail 'rescue lacks the independent console-source readback'
[[ $(jq -Sc .layout "$super/super-composition.json") == "$(jq -Sc .seed_layout "$super/super-seed.json")" &&
 $(jq -er .super_sparse_sha256 "$super/super-composition.json") == "$(sha256sum "$super/super.img" | cut -d' ' -f1)" ]] || fail 'super composition and payload differ'
[[ $(sha256sum "$desktop/userdata.img" | cut -d' ' -f1) == "$(jq -er .root_sparse_sha256 "$desktop/manifest.json")" ]] || fail 'desktop payload hash differs'
[[ $(sha256sum "$dtbo" | cut -d' ' -f1) == "$(jq -er .dtbo.sha256 "$contract")" ]] || fail 'DTBO hash differs'
[[ $(sha256sum "$vendor" | cut -d' ' -f1) == "$(jq -er .vendor_boot.sha256 "$contract")" ]] || fail 'vendor_boot hash differs'
[[ $(wc -l < "$boots/SHA256SUMS") == 3 ]] || fail 'unexpected boot receipt'
(cd "$boots";sha256sum -c --strict SHA256SUMS)
kernel_hash=$(jq -er .root_kernel_image_sha256 "$desktop/manifest.json")
for name in boot_a boot_b rescue-boot;do
 image=$boots/$name.img
 [[ $(dd if="$image" bs=8 count=1 status=none) == 'ANDROID!' &&
    $(od -An -tu4 -j40 -N4 "$image" | xargs) == 4 &&
    $(od -An -tu4 -j12 -N4 "$image" | xargs) == 0 &&
    $(od -An -tu4 -j1580 -N4 "$image" | xargs) == 0 ]] || fail 'noncanonical v4 boot header'
 kernel_bytes=$(od -An -tu4 -j8 -N4 "$image" | xargs)
 ((kernel_bytes>0&&kernel_bytes<=100663296-4194304-4096)) || fail 'embedded Image lacks the required capacity reserve'
 [[ $(dd if="$image" bs=1048576 iflag=skip_bytes,count_bytes skip=4096 count="$kernel_bytes" status=none | sha256sum | cut -d' ' -f1) == "$kernel_hash" ]] || fail 'boot and desktop kernels differ'
 cmdline=$(dd if="$image" bs=1 skip=44 count=1536 status=none | tr -d '\0')
 case $name in
  boot_a) expected_cmdline='senemos.root=userdata senemos.super=seed4-v1 androidboot.slot_suffix=_a';;
  boot_b) expected_cmdline='senemos.root=userdata senemos.super=seed4-v1 androidboot.slot_suffix=_b';;
  rescue-boot) expected_cmdline='senemos.root=userdata senemos.role=rescue';;
 esac
 [[ $cmdline == "$expected_cmdline" ]] || fail 'boot destination or root profile differs'
done
expected_super=$(awk '$2=="./super.img"||$2=="super.img"{print $1;n++} END{if(n!=1)exit 1}' "$super/SHA256SUMS")
[[ $expected_super =~ ^[a-f0-9]{64}$ && $(sha256sum "$super/super.img" | cut -d' ' -f1) == "$expected_super" ]] || fail 'super payload hash differs'
[[ $(stat -c %s "$boots/boot_a.img") == 100663296 && $(stat -c %s "$boots/boot_b.img") == 100663296 &&
 $(stat -c %s "$boots/rescue-boot.img") == 100663296 && $(stat -c %s "$vendor") == 100663296 ]] || fail 'unexpected measured boot capacity'
total=$(du -cb --apparent-size "$desktop/userdata.img" "$super/super.img" "$boots/boot_a.img" "$boots/boot_b.img" "$boots/rescue-boot.img" "$dtbo" "$vendor" | tail -n1 | cut -f1)
(( $(df -B1 --output=avail "${output%/*}" | tail -n1) >= total*2+1073741824 )) || fail 'insufficient host storage reserve'
mkdir -m700 "$output"
work=$(mktemp -d "$output/compose.XXXXXXXX")
trap 'find "$work" -depth -delete' EXIT
link_input(){ ln -s "$1" "$work/$2"; }
link_input "$desktop/userdata.img" userdata.img
link_input "$super/super.img" super.img
link_input "$boots/boot_a.img" boot_a.img
link_input "$boots/boot_b.img" boot_b.img
link_input "$boots/rescue-boot.img" rescue-boot.img
link_input "$dtbo" dtbo.img
link_input "$vendor" vendor_boot.img
: > "$work/payloads.jsonl"
for destination in super userdata dtbo_a dtbo_b vendor_boot_a vendor_boot_b boot_a boot_b;do
 case $destination in dtbo_*) name=dtbo;;vendor_boot_*) name=vendor_boot;;*) name=$destination;;esac
 file=$name.img;expanded=$(stat -Lc %s "$work/$file")
 case $destination in super) expanded=4294967296;;userdata) expanded=$(jq -er .root_raw_bytes "$desktop/manifest.json");;esac
 jq -n --arg partition "$destination" --arg file "$file" --arg sha "$(sha256sum "$work/$file" | cut -d' ' -f1)" \
  --argjson stored "$(stat -Lc %s "$work/$file")" --argjson expanded "$expanded" \
  '{partition:$partition,file:$file,sha256:$sha,stored_bytes:$stored,expanded_bytes:$expanded}' >> "$work/payloads.jsonl"
done
printf 'require product=uke-unprepared-measure-first\n' > "$work/android-info.txt"
{ printf 'version 1\n';jq -r '"flash "+.partition+" "+.file' "$work/payloads.jsonl"; } > "$work/fastboot-info.txt"
jq -n --slurpfile payloads "$work/payloads.jsonl" --arg release "$release" --arg commit "$commit" \
 --arg rescue "$(sha256sum "$work/rescue-boot.img" | cut -d' ' -f1)" --arg day "$day" '
 {schema_version:1,artifact_kind:"uke-full-fastboot-test",device:"uke",date_ddmmyy:$day,
 geometry_policy:"measure-before-write",kernel_release:$release,kernel_source_commit:$commit,payloads:$payloads,
 rescue_boot:{file:"rescue-boot.img",stored_bytes:100663296,expanded_bytes:100663296,sha256:$rescue},
 super_policy:{seed_bytes:4294967296,swap_percent:80,rescue_percent:20,opt:false,gpt_geometry_changed:false},
 rescue_console_source_verified:true,
 local_working_vendor_boot_input:true,redistribution_qualified:false,replaces_existing_userdata:true,
 physical_boot_tested:false,common_256_512_qualified:false,secure_boot_qualified:false,
 hardware_auto_unlock_qualified:false,encrypted_swap_qualified:false,hibernate_qualified:false,
 independent_rescue_boot_qualified:false,terminal_rescue_entry_qualified:false}' > "$work/manifest.json"
cat > "$work/README.txt" <<'TEXT'
Uke full singleboot EXT4 / original Fedora Plasma installation test

This PAYLOAD archive deliberately fails the product requirement. First use
prepare-fastboot-update.sh with the qualified fastboot client while one Uke is
connected in bootloader mode. Flash only the resulting measured ZIP. The
preparer verifies complete payload hashes and every destination's actual size.
Do not remove requirements or force a failed check.

The measured ZIP replaces userdata and writes both boot, DTBO and vendor_boot
slots plus the super seed. Existing accounts/files are replaced. GPT sizes are
preserved. On the first normal boot, existing early provisioning grows the
seed into 80% linux_swap / 20% Fedora rescue and grows userdata before setup.
The native swap manager prefers the qualified logical area over managed files.
Original Plasma account setup remains; temporary restricted setup USB should
finish with the wizard and preserve the saved USB preference. Seamless update
and the original native boot-health approval are enabled.

rescue-boot.img is retained as a separate RAM-boot input; it is not flashed by
this archive. Rescue entry, authenticated console/chroot repair, setup cold boot,
256-GB hardware, encryption, hardware key release, safe hibernate and the OEM
verified chain are not qualified by composition. This is an fb-test image,
without an sb claim. The working vendor_boot input is local test evidence;
redistribution and an original OEM source cohort remain separate work.
TEXT
(cd "$work";sha256sum android-info.txt fastboot-info.txt manifest.json README.txt boot_a.img boot_b.img rescue-boot.img dtbo.img vendor_boot.img super.img userdata.img > SHA256SUMS)
archive=fedora-rawhide-linux-kde-plasma-uke-senemos-fb-test-$day.payload.zip
(cd "$work";zip -q -1 "$output/$archive" android-info.txt fastboot-info.txt manifest.json README.txt SHA256SUMS boot_a.img boot_b.img rescue-boot.img dtbo.img vendor_boot.img super.img userdata.img)
unzip -t "$output/$archive" > "$output/zip-check.txt"
cp "$work/manifest.json" "$output/manifest.json"
(cd "$output";sha256sum "$archive" > SHA256SUMS)
printf 'Full test PAYLOAD archive composed and CRC checked. Measure and prepare the connected device before flash: %s\n' "$output/$archive"
