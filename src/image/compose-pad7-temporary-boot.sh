#!/usr/bin/env bash
# Host-only rewrap of the exact signed 7.4.11 userdata-super boot image.
set -Eeuo pipefail
export LC_ALL=C
[[ $# == 2 && -f $1 && ! -e $2 && ${2##*/} == boot.img ]]
source_image=$1
output=$2
capacity=100663296
kernel_bytes=79329792
content_bytes=$((4096 + (kernel_bytes + 4095) / 4096 * 4096))
source_sha=204d47503bcfb4d425b457276326dabeb1ac1d03152b03d017c79b83fad8feeb
kernel_sha=5b475bbbdc8881a3b9fc3fe0243cc2751ef5514983d4d2205734231be5883b74

printf '%s  %s\n' "$source_sha" "$source_image" | sha256sum -c --strict
[[ $(stat -c %s "$source_image") == "$capacity" ]]
[[ $(od --endian=little -An -v -tu4 -j8 -N12 "$source_image" | xargs) == "$kernel_bytes 0 570425768" ]]

head -c "$content_bytes" "$source_image" > "$output"
printf '\0\0\0\0' | dd of="$output" bs=1 seek=16 conv=notrunc status=none
# Use the previously reviewed Global 304 compatibility properties.
avbtool add_hash_footer --image "$output" --partition_name boot --partition_size "$capacity" \
    --algorithm NONE --hash_algorithm sha256 --salt "$source_sha" --rollback_index 1788220800 \
    --prop com.android.build.boot.os_version:14 \
    --prop com.android.build.boot.security_patch:2026-09-01 \
    --prop com.android.build.boot.fingerprint:Xiaomi/uke_global/uke:14/UKQ1.240624.001/OS3.0.304.0.WOZMIXM:user/release-keys

[[ $(stat -c %s "$output") == "$capacity" ]]
[[ $(od --endian=little -An -v -tu4 -j16 -N4 "$output" | xargs) == 0 ]]
cmp -n 16 -- "$source_image" "$output"
cmp -i 20:20 -n "$((content_bytes - 20))" -- "$source_image" "$output"
dd if="$output" bs=4096 skip=1 count="$kernel_bytes" iflag=count_bytes status=none |
    sha256sum | awk -v expected="$kernel_sha" '$1==expected {ok=1} END {exit !ok}'
avbtool info_image --image "$output"
avbtool verify_image --image "$output"
