#!/usr/bin/env bash
# Codec fixtures include real nonzero RAW data and explicit zero/nonzero FILL.
set -Eeuo pipefail
[[ $# == 2 && -x $1 && ! -e $2 ]] || exit 2
binary=$1 out=$2
mkdir -p "$out"
dd if=/dev/zero of="$out/raw.img" bs=4096 count=1 status=none
{
    dd if=/dev/urandom bs=4096 count=2 status=none
    dd if=/dev/zero bs=4096 count=1 status=none
    for ((i=0;i<1024;++i)); do printf 'UKE!'; done
} >> "$out/raw.img"
"$binary" encode "$out/raw.img" "$out/sparse.img"
"$binary" decode "$out/sparse.img" "$out/roundtrip.img"
cmp "$out/raw.img" "$out/roundtrip.img"
if "$binary" encode "$out/raw.img" "$out/sparse.img"; then exit 1; fi
ln -s raw.img "$out/link.img"
if "$binary" encode "$out/link.img" "$out/link-output.img"; then exit 1; fi
if "$binary" encode /dev/zero "$out/block-output.img"; then exit 1; fi
for scenario in truncated dont-care trailing bad-size; do
    cp "$out/sparse.img" "$out/$scenario.img"
    case $scenario in
        truncated) truncate -s 30 "$out/$scenario.img";;
        dont-care) printf '\303\312' | dd of="$out/$scenario.img" bs=1 seek=28 conv=notrunc status=none;;
        trailing) printf X >> "$out/$scenario.img";;
        bad-size) printf '\377\377\377\377' | dd of="$out/$scenario.img" bs=1 seek=32 conv=notrunc status=none;;
    esac
    if "$binary" decode "$out/$scenario.img" "$out/rejected-$scenario.img"; then exit 1; fi
    [[ ! -e $out/rejected-$scenario.img ]]
done
echo 'Sparse roundtrip, no-overwrite, symlink/device and four malformed-input groups passed'
