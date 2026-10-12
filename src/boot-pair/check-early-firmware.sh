#!/usr/bin/env bash
# Host-only: a hash-bound DSP exception, never an ELF architecture bypass.
set -Eeuo pipefail
[[ $# == 2 && -d $1 && -s $2 ]] || exit 2
root=$1 manifest=$2
jq -e '.schema_version==1 and .device=="uke" and (.files|length)>0 and all(.files[]; (.path|test("^usr/lib/firmware/adsp(_dtb)?\\.(mdt|b[0-9]{2})$")) and (.sha256|test("^[a-f0-9]{64}$")))' "$manifest" >/dev/null
while IFS=$'\t' read -r path expected; do
    [[ -f $root/$path && ! -L $root/$path ]]
    [[ $(sha256sum "$root/$path" | cut -d ' ' -f1) == "$expected" ]]
done < <(jq -r '.files[]|[.path,.sha256]|@tsv' "$manifest")
echo 'Pinned early ADSP firmware files: passed'
