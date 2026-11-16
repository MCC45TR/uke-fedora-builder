#!/usr/bin/bash
# Data-only checks; no mounts, device access or source compilation.
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
mkdir "$work/root"
printf '{"kernel_profile":"unstable","kernel_rpm_signature":"verified COPR signature","kernel_release":"7.3.4-3-unstable","kernel_source_commit":"44be649381405be367cfbc47af92447545b11a1d"}\n' > "$work/info.json"
bash "$repo/src/image/rescue-seed-manifest.sh" "$work/root" 536870912 "$work/info.json" 6442450944
file=$work/root/usr/share/uke-rescue/seed-layout.json
jq -e '.kind=="uke-rescue-seed-layout" and .seed_layout.super_bytes==4294967296 and
 .seed_layout.phase=="seed" and .seed_layout.opt_partition==false and
 .source_filesystem_bytes==536870912 and .authorizes_key_release==false and .authorizes_resume==false' "$file" >/dev/null
[[ $(stat -c %a "$file") == 644 ]]
before=$(sha256sum "$file")
if bash "$repo/src/image/rescue-seed-manifest.sh" "$work/root" 536870912 "$work/info.json" 6442450944;then exit 1;fi
[[ $(sha256sum "$file") == "$before" ]]
mkdir "$work/foreign"
ln -s "$work/root/usr" "$work/foreign/usr"
if bash "$repo/src/image/rescue-seed-manifest.sh" "$work/foreign" 536870912 "$work/info.json" 6442450944;then exit 1;fi
mkdir "$work/small"
if bash "$repo/src/image/rescue-seed-manifest.sh" "$work/small" 1073741824 "$work/info.json" 4294967296;then exit 1;fi
[[ ! -e $work/small/usr ]]
printf 'Rescue seed data: canonical4GiB layout, no key/resume authority, existing-file/symlink/undersized refusal passed.\n'
