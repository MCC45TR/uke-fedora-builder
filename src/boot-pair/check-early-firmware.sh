#!/usr/bin/env bash
# Host-only: a hash-bound DSP exception, never an ELF architecture bypass.
set -Eeuo pipefail
[[ $# == 2 && -d $1 && -s $2 ]] || exit 2
root=$1 manifest=$2
count=0
while read -r expected path; do
    [[ $expected != \#* ]] || continue
    [[ $expected =~ ^[a-f0-9]{64}$ && $path =~ ^usr/lib/firmware/adsp(_dtb)?\.(mdt|b[0-9]{2})$ ]]
    [[ -f $root/$path && ! -L $root/$path ]]
    [[ $(sha256sum "$root/$path" | cut -d ' ' -f1) == "$expected" ]]
    count=$((count+1))
done < "$manifest"
((count>0))
echo 'Pinned early ADSP firmware files: passed'
