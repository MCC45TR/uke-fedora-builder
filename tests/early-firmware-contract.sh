#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -r -- "$work"' EXIT
mkdir -p "$work/payload/usr/lib/firmware"
printf 'DSP fixture\n' > "$work/payload/usr/lib/firmware/adsp.mdt"
sha=$(sha256sum "$work/payload/usr/lib/firmware/adsp.mdt" | cut -d ' ' -f1)
printf '%s  usr/lib/firmware/adsp.mdt\n' "$sha" > "$work/manifest.sha256"
check() { bash "$root/src/boot-pair/check-early-firmware.sh" "$work/payload" "$work/manifest.sha256"; }
reject() { if check >/dev/null 2>&1; then echo 'Invalid DSP payload accepted' >&2; exit 1; fi; }
check
cp "$work/manifest.sha256" "$work/original.sha256"
printf 'tamper\n' >> "$work/payload/usr/lib/firmware/adsp.mdt"; reject
printf 'DSP fixture\n' > "$work/payload/usr/lib/firmware/adsp.mdt"
sed 's|usr/lib/firmware/adsp.mdt|usr/lib/firmware/../../bin/tool|' "$work/original.sha256" > "$work/manifest.sha256"; reject
cp "$work/original.sha256" "$work/manifest.sha256"
mv "$work/payload/usr/lib/firmware/adsp.mdt" "$work/file"
ln -s "$work/file" "$work/payload/usr/lib/firmware/adsp.mdt"; reject
rm "$work/payload/usr/lib/firmware/adsp.mdt"; reject
echo 'Early firmware matching, tamper, path traversal, symlink and missing-file contracts passed'
