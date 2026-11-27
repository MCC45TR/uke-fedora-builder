#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
[[ $# == 1 ]]
key=$(realpath -- "$1")
signer=$(realpath -- "$(dirname -- "$0")/../src/image/sign-fastboot-boot.sh")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd "$work"
capacity=100663296
hash() { sha256sum < "$1" | cut -d ' ' -f1; }
write_at() { dd of="$1" bs=1 seek="$2" conv=notrunc status=none; }
reject() {
    if "$@" > rejection.log 2>&1; then
        echo "Unexpected success from $*" >&2
        exit 1
    fi
}
truncate -s "$capacity" source.img
printf 'ANDROID!\101\000\000\000' | write_at source.img 0
printf '\250\001\000\042\060\006\000\000' | write_at source.img 16
printf '\004\000\000\000' | write_at source.img 40
printf 'senemos.root=userdata' | write_at source.img 44
printf 'test kernel bytes' | write_at source.img 4096
source_sha=$(hash source.img)
reject avbtool info_image --image source.img
bash "$signer" source.img "$source_sha" boot.img "$key"
bash "$signer" source.img "$source_sha" identical.img "$key"
cmp boot.img identical.img
cmp -n 8192 source.img boot.img
[[ $(hash source.img) == "$source_sha" && $(stat -c %s boot.img) == "$capacity" ]]
[[ $(tail -c64 boot.img | head -c4) == AVBf ]]
avbtool info_image --image boot.img > info
grep -E '^Algorithm: +SHA256_RSA4096$' info
grep -E '^Rollback Index: +0$' info
grep -E '^Original image size: +8192 bytes$' info
grep -E '^ +Partition Name: +boot$' info
grep -E '^ +Flags: +0$' info
grep -F "Prop: com.android.build.boot.os_version -> '14'" info
grep -F "Prop: com.android.build.boot.security_patch -> '2026-09-01'" info

avbtool extract_public_key --key "$key" --output public.avbpubkey
avbtool make_vbmeta_image --output vbmeta.img --chain_partition boot:3:public.avbpubkey
avbtool verify_image --image vbmeta.img --expected_chain_partition boot:3:public.avbpubkey --follow_chain_partitions
mv boot.img verified.img
cp --sparse=always source.img boot.img
reject avbtool verify_image --image vbmeta.img --expected_chain_partition boot:3:public.avbpubkey --follow_chain_partitions
mv verified.img boot.img
printf X | write_at boot.img 4096
reject avbtool verify_image --image boot.img --key "$key"

printf 'senemos.root=rescue\000\000' | write_at source.img 44
rescue_sha=$(hash source.img)
reject bash "$signer" source.img "$source_sha" rejected.img "$key"
bash "$signer" source.img "$rescue_sha" rescue-boot.img "$key"
mv rescue-boot.img boot.img
cmp -n 8192 source.img boot.img
avbtool verify_image --image boot.img --key "$key"
reject bash "$signer" boot.img "$(hash boot.img)" rejected.img "$key"
reject bash "$signer" source.img "$rescue_sha" boot.img "$key"
printf 'wrong key\n' > foreign.pem
reject bash "$signer" source.img "$rescue_sha" rejected.img foreign.pem
printf '\001' | write_at source.img 4161
reject bash "$signer" source.img "$(hash source.img)" rejected.img "$key"
printf '\000' | write_at source.img 4161
printf '\001' | write_at source.img 1580
reject bash "$signer" source.img "$(hash source.img)" rejected.img "$key"
printf '\000' | write_at source.img 1580
printf '\000\360\377\005' | write_at source.img 8
reject bash "$signer" source.img "$(hash source.img)" rejected.img "$key"
[[ ! -e rejected.img ]]
echo 'Chained AVB boot/rescue metadata, deterministic output and corruption refusals passed'
