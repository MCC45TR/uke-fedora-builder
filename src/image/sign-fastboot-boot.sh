#!/usr/bin/env bash
# Add chained-boot AVB metadata to a verified, kernel-only Uke boot wrapper.
set -Eeuo pipefail
export LC_ALL=C
[[ $# == 4 && -f $1 && $2 =~ ^[0-9a-f]{64}$ && ! -e $3 && -f $4 ]] || {
    echo 'Usage: sign-fastboot-boot.sh SOURCE EXPECTED_SHA256 NEW_OUTPUT AOSP_TEST_KEY' >&2
    exit 1
}
source_image=$1 expected_sha=$2 output=$3 test_key=$4
capacity=100663296
page=4096
test_key_sha=6a224754880a57ab9cbd308267cd157d94cf05a1c8cb851aec4090e045d24121
hash() { sha256sum < "$1" | cut -d ' ' -f1; }
[[ $(hash "$source_image") == "$expected_sha" && $(hash "$test_key") == "$test_key_sha" ]] || {
    echo 'Boot wrapper or AOSP test key SHA-256 mismatch' >&2; exit 1;
}
[[ $(stat -Lc %s "$source_image") == "$capacity" && $(head -c8 "$source_image") == 'ANDROID!' ]] || {
    echo 'Expected a full-size Android boot wrapper' >&2; exit 1;
}
read -r kernel ramdisk _os_version header reserved1 reserved2 reserved3 reserved4 version < <(
    od --endian=little -An -tu4 -w36 -j8 -N36 "$source_image"
)
signature=$(od --endian=little -An -tu4 -j1580 -N4 "$source_image" | tr -d ' ')
[[ $kernel =~ ^[1-9][0-9]*$ && $ramdisk == 0 && $header == 1584 && $version == 4 && $signature == 0 &&
    $reserved1 == 0 && $reserved2 == 0 && $reserved3 == 0 && $reserved4 == 0 ]] || {
    echo 'Expected a kernel-only Android boot v4 wrapper' >&2; exit 1;
}
# Retain the entire boot header and aligned kernel. Replace only verified zero padding.
content=$((page + (kernel + page - 1) / page * page))
maximum=$(avbtool add_hash_footer --partition_size "$capacity" --calc_max_image_size)
(( kernel >= 64 && content <= maximum )) || {
    echo 'Kernel leaves insufficient space for AVB metadata in the boot partition' >&2; exit 1;
}
cmp -s -i "$((page + kernel)):0" -n "$((capacity - page - kernel))" "$source_image" /dev/zero || {
    echo 'Boot wrapper has nonzero data after the kernel' >&2; exit 1;
}

work=$(mktemp -d -- "$(dirname -- "$output")/.boot-avb.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
# avbtool verifies the boot descriptor against a sibling named boot.img.
image=$work/boot.img
head -c "$content" "$source_image" > "$image"
avbtool add_hash_footer --image "$image" --partition_name boot --partition_size "$capacity" \
    --algorithm SHA256_RSA4096 --key "$test_key" --hash_algorithm sha256 --salt "$expected_sha" \
    --rollback_index 0 --prop com.android.build.boot.os_version:14 \
    --prop com.android.build.boot.security_patch:2026-09-01
[[ $(stat -c %s "$image") == "$capacity" ]]
cmp -n "$content" "$source_image" "$image"
avbtool verify_image --image "$image" --key "$test_key"
ln -T -- "$image" "$output"
