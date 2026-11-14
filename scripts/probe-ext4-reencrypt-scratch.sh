#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Test original cryptsetup's offline conversion on an owned 64 MiB loop file.
# This is NOT an inline-crypto or production key-management acceptance test.
set +x
set -Eeuo pipefail
export LC_ALL=C
umask 077
[[ $# == 0 && $(id -u) == 0 ]] || { printf 'Run as root without device arguments.\n' >&2; exit 2; }
for tool in cryptsetup losetup mke2fs e2fsck mount umount timeout jq; do command -v "$tool" >/dev/null; done
free_kib=$(df -Pk /var/tmp | awk 'NR==2 {print $4}')
if [[ ! $free_kib =~ ^[0-9]+$ ]] || ((free_kib < 196608)); then
    printf 'Need 64 MiB peak plus at least 128 MiB free reserve.\n' >&2
    exit 1
fi
work=$(mktemp -d /var/tmp/uke-ext4-conversion.XXXXXXXX)
key_file=$(mktemp /run/uke-ext4-conversion-key.XXXXXXXX)
loop=''
mapper=uke-ext4-conversion-$BASHPID
mounted=0
opened=0
cleanup() {
    local result=$?
    trap - EXIT
    set +e
    if (( mounted )); then umount "$work/mount" || result=1; fi
    if (( opened )) || cryptsetup status "$mapper" >/dev/null 2>&1; then
        cryptsetup close "$mapper" || result=1
    fi
    if [[ -n $loop ]]; then losetup -d "$loop" || result=1; fi
    rm -f -- "$key_file"
    # Never remove an image whose mapping or mount failed to close.
    if ! mountpoint -q "$work/mount" && ! losetup -j "$work/volume.img" | grep -q .; then
        rm -rf -- "$work"
    else
        printf 'Scratch state retained at %s for cleanup; no production device involved.\n' "$work" >&2
        result=1
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$work/files" "$work/mount"
printf 'Uke standalone EXT4 conversion sentinel\n' > "$work/files/sentinel.txt"
dd if=/dev/urandom of="$work/files/random.bin" bs=4096 count=64 status=none
(cd "$work/files"; sha256sum sentinel.txt random.bin) > "$work/expected.sha256"
dd if=/dev/urandom of="$key_file" bs=64 count=1 status=none
truncate -s 64M "$work/volume.img"
loop=$(losetup --find --show "$work/volume.img")
[[ $loop =~ ^/dev/loop[0-9]+$ && $(blockdev --getsize64 "$loop") == 67108864 ]]
# Leave 16 MiB of tail capacity for the future LUKS2 header/data shift.
mke2fs -q -F -t ext4 -b 4096 -d "$work/files" "$loop" 12288
e2fsck -fn "$loop" >/dev/null
# The low PBKDF cost is for a disposable random test secret, never an image policy.
timeout --signal=INT --kill-after=5s 90s cryptsetup reencrypt --encrypt --type luks2 \
    --reduce-device-size 16M --cipher aes-xts-plain64 --key-size 512 \
    --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --hotzone-size 4M \
    --batch-mode --key-file "$key_file" "$loop"
cryptsetup isLuks --type luks2 "$loop"
cryptsetup open --readonly --key-file "$key_file" "$loop" "$mapper"
opened=1
mount -o ro,noload "/dev/mapper/$mapper" "$work/mount"
mounted=1
(cd "$work/mount"; sha256sum -c "$work/expected.sha256") >&2
[[ $(findmnt -rn -o FSTYPE --target "$work/mount") == ext4 ]]
jq -M -n --arg kernel "$(uname -r)" --arg version "$(cryptsetup --version)" \
    '{schema_version:1,kernel_release:$kernel,cryptsetup:$version,
      backing_file_bytes:67108864,original_ext4_bytes:50331648,
      offline_ext4_to_luks2_conversion:true,original_files_readback:true,
      hardware_inline_crypto_tested:false,production_root_modified:false,
      automatic_unlock_tested:false,power_loss_recovery_tested:false}'
