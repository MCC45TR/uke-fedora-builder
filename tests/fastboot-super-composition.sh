#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Original-tool integration fixture. Host files only; no root, mount or devices.
set -Eeuo pipefail
export LC_ALL=C
umask 077
[[ $# == 1 && ! -e $1 && ! -L $1 ]] || {
    printf 'Usage: %s NEW_REPORT_DIRECTORY\n' "${0##*/}" >&2
    exit 2
}
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
reports=$(realpath -m "$1")
mkdir -m700 "$reports"
work=$(mktemp -d "$(dirname "$reports")/uke-super-fixture.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
for tool in mke2fs debugfs lpdump lpunpack simg2img jq sha256sum; do command -v "$tool" >/dev/null; done
layout="$root/src/image/fastboot-singleboot-layout.sh"
producer="$root/src/image/build-fastboot-super.sh"
capacity=4294967296
bash "$layout" layout "$capacity" > "$work/layout.json"
mkdir "$work/files"
printf 'Independent Fedora rescue payload fixture, not an operating system.\n' > "$work/files/sentinel.txt"
dd if=/dev/urandom of="$work/files/random.bin" bs=4096 count=16 status=none
truncate -s 64M "$work/input.ext4"
mke2fs -q -F -t ext4 -b 4096 -d "$work/files" "$work/input.ext4"
input_hash=$(sha256sum "$work/input.ext4" | cut -d ' ' -f1)

refuse() {
    local name=$1
    shift
    if bash "$producer" "$@" > "$work/$name.log" 2>&1; then
        printf 'Unexpectedly accepted %s fixture.\n' "$name" >&2
        exit 1
    fi
}
jq '.partitions[0].role = "opt"' "$work/layout.json" > "$work/tampered.json"
refuse altered-role "$work/tampered.json" "$work/input.ext4" "$work/refused"
[[ ! -e $work/refused ]]
ln -s input.ext4 "$work/symlink.ext4"
refuse symlink-input "$work/layout.json" "$work/symlink.ext4" "$work/refused"
[[ ! -e $work/refused ]]
bash "$layout" layout 4294967808 > "$work/unaligned.json"
refuse unaligned-sparse-block "$work/unaligned.json" "$work/input.ext4" "$work/refused"
[[ ! -e $work/refused ]]
cp --reflink=auto --sparse=always "$work/input.ext4" "$work/oversized.ext4"
truncate -s 1G "$work/oversized.ext4"
refuse oversized-rescue "$work/layout.json" "$work/oversized.ext4" "$work/refused"
[[ ! -e $work/refused ]]
rm -- "$work/oversized.ext4"
# Inject only the free-space observation, not any image/decoder tools.
mkdir "$work/low-space-tools"
cat > "$work/low-space-tools/df" <<'SH'
#!/bin/sh
case "$1" in
    -Pi) printf 'Filesystem Inodes IUsed IFree IUse%% Mounted-on\nfixture 10000 10 9990 1%% /\n';;
    *) printf 'Filesystem 1024-blocks Used Available Capacity Mounted-on\nfixture 1024 1000 24 98%% /\n';;
esac
SH
chmod +x "$work/low-space-tools/df"
PATH="$work/low-space-tools:$PATH" refuse low-space "$work/layout.json" "$work/input.ext4" "$work/refused"
[[ ! -e $work/refused ]]
grep -q 'reserve' "$work/low-space.log"

bash "$producer" "$work/layout.json" "$work/input.ext4" "$work/composed"
[[ $(sha256sum "$work/input.ext4" | cut -d ' ' -f1) == "$input_hash" ]]
for pending in "$work/composed/".work.*; do [[ ! -e $pending ]]; done
(cd "$work/composed"; sha256sum -c SHA256SUMS)
jq -e '.container_assembled and .both_logical_payloads_byte_matched and
  .rescue_full_capacity and .swap_full_capacity and .liblp_three_slot_readback and
  .independent_aosp_decode and (.installable_archive_created | not) and
  (.secure_boot_qualified | not) and (.rescue_os_qualified | not) and
  (.device_write_executed | not)' "$work/composed/super-composition.json" >/dev/null
# Independently extract rescue again, then use original EXT4 tooling to check
# original files without mounting or trusting the producer's own hash receipt.
simg2img "$work/composed/super.img" "$work/decoded.raw"
mkdir "$work/extracted"
lpunpack -p system_b "$work/decoded.raw" "$work/extracted"
debugfs -R "dump /sentinel.txt $work/sentinel.txt" "$work/extracted/system_b.img" >/dev/null 2>&1
debugfs -R "dump /random.bin $work/random.bin" "$work/extracted/system_b.img" >/dev/null 2>&1
cmp "$work/files/sentinel.txt" "$work/sentinel.txt"
cmp "$work/files/random.bin" "$work/random.bin"
# Refusing an occupied destination must also preserve its accepted output.
refuse occupied-output "$work/layout.json" "$work/input.ext4" "$work/composed"
(cd "$work/composed"; sha256sum -c SHA256SUMS)
cp -- "$work/composed/super-composition.json" "$work/composed/super-layout.json" \
    "$work/composed/"lp-slot-?.json "$work/composed/rescue-superblock.txt" \
    "$work/composed/rescue-filesystem-check.txt" "$reports/"
jq -M -n --arg input "$input_hash" \
    '{schema_version:1,fixture_super_bytes:4294967296,synthetic_ext4_input:true,
      input_sha256_unchanged:$input,original_files_independently_read_back:true,
      altered_role_refused:true,symlink_refused:true,unaligned_capacity_refused:true,
      oversized_rescue_refused:true,low_space_refused:true,occupied_output_preserved:true,
      device_write_executed:false,operating_system_boot_tested:false,
      secure_boot_tested:false,encryption_tested:false}' > "$reports/fixture-result.json"
printf 'Original-tool super composition, three-slot readback, full capacities, independent EXT4 file recovery and refusal paths passed.\n'
