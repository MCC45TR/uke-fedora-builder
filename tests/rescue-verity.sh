#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Owned regular files only. No loop, mapping, mount, key or block-device writes.
set -Eeuo pipefail
trap 'printf "UKE_RESCUE_VERITY_TEST_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
[[ $# == 1 && ! -e $1 && ! -L $1 ]]
report=$(realpath -m "$1")
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$repo/src/image/rescue-verity-layout.sh"
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
for bytes in 33554432 268435456 858783744 2255486976 2199023255552; do
    layout=$(rescue_verity_layout "$bytes")
    data=$(jq -er .data_blocks <<< "$layout")
    tree=$(rescue_verity_hash_blocks "$data")
    next=$(rescue_verity_hash_blocks "$((data+1))")
    (( (data + tree) * 4096 <= bytes && (data + 1 + next) * 4096 > bytes ))
    jq -e '.data_bytes+.hash_bytes+.tail_padding_bytes==.container_bytes and
      .hash_offset_bytes==.data_bytes and .read_only and (.liblp_allocation_changes|not)' <<< "$layout" >/dev/null
done
for bytes in '' 0 00033554432 -1 33554433 33554432x 1e9 2199023259648; do
    if rescue_verity_layout "$bytes" > "$work/rejected.json"; then exit 1; fi
    [[ ! -s $work/rejected.json ]]
done
mkdir "$work/source"
printf 'known rescue file\n' > "$work/source/proof"
touch -d @1794700800 "$work/source/proof" "$work/source"
truncate -s 16M "$work/seed.ext4"
SOURCE_DATE_EPOCH=1794700800 mke2fs -q -F -t ext4 -b4096 -L FEDORA_RESCUE \
    -E lazy_itable_init=0,lazy_journal_init=0 -d "$work/source" "$work/seed.ext4"
input_hash=$(sha256sum "$work/seed.ext4" | cut -d ' ' -f1)
salt=1111111111111111111111111111111111111111111111111111111111111111
first_wall=$(date -u +%s)
bash "$repo/src/image/build-rescue-verity.sh" "$work/seed.ext4" "$input_hash" \
    268435456 1794700800 "$salt" "$work/a"
# Ensure the comparison crosses a wall-clock second, not only a fast repeated
# invocation. This bounded delay is part of the time-independence experiment.
sleep 2
second_wall=$(date -u +%s)
((second_wall > first_wall))
bash "$repo/src/image/build-rescue-verity.sh" "$work/seed.ext4" "$input_hash" \
    268435456 1794700800 "$salt" "$work/b"
cmp "$work/a/rescue.verity" "$work/b/rescue.verity"
[[ $(sha256sum "$work/seed.ext4" | cut -d ' ' -f1) == "$input_hash" ]]
root=$(jq -er .root_hash "$work/a/rescue-verity.json")
blocks=$(jq -er .layout.data_blocks "$work/a/rescue-verity.json")
offset=$(jq -er .layout.hash_offset_bytes "$work/a/rescue-verity.json")
options=(--no-superblock --format=1 --hash=sha256 --data-block-size=4096
    --hash-block-size=4096 --data-blocks="$blocks" --hash-offset="$offset" --salt="$salt")
verify() { veritysetup verify "${options[@]}" "$work/a/rescue.verity" "$work/a/rescue.verity" "$root"; }
verify > "$work/verify.log" 2>&1
if [[ ${root:0:1} == 0 ]]; then wrong_root=1${root:1}; else wrong_root=0${root:1}; fi
if veritysetup verify "${options[@]}" "$work/a/rescue.verity" "$work/a/rescue.verity" "$wrong_root" > "$work/wrong-root.log" 2>&1; then exit 1; fi
# The first data block and the root tree block are distinct authenticated data.
for position in 0 "$offset"; do
    original=$(od -An -tu1 -j "$position" -N1 "$work/a/rescue.verity" | tr -d '[:space:]')
    printf -v octal '%03o' "$((original ^ 1))"
    printf '%b' "\\$octal" | dd of="$work/a/rescue.verity" bs=1 seek="$position" conv=notrunc status=none
    if verify > "$work/tampered.log" 2>&1; then echo 'Tampered verity data accepted' >&2; exit 1; fi
    printf -v octal '%03o' "$original"
    printf '%b' "\\$octal" | dd of="$work/a/rescue.verity" bs=1 seek="$position" conv=notrunc status=none
    verify > "$work/restored.log" 2>&1
done
debugfs -R "dump /proof $work/proof" "$work/a/rescue.verity" >/dev/null 2>&1
cmp "$work/source/proof" "$work/proof"
if bash "$repo/src/image/build-rescue-verity.sh" "$work/seed.ext4" \
    0000000000000000000000000000000000000000000000000000000000000000 \
    268435456 1794700800 "$salt" "$work/rejected-output" > "$work/wrong-input.log" 2>&1; then exit 1; fi
[[ ! -e $work/rejected-output ]]
jq -n --arg hash "$(sha256sum "$work/a/rescue.verity" | cut -d ' ' -f1)" --arg root "$root" \
    --argjson bytes 268435456 --argjson first "$first_wall" --argjson second "$second_wall" \
    '{schema_version:1,owned_regular_files_only:true,container_bytes:$bytes,
      repeated_container_sha256:$hash,root_hash:$root,first_wall_time:$first,second_wall_time:$second,
      repeat_growth_byte_identical:true,crosses_ext4_block_group_boundary:true,
      original_file_readback:true,seed_unchanged:true,original_veritysetup_verify:true,
      data_and_hash_block_tampering_refused:true,wrong_input_digest_refused_before_output:true,
      wrong_root_hash_refused:true,
      measured_super_rescue_geometry_calculated:true,measured_256gb_geometry:false,
      kernel_mapping_tested:false,metadata_signature_verified:false,operating_system_booted:false,
      physical_ufs_tested:false,installable_archive_created:false}' > "$report"
