#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -r -- "$work"' EXIT
mkdir -p "$work/payload/usr/lib/firmware"
printf 'DSP fixture\n' > "$work/payload/usr/lib/firmware/adsp.mdt"
sha=$(sha256sum "$work/payload/usr/lib/firmware/adsp.mdt" | cut -d ' ' -f1)
jq -n --arg sha "$sha" '{schema_version:1,device:"uke",files:[{path:"usr/lib/firmware/adsp.mdt",sha256:$sha}]}' > "$work/manifest.json"
check() { bash "$root/src/boot-pair/check-early-firmware.sh" "$work/payload" "$work/manifest.json"; }
reject() { if check >/dev/null 2>&1; then echo 'Invalid DSP payload accepted' >&2; exit 1; fi; }
check
cp "$work/manifest.json" "$work/original.json"
printf 'tamper\n' >> "$work/payload/usr/lib/firmware/adsp.mdt"; reject
printf 'DSP fixture\n' > "$work/payload/usr/lib/firmware/adsp.mdt"
jq '.files[0].path="usr/lib/firmware/../../bin/tool"' "$work/original.json" > "$work/manifest.json"; reject
cp "$work/original.json" "$work/manifest.json"
mv "$work/payload/usr/lib/firmware/adsp.mdt" "$work/file"
ln -s "$work/file" "$work/payload/usr/lib/firmware/adsp.mdt"; reject
rm "$work/payload/usr/lib/firmware/adsp.mdt"; reject
echo 'Early firmware matching, tamper, path traversal, symlink and missing-file contracts passed'
