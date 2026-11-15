#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Host-only: one owned regular-file container, never a tablet/block-device tool.
set -Eeuo pipefail
trap 'printf "UKE_RESCUE_VERITY_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
[[ $# == 6 && -f $1 && ! -L $1 && $2 =~ ^[a-f0-9]{64}$ &&
   $4 =~ ^[1-9][0-9]{0,9}$ && $5 =~ ^[a-f0-9]{64}$ && ! -e $6 && ! -L $6 ]]
input=$1 expected=$2 capacity=$3 epoch=$4 salt=$5
((epoch <= 2147483647))
output=$(realpath -m "$6")
here=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=src/image/rescue-verity-layout.sh
# shellcheck disable=SC1091
source "$here/rescue-verity-layout.sh"
layout=$(rescue_verity_layout "$capacity")
data=$(jq -er .data_bytes <<< "$layout")
blocks=$(jq -er .data_blocks <<< "$layout")
tree=$(jq -er .hash_blocks <<< "$layout")
for tool in blkid cp dd df dumpe2fs e2fsck jq od resize2fs sha256sum stat timeout truncate veritysetup; do
    command -v "$tool" >/dev/null
done
exec 3< "$input"
[[ -f /proc/self/fd/3 && $(stat -Lc %s /proc/self/fd/3) -le $data ]]
[[ $(sha256sum /proc/self/fd/3 | cut -d ' ' -f1) == "$expected" ]]
[[ $(blkid -p -s TYPE -o value /proc/self/fd/3) == ext4 &&
   $(blkid -p -s LABEL -o value /proc/self/fd/3) == FEDORA_RESCUE ]]
header=$(dumpe2fs -h /proc/self/fd/3 2>/dev/null)
input_blocks=$(awk '/^Block count:/ {print $3}' <<< "$header")
[[ $input_blocks =~ ^[1-9][0-9]*$ && $(awk '/^Block size:/ {print $3}' <<< "$header") == 4096 ]]
((input_blocks * 4096 == $(stat -Lc %s /proc/self/fd/3)))
available=$(df -PB1 "$(dirname "$output")" | awk 'NR==2{print $4}')
((available >= capacity + 536870912))
mkdir -m700 "$output"
work=$(mktemp -d "$output/work.XXXXXXXX")
trap 'find "$work" -depth -delete' EXIT
cp --sparse=always /proc/self/fd/3 "$work/container"
[[ $(sha256sum "$work/container" | cut -d ' ' -f1) == "$expected" ]]
truncate -s "$data" "$work/container"
# E2FSCK_TIME and SOURCE_DATE_EPOCH serve different clocks in e2fsprogs.
# Limit them to these filesystem subprocesses; never change the host clock.
status=0
env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C TZ=UTC \
    E2FSCK_TIME="$epoch" SOURCE_DATE_EPOCH="$epoch" \
    timeout --kill-after=2s 60s e2fsck -pf "$work/container" > "$output/fsck.log" 2>&1 || status=$?
[[ $status == 0 || $status == 1 ]]
env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C TZ=UTC \
    E2FSCK_TIME="$epoch" SOURCE_DATE_EPOCH="$epoch" \
    timeout --kill-after=2s 60s resize2fs "$work/container" "$blocks" > "$output/resize.log" 2>&1
dumpe2fs -h "$work/container" > "$work/superblock" 2>/dev/null
[[ $(awk '/^Block count:/ {print $3}' "$work/superblock") == "$blocks" &&
   $(awk '/^Block size:/ {print $3}' "$work/superblock") == 4096 ]]
truncate -s "$capacity" "$work/container"
options=(--no-superblock --format=1 --hash=sha256 --data-block-size=4096
    --hash-block-size=4096 --data-blocks="$blocks" --hash-offset="$data" --salt="$salt")
timeout --kill-after=2s 120s veritysetup format "${options[@]}" "$work/container" "$work/container" > "$output/verity-format.log"
root=$(awk '/^Root hash:/ {print $3}' "$output/verity-format.log")
actual_tree=$(awk '/^Hash blocks:/ {print $3}' "$output/verity-format.log")
[[ $root =~ ^[a-f0-9]{64}$ && $actual_tree == "$tree" && $(stat -c %s "$work/container") == "$capacity" ]]
timeout --kill-after=2s 120s veritysetup verify "${options[@]}" "$work/container" "$work/container" "$root" > "$output/verity-verify.log" 2>&1
whole=$(sha256sum "$work/container" | cut -d ' ' -f1)
mv "$work/container" "$output/rescue.verity"
jq -n --argjson layout "$layout" --arg root "$root" --arg salt "$salt" --arg input "$expected" \
    --arg hash "$whole" --argjson epoch "$epoch" \
    '{schema_version:1,artifact_kind:"unqualified-verity-rescue-container",layout:$layout,
      input_ext4_sha256:$input,container_sha256:$hash,root_hash:$root,salt:$salt,filesystem_epoch:$epoch,
      original_tool_userspace_verification_passed:true,all_verity_parameters_need_authentication:true,
      kernel_mapping_tested:false,metadata_signature_verified:false,operating_system_booted:false,
      physical_ufs_tested:false,installable_archive_created:false}' > "$output/rescue-verity.json"
