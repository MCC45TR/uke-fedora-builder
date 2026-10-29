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
echo 'Traversal failure, NUL-safe names, real malformed ELF, decoder failure and line-bounded Python dependency checks passed'
