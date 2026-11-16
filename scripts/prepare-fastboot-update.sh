#!/usr/bin/bash
# Host-only preparation. Reads fastboot variables; never flashes or selects a slot.
set -Eeuo pipefail
export LC_ALL=C
umask 077
fail() { printf 'UKE_FASTBOOT_PREPARE_FAILED: %s\n' "$*" >&2; exit 1; }
[[ $# == 2 ]] || fail 'usage: prepare-fastboot-update.sh PAYLOAD_ZIP NEW_DEVICE_ZIP'
archive=$(realpath "$1");output=$(realpath -m "$2")
[[ -f $archive && ! -L $1 && ! -e $output && ! -L $2 && -d ${output%/*} ]] || fail 'regular input and new output required'
for tool in fastboot timeout unzip zip jq sha256sum od stat cp;do command -v "$tool" >/dev/null || fail "missing original host tool: $tool";done
[[ $(uname -m) == x86_64 || $(uname -m) == aarch64 ]] || fail 'little-endian x86_64 or AArch64 host required'
work=$(mktemp -d "${output%/*}/.uke-fastboot-prepare.XXXXXXXX")
trap 'find "$work" -depth -delete' EXIT
printf '[1/4] Checking the payload manifest and archive paths...\n'
unzip -Z -1 "$archive" > "$work/paths"
printf '%s\n' README.txt SHA256SUMS android-info.txt boot_a.img boot_b.img dtbo.img fastboot-info.txt manifest.json rescue-boot.img super.img userdata.img vendor_boot.img | sort > "$work/expected"
sort "$work/paths" | cmp - "$work/expected" || fail 'unexpected, missing or duplicate archive entry'
entry_size() { unzip -l "$archive" "$1" | awk -v name="$1" '$NF==name{n++;value=$1}END{if(n!=1)exit 1;print value}'; }
for name in manifest.json fastboot-info.txt android-info.txt README.txt SHA256SUMS;do
 size=$(entry_size "$name");[[ $size =~ ^[0-9]+$ && $size -le 65536 ]] || fail "oversized metadata: $name"
done
unzip -p "$archive" manifest.json > "$work/manifest.json"
[[ $(stat -c %s "$work/manifest.json") -le 65536 ]] || fail 'oversized manifest'
jq -e '
 .schema_version==1 and .artifact_kind=="uke-full-fastboot-test" and .device=="uke" and
 .geometry_policy=="measure-before-write" and (.payloads|length)==8 and
 ([.payloads[].partition]|sort)==["boot_a","boot_b","dtbo_a","dtbo_b","super","userdata","vendor_boot_a","vendor_boot_b"] and
 all(.payloads[];
  .partition as $p|.file==({super:"super.img",userdata:"userdata.img",boot_a:"boot_a.img",boot_b:"boot_b.img",
   dtbo_a:"dtbo.img",dtbo_b:"dtbo.img",vendor_boot_a:"vendor_boot.img",vendor_boot_b:"vendor_boot.img"}[$p])) and
 .rescue_boot.file=="rescue-boot.img" and
 all((.payloads[]),.rescue_boot;
  (.stored_bytes|type=="number" and floor==. and .>=28 and .<=8589934592) and
  (.expanded_bytes|type=="number" and floor==. and .>=28 and .<=2199023255552) and
  (.sha256|type=="string" and test("^[a-f0-9]{64}$"))) and
 ([.payloads[]]|group_by(.file)|all(.[];([.[]|{file,stored_bytes,expanded_bytes,sha256}]|unique|length)==1))
' "$work/manifest.json" >/dev/null || fail 'invalid full-test manifest'
unzip -p "$archive" fastboot-info.txt > "$work/tasks"
{ printf 'version 1\n';jq -r '.payloads[]|"flash "+.partition+" "+.file' "$work/manifest.json"; } > "$work/expected-tasks"
cmp "$work/tasks" "$work/expected-tasks" || fail 'write tasks differ from the manifest'
u32() { od -An -v -tu4 -j "$1" -N4 "$work/header" | tr -d ' \n'; }
: > "$work/actual.sha256"
printf '[2/4] Verifying image hashes and expanded sizes...\n'
while IFS=$'\t' read -r name stored expanded expected;do
 printf '  Checking %s\n' "$name"
 actual=$(entry_size "$name")
 [[ $actual == "$stored" ]] || fail "stored size differs: $name"
 unzip -p "$archive" "$name" | sha256sum > "$work/hash"
 [[ $(cut -d' ' -f1 "$work/hash") == "$expected" ]] || fail "payload hash differs: $name"
 printf '%s  %s\n' "$expected" "$name" >> "$work/actual.sha256"
 # Stop decompression after the bounded header. SIGPIPE from unzip is expected;
 # every complete payload and CRC was checked in the preceding hash pass.
 set +e
 unzip -p "$archive" "$name" | dd iflag=fullblock bs=28 count=1 status=none > "$work/header"
 statuses=("${PIPESTATUS[@]}")
 set -e
 [[ ${statuses[1]} == 0 && ( ${statuses[0]} == 0 || ${statuses[0]} == 141 ) && $(stat -c %s "$work/header") == 28 ]] || fail "cannot inspect image header: $name"
 raw=$stored
 if [[ $(u32 0) == 3978755898 ]];then
  [[ $(od -An -v -tu2 -j4 -N8 "$work/header" | xargs) == '1 0 28 12' ]] || fail "unsupported Android sparse header: $name"
  block=$(u32 12);blocks=$(u32 16);chunks=$(u32 20)
  ((block>=512&&block<=65536&&(block&(block-1))==0&&blocks>0&&blocks<=2199023255552/block&&chunks>0&&chunks<=1048576)) || fail "invalid sparse extent: $name"
  raw=$((block*blocks))
 fi
 [[ $raw == "$expanded" ]] || fail "expanded size differs: $name"
done < <(jq -r '[.payloads[],.rescue_boot]|unique_by(.file)[]|[.file,.stored_bytes,.expanded_bytes,.sha256]|@tsv' "$work/manifest.json")
for name in manifest.json fastboot-info.txt android-info.txt README.txt;do
 unzip -p "$archive" "$name" > "$work/metadata"
 printf '%s  %s\n' "$(sha256sum "$work/metadata" | cut -d' ' -f1)" "$name" >> "$work/actual.sha256"
done
unzip -p "$archive" SHA256SUMS | sort > "$work/original.sha256"
sort "$work/actual.sha256" | cmp - "$work/original.sha256" || fail 'archive checksums differ or contain unknown entries'
getvar() {
 local key=$1 response line value='' count=0
 response=$(timeout --kill-after=2s 10s fastboot getvar "$key" 2>&1) || fail "device did not provide $key; connect one Uke in bootloader mode"
 [[ ${#response} -le 4096 ]] || fail "oversized device response: $key"
 while IFS= read -r line;do
  line=${line//$'\r'/};line=${line#'(bootloader) '}
  if [[ $line == "$key: "* ]];then
   value=${line#"$key: "};count=$((count+1))
   value=${value##+([[:space:]])};value=${value%%+([[:space:]])}
  fi
 done <<< "$response"
 [[ $count == 1 && -n $value ]] || fail "missing or ambiguous device value: $key"
 printf '%s' "$value"
}
shopt -s extglob
printf '[3/4] Measuring the connected bootloader and every destination...\n'
[[ $(getvar product) == uke && $(getvar is-userspace) == no && $(getvar slot-count) == 2 ]] || fail 'Uke bootloader with two slots required'
[[ $(getvar snapshot-update-status) == none ]] || fail 'unfinished Android snapshot update; no device write was performed'
slot=$(getvar current-slot);[[ $slot == a || $slot == b ]] || fail 'unrecognized current slot'
printf 'require product=uke\nrequire is-userspace=no\nrequire slot-count=2\n' > "$work/android-info.txt"
while IFS=$'\t' read -r partition raw;do
 value=$(getvar "partition-size:$partition")
 [[ $value =~ ^0[xX][0-9a-fA-F]{1,16}$ ]] || fail "invalid capacity for $partition"
 digits=${value:2};digits=${digits##+(0)};[[ -n $digits ]] || digits=0
 [[ ${#digits} -le 11 ]] || fail "capacity outside supported bounds: $partition"
 bytes=$((16#$digits))
 ((bytes>0&&bytes<=2199023255552&&raw<=bytes)) || fail "$partition has $bytes bytes; payload needs $raw; no device write was performed"
 printf '  %s: payload %s / device %s bytes\n' "$partition" "$raw" "$bytes"
 printf -v short '0x%x' "$bytes";printf -v eight '0x%08x' "$bytes";printf -v sixteen '0x%016x' "$bytes"
 printf 'require partition-size:%s=%s|%s|%s|%s\n' "$partition" "$value" "$short" "$eight" "$sixteen" >> "$work/android-info.txt"
done < <(jq -r '.payloads[]|[.partition,.expanded_bytes]|@tsv' "$work/manifest.json")
rescue=$(jq -er .rescue_boot.expanded_bytes "$work/manifest.json")
for partition in boot_a boot_b;do
 value=$(getvar "partition-size:$partition");digits=${value:2};digits=${digits##+(0)}
 [[ $value =~ ^0[xX][0-9a-fA-F]{1,16}$ && -n $digits && ${#digits} -le 11 ]] || fail 'invalid rescue destination capacity'
 ((rescue<=16#$digits)) || fail 'rescue boot image does not fit both boot destinations'
done
printf '[4/4] Writing the measured ZIP; payload bytes stay unchanged...\n'
required=$(stat -c %s "$archive")
(( $(df -B1 --output=avail "${output%/*}" | tail -n1) >= required*2+1073741824 )) || fail 'insufficient host storage and operating reserve'
cp --reflink=auto "$archive" "$work/device.zip"
hash=$(sha256sum "$work/android-info.txt" | cut -d' ' -f1)
awk -v hash="$hash" '$2=="android-info.txt"{$1=hash;print $1"  "$2;next}{print}' "$work/actual.sha256" | sort > "$work/SHA256SUMS"
(cd "$work";zip -q device.zip android-info.txt SHA256SUMS)
mv "$work/device.zip" "$output"
sha256sum "$output" > "$output.sha256"
printf 'Prepared %s\nNo slot selection, flash, erase, reboot, relock or key operation was performed.\nRun: fastboot update %q\n' "$output" "$output"
