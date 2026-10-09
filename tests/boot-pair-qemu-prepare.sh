#!/usr/bin/env bash
# Host-only disposable GPT fixtures. Never accepts a device or existing output.
set -Eeuo pipefail
[[ $# == 2 && -s $1/system.raw.img && -s $1/manifest.json && ! -e $2 ]] || exit 2
candidate=$(realpath "$1") out=$2
mkdir -p "$out"
bytes=$(stat -c %s "$candidate/system.raw.img")
[[ $bytes == 3221225472 ]]
for name in correct wrong-partname wrong-uuid; do
    truncate -s "$((bytes + 4*1024*1024))" "$out/$name.disk"
    partition_name=linux
    [[ $name != wrong-partname ]] || partition_name=userdata
    printf 'label: gpt\nunit: sectors\n\nstart=2048,size=%s,type=L,name="%s"\n' "$((bytes / 512))" "$partition_name" | sfdisk "$out/$name.disk"
    if [[ $name == wrong-uuid ]]; then
        cp --reflink=auto "$candidate/system.raw.img" "$out/wrong-uuid.ext4"
        tune2fs -U random "$out/wrong-uuid.ext4"
        dd if="$out/wrong-uuid.ext4" of="$out/$name.disk" bs=1M seek=1 conv=notrunc,sparse status=none
        rm "$out/wrong-uuid.ext4"
    else
        dd if="$candidate/system.raw.img" of="$out/$name.disk" bs=1M seek=1 conv=notrunc,sparse status=none
    fi
done
cp "$candidate/Image" "$out/Image"
cp "$candidate/inputs/profile.json" "$out/profile.json"
printf '%s\n' 'Three generic VM GPT fixtures prepared; no Uke geometry or hardware emulated'
