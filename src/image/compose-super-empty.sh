#!/usr/bin/env bash
# Compose the AOSP metadata-only ZIP entry from the published super seed layout.
set -Eeuo pipefail
export LC_ALL=C
[[ $# == 2 && -f $1 && ! -e $2 && ! -L $2 ]]
layout=$1 output=$2
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
capacity=$(jq -er .super_bytes "$layout")
[[ $(jq -Sc . "$layout") == "$(bash "$repo/src/image/fastboot-singleboot-layout.sh" layout "$capacity" seed | jq -Sc .)" ]]
read -r metadata slots alignment group usable < <(
    jq -er '[.metadata_size,.metadata_slots,.alignment_bytes,.group.name,.group.maximum_size]|@tsv' "$layout"
)
swap=$(jq -er '.partitions[] | select(.name=="system_a") | .bytes' "$layout")
rescue=$(jq -er '.partitions[] | select(.name=="system_b") | .bytes' "$layout")
lpmake --device-size "$capacity" --super-name super --alignment "$alignment" \
    --metadata-size "$metadata" --metadata-slots "$slots" --group "$group:$usable" \
    --partition "system_b:none:$rescue:$group" --partition "system_a:none:$swap:$group" \
    --output "$output"
bytes=$(stat -c %s "$output")
(( bytes > 4096 && bytes <= 4096 + metadata ))
