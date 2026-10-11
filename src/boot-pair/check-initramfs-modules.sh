#!/usr/bin/env bash
# Host-only check: early modules must be the exact reviewed root payload.
set -Eeuo pipefail
[[ $# == 3 && -d $1 && -d $2 && $3 != */* ]]
initramfs=$1 root=$2 release=$3
count=0
while IFS= read -r -d '' module; do
    cmp "$module" "$root/${module#"$initramfs/"}"
    ((count+=1))
done < <(find "$initramfs/usr/lib/modules/$release/kernel" -type f -name '*.ko*' -print0)
((count > 0))
printf 'Initramfs/root module bytes match: %s\n' "$count"
