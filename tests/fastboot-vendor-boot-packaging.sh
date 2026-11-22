#!/usr/bin/env bash
# Exercise the archive extension and its input refusals with synthetic firmware.
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
profile=configs/images/rawhide-fastboot
mkdir -p "$work/fixture" "$work/source/$profile" "$work/source/src/image"
cp "$repo/src/image/add-fastboot-vendor-boot.sh" "$work/source/src/image/"
cp "$repo/$profile/"* "$work/source/$profile/"
cp "$repo/$profile/"*.txt "$work/fixture/"
archive=$work/fedora-rawhide-uke-kde-plasma-221126-1436.zip
(
    cd "$work/fixture"
    printf 'Fixture\n' > README.txt
    jq -n '{
        device:"uke", artifact_kind:"uke-rawhide-super-fastboot", mode:"singleboot",
        installation:"fastboot update", targets:["super","userdata","dtbo_active","boot_active"],
        dtbo_sha256:"74958f51ed384f86e542fefe42c2252c4f309339df5c0850287e983db89fcfda"
    }' > manifest.json
    for file in boot.img dtbo.img rescue-boot.img userdata.img super.img super_empty.img; do
        printf '%s\n' "$file" > "$file"
    done
    sha256sum -- ./* | sed 's@  [.]\/@  @' > sums
    mv sums SHA256SUMS
    zip -q "$archive" ./*
)
vendor=$work/vendor.img
truncate -s 20480 "$vendor"
put() { printf '%b' "$2" | dd of="$vendor" bs=1 seek="$1" conv=notrunc status=none; }
put 0 'VNDRBOOT\x04\x00\x00\x00\x00\x10\x00\x00'
put 24 '\x01'
put 2096 '\x50\x08\x00\x00\x04'
put 2112 '\x6c\x00\x00\x00\x01\x00\x00\x00\x6c\x00\x00\x00\x01'
put 8192 'DTB!'
hash() { sha256sum < "$1" | cut -d ' ' -f 1; }
dtb=$(printf 'DTB!' | sha256sum | cut -d ' ' -f 1)
jq --arg hash "$dtb" '.dtb_bytes=4 | .dtb_sha256=$hash' "$repo/$profile/vendor-boot.json"     > "$work/source/$profile/vendor-boot.json"
script=$work/source/src/image/add-fastboot-vendor-boot.sh
archive_hash=$(hash "$archive")
vendor_hash=$(hash "$vendor")
bash "$script" "$archive" "$archive_hash" "$vendor" "$vendor_hash" "$work/delivery"
(
    cd "$work/delivery"
    sha256sum -c --strict SHA256SUMS
    unzip -q "${archive##*/}" -d readback
    cd readback
    sha256sum -c --strict SHA256SUMS
    cmp vendor_boot.img "$vendor"
    cmp userdata.img "$work/fixture/userdata.img"
    jq -e --arg sha "$vendor_hash" '
        .images["vendor_boot.img"].sha256==$sha and
        .targets==["super","userdata","vendor_boot_active","dtbo_active","boot_active"]
    ' manifest.json >/dev/null
    cmp fastboot-info.txt <(printf 'version 1\nflash super super.img\nflash userdata userdata.img\nflash vendor_boot vendor_boot.img\nflash dtbo dtbo.img\nflash boot boot.img\n')
)
if bash "$script" "$archive" "$vendor_hash" "$vendor" "$vendor_hash" "$work/rejected"; then exit 1; fi
put 8192 'BAD!'
if bash "$script" "$archive" "$archive_hash" "$vendor" "$(hash "$vendor")" "$work/rejected"; then exit 1; fi
[[ ! -e $work/rejected && $(hash "$archive") == "$archive_hash" ]]
