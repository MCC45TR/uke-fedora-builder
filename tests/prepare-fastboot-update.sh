#!/usr/bin/bash
# Synthetic nonbootable ZIP and read-only fake fastboot. No compiler/device.
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
mkdir "$work/files" "$work/bin"
for name in boot_a boot_b dtbo vendor_boot rescue-boot;do truncate -s4096 "$work/files/$name.img";done
# Valid sparse DONT_CARE extents; no expanded multi-GiB file is created.
printf '\x3a\xff\x26\xed\x01\x00\x00\x00\x1c\x00\x0c\x00\x00\x10\x00\x00\x00\x00\x10\x00\x01\x00\x00\x00\x00\x00\x00\x00\xc3\xca\x00\x00\x00\x00\x10\x00\x0c\x00\x00\x00' > "$work/files/super.img"
printf '\x3a\xff\x26\xed\x01\x00\x00\x00\x1c\x00\x0c\x00\x00\x10\x00\x00\x00\x00\x20\x00\x01\x00\x00\x00\x00\x00\x00\x00\xc3\xca\x00\x00\x00\x00\x20\x00\x0c\x00\x00\x00' > "$work/files/userdata.img"
printf 'Synthetic files; not an operating system or firmware.\n' > "$work/files/README.txt"
printf 'require product=uke\n' > "$work/files/android-info.txt"
printf 'version 1\nflash super super.img\nflash userdata userdata.img\nflash vendor_boot_a vendor_boot.img\nflash vendor_boot_b vendor_boot.img\nflash dtbo_a dtbo.img\nflash dtbo_b dtbo.img\nflash boot_a boot_a.img\nflash boot_b boot_b.img\n' > "$work/files/fastboot-info.txt"
jq -n --arg flat "$(sha256sum "$work/files/boot_a.img" | cut -d' ' -f1)" \
 --arg super "$(sha256sum "$work/files/super.img" | cut -d' ' -f1)" \
 --arg user "$(sha256sum "$work/files/userdata.img" | cut -d' ' -f1)" '
 {schema_version:1,artifact_kind:"uke-full-fastboot-test",device:"uke",geometry_policy:"measure-before-write",
 payloads:[{partition:"super",file:"super.img"},{partition:"userdata",file:"userdata.img"},
  {partition:"vendor_boot_a",file:"vendor_boot.img"},{partition:"vendor_boot_b",file:"vendor_boot.img"},
  {partition:"dtbo_a",file:"dtbo.img"},{partition:"dtbo_b",file:"dtbo.img"},
  {partition:"boot_a",file:"boot_a.img"},{partition:"boot_b",file:"boot_b.img"}]|
  map(.+if .partition=="super" then {stored_bytes:40,expanded_bytes:4294967296,sha256:$super}
   elif .partition=="userdata" then {stored_bytes:40,expanded_bytes:8589934592,sha256:$user}
   else {stored_bytes:4096,expanded_bytes:4096,sha256:$flat} end),
 rescue_boot:{file:"rescue-boot.img",stored_bytes:4096,expanded_bytes:4096,sha256:$flat}}
' > "$work/files/manifest.json"
(cd "$work/files";sha256sum README.txt android-info.txt fastboot-info.txt manifest.json boot_a.img boot_b.img dtbo.img rescue-boot.img super.img userdata.img vendor_boot.img > SHA256SUMS;zip -q "$work/input.zip" ./*)
cat > "$work/bin/fastboot" <<'MOCK'
#!/usr/bin/bash
set -Eeuo pipefail
[[ $# == 2 && $1 == getvar ]]
printf '%s\n' "$*" >> "$UKE_FIXTURE_COMMANDS"
case $2 in
 product) value=uke;[[ $UKE_FIXTURE_CASE != foreign ]] || value=foreign;;
 is-userspace) value=no;[[ $UKE_FIXTURE_CASE != fastbootd ]] || value=yes;;
 slot-count) value=2;;
 current-slot) value=b;;
 snapshot-update-status) value=none;[[ $UKE_FIXTURE_CASE != snapshot ]] || value=merging;;
 partition-size:super)
  value=' 0x200000000 '
  [[ $UKE_FIXTURE_CASE != small ]] || value=0xc0000000
  [[ $UKE_FIXTURE_CASE != large ]] || value=0x00000002a0000000;;
 partition-size:userdata) value=0x4000000000;[[ $UKE_FIXTURE_CASE != large ]] || value=0x73d7700000;;
 partition-size:boot_*|partition-size:vendor_boot_*) value=0x6000000;;
 partition-size:dtbo_*) value=0x1800000;;
 *) exit 1;;
esac
[[ $UKE_FIXTURE_CASE != missing || $2 != partition-size:dtbo_b ]] || exit 1
printf '(bootloader) %s: %s\nFinished. Total time: 0.001s\n' "$2" "$value" >&2
if [[ $UKE_FIXTURE_CASE == duplicate && $2 == product ]];then printf 'product: uke\n' >&2;fi
MOCK
chmod 755 "$work/bin/fastboot"
export PATH="$work/bin:$PATH" UKE_FIXTURE_COMMANDS="$work/commands"
for scenario in synthetic-256 large;do
 export UKE_FIXTURE_CASE=$scenario
 if ! bash "$root/scripts/prepare-fastboot-update.sh" "$work/input.zip" "$work/$scenario.zip" > "$work/$scenario.log" 2>&1;then cat "$work/$scenario.log";exit 1;fi
 unzip -p "$work/$scenario.zip" SHA256SUMS > "$work/after.sha256"
 mkdir "$work/readback-$scenario"
 unzip -q "$work/$scenario.zip" -d "$work/readback-$scenario"
 (cd "$work/readback-$scenario";sha256sum -c --strict --quiet ../after.sha256)
 for name in boot_a boot_b dtbo vendor_boot rescue-boot super userdata;do cmp "$work/files/$name.img" "$work/readback-$scenario/$name.img";done
 grep -q '^require partition-size:super=' "$work/readback-$scenario/android-info.txt"
done
for scenario in foreign fastbootd snapshot small missing duplicate;do
 export UKE_FIXTURE_CASE=$scenario
 if bash "$root/scripts/prepare-fastboot-update.sh" "$work/input.zip" "$work/$scenario.zip" > "$work/$scenario.log" 2>&1;then cat "$work/$scenario.log";exit 1;fi
 [[ ! -e $work/$scenario.zip ]]
done
export UKE_FIXTURE_CASE=synthetic-256
cp "$work/input.zip" "$work/tampered.zip"
printf 'changed' | dd of="$work/files/dtbo.img" conv=notrunc status=none
(cd "$work/files";zip -q "$work/tampered.zip" dtbo.img)
if bash "$root/scripts/prepare-fastboot-update.sh" "$work/tampered.zip" "$work/bad.zip" > "$work/tampered.log" 2>&1;then exit 1;fi
[[ ! -e $work/bad.zip ]]
if grep -v '^getvar ' "$work/commands";then exit 1;fi
echo 'PASS: measured ZIP preparation; two synthetic capacities, sparse extents, unchanged payloads/checksums, wrong identity/snapshot/size/ambiguous/missing/tampered refusals; getvar only.'
