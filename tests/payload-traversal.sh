#!/usr/bin/env bash
# Host-only scanner faults; target files are never executed.
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
audit=${UKE_PAYLOAD_AUDIT:-$repo/src/audit/check-target-payload.sh}
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/payload" "$fixture/bin" "$fixture/temp"
printf '#!/bin/sh\n' > "$fixture/payload/safe"
printf '#!/usr/bin/python3\n' > "$fixture/payload/omitted"
cat > "$fixture/bin/find" <<'SH'
#!/usr/bin/env bash
printf '%s\0' "$UKE_FIXTURE_FIRST"
exit 1
SH
chmod +x "$fixture/bin/find"
if TMPDIR="$fixture/temp" PATH="$fixture/bin:$PATH" UKE_FIXTURE_FIRST="$fixture/payload/safe" bash "$audit" "$fixture/payload" > "$fixture/output" 2>&1; then
    echo 'Incomplete traversal was accepted' >&2; exit 1
fi
[[ -z $(find "$fixture/temp" -mindepth 1 -print -quit) ]]
if grep -q '^Extracted target payload:' "$fixture/output"; then
    echo 'Incomplete traversal printed a success receipt' >&2; exit 1
fi
rm "$fixture/bin/find" "$fixture/payload/omitted"
# A live subtree must be refused before even file discovery. Paths with the
# same prefix outside the target must not hide ordinary payload files.
cat > "$fixture/bin/findmnt" <<'SH'
#!/usr/bin/env bash
case $UKE_FIXTURE_MOUNTS in
 failure) exit 1;;
 malformed) printf '{"filesystems":null}\n';;
 empty) printf '{"filesystems":[]}\n';;
 nested) jq -n --arg path "$UKE_FIXTURE_ROOT/proc" '{filesystems:[{target:"/"},{target:$path}]}' ;;
 adjacent) jq -n --arg path "$UKE_FIXTURE_ROOT-other/proc" '{filesystems:[{target:"/"},{target:$path}]}' ;;
esac
SH
cat > "$fixture/bin/find" <<'SH'
#!/usr/bin/env bash
touch "$UKE_FIXTURE_DISCOVERY"
exit 97
SH
chmod +x "$fixture/bin/findmnt" "$fixture/bin/find"
for mode in failure malformed empty nested; do
 if PATH="$fixture/bin:$PATH" UKE_FIXTURE_ROOT="$fixture/payload" UKE_FIXTURE_MOUNTS=$mode \
    UKE_FIXTURE_DISCOVERY="$fixture/discovered" bash "$audit" "$fixture/payload" > "$fixture/output" 2>&1; then exit 1; fi
 [[ ! -e $fixture/discovered ]]
 if grep -q '^Extracted target payload:' "$fixture/output"; then exit 1; fi
done
rm "$fixture/bin/find"
PATH="$fixture/bin:$PATH" UKE_FIXTURE_ROOT="$fixture/payload" UKE_FIXTURE_MOUNTS=adjacent bash "$audit" "$fixture/payload" >/dev/null
rm "$fixture/bin/findmnt"
# Ordinary files under proc are still real payload when no mount hides them.
mkdir "$fixture/payload/proc"
printf '#!/usr/bin/python3\n' > "$fixture/payload/proc/unapproved"
if bash "$audit" "$fixture/payload" >/dev/null 2>&1; then exit 1; fi
rm "$fixture/payload/proc/unapproved"
# Permission-bit checks alone do not detect I/O errors from readable files.
cat > "$fixture/read-fault" <<'SH'
read() {
 for argument in "$@"; do
  if [[ $argument == -n ]]; then printf 'injected read I/O error\n' >&2; return 1; fi
 done
 builtin read "$@"
}
SH
if BASH_ENV="$fixture/read-fault" bash "$audit" "$fixture/payload" > "$fixture/output" 2>&1; then exit 1; fi
grep -F 'Unreadable target header rejected:' "$fixture/output" >/dev/null
if grep -q '^Extracted target payload:' "$fixture/output"; then exit 1; fi
# Keep NUL-safe enumeration and the real ELF decoder on ordinary data.
cp /bin/true "$fixture/payload/ELF with space"
printf '#!/bin/sh\n' > "$fixture/payload/line"$'\n'"break"
bash "$audit" "$fixture/payload" >/dev/null
printf '\177ELFbad' > "$fixture/payload/broken"
if bash "$audit" "$fixture/payload" >/dev/null 2>&1; then exit 1; fi
rm "$fixture/payload/broken"
cat > "$fixture/bin/readelf" <<'SH'
#!/usr/bin/env bash
case $UKE_FIXTURE_DYNAMIC in
  failure) exit 1;;
  python) printf '  0x01 (NEEDED) Shared library: [libpython3.15.so]\n';;
  cross-line) printf '  0x01 (NEEDED) Shared library: [libc.so]\nlibpython unrelated text\n';;
  ordinary) printf '  0x01 (NEEDED) Shared library: [libc.so]\n';;
esac
SH
chmod +x "$fixture/bin/readelf"
for mode in failure python; do
 if PATH="$fixture/bin:$PATH" UKE_FIXTURE_DYNAMIC=$mode bash "$audit" "$fixture/payload" >/dev/null 2>&1; then exit 1; fi
done
for mode in cross-line ordinary; do
 PATH="$fixture/bin:$PATH" UKE_FIXTURE_DYNAMIC=$mode bash "$audit" "$fixture/payload" >/dev/null
done
echo 'Mount/read/traversal failures, ordinary proc payload, NUL-safe names, malformed ELF and Python dependency checks passed'
