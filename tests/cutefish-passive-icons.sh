#!/usr/bin/env bash
# Artwork is not a Python runtime. Proof, file bytes and link containment matter.
set -Eeuo pipefail
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
audit=$builder/src/audit/check-target-payload.sh
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
relative=usr/share/icons/Cutefish/apps/scalable
mkdir -p "$work/root/$relative" "$work/proof/$relative"
svg='<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0"/></svg>'
printf '%s\n' "$svg" > "$work/root/$relative/python.svg"
cp "$work/root/$relative/python.svg" "$work/proof/$relative/python.svg"
ln -s python.svg "$work/root/$relative/python3.10.svg"
ln -s python.svg "$work/proof/$relative/python3.10.svg"
reject() { if "$@" > "$work/rejected" 2>&1; then echo "Unsafe icon exception accepted: $*" >&2; exit 1; fi; }
reject bash "$audit" "$work/root"
bash "$audit" --verified-cutefish-payload "$work/proof" "$work/root" >/dev/null
printf '<svg xmlns="http://www.w3.org/2000/svg"><image href="data:image/png;base64,aGVsbG8="/></svg>\n' > "$work/root/$relative/python.svg"
cp "$work/root/$relative/python.svg" "$work/proof/$relative/python.svg"
bash "$audit" --verified-cutefish-payload "$work/proof" "$work/root" >/dev/null
for resource in 'https://example.com/icon.png' 'data:image/svg+xml;base64,aGVsbG8='; do
  printf '<svg xmlns="http://www.w3.org/2000/svg"><image href="%s"/></svg>\n' "$resource" > "$work/root/$relative/python.svg"
  cp "$work/root/$relative/python.svg" "$work/proof/$relative/python.svg"
  reject bash "$audit" --verified-cutefish-payload "$work/proof" "$work/root"
done
printf '<svg xmlns="http://www.w3.org/2000/svg"><script>bad()</script></svg>\n' > "$work/root/$relative/python.svg"
cp "$work/root/$relative/python.svg" "$work/proof/$relative/python.svg"
reject bash "$audit" --verified-cutefish-payload "$work/proof" "$work/root"
printf '#!/usr/bin/python3\nprint("script")\n' > "$work/root/$relative/python.svg"
cp "$work/root/$relative/python.svg" "$work/proof/$relative/python.svg"
reject bash "$audit" --verified-cutefish-payload "$work/proof" "$work/root"
printf '%s\n' "$svg" > "$work/root/$relative/python.svg"
cp "$work/root/$relative/python.svg" "$work/proof/$relative/python.svg"
chmod +x "$work/root/$relative/python.svg"
reject bash "$audit" --verified-cutefish-payload "$work/proof" "$work/root"
chmod -x "$work/root/$relative/python.svg"
printf 'changed artwork\n' > "$work/root/$relative/python.svg"
reject bash "$audit" --verified-cutefish-payload "$work/proof" "$work/root"
printf '%s\n' "$svg" > "$work/root/$relative/python.svg"
rm "$work/root/$relative/python3.10.svg" "$work/proof/$relative/python3.10.svg"
printf '%s\n' "$svg" > "$work/outside.svg"
ln -s "$work/outside.svg" "$work/root/$relative/python3.10.svg"
ln -s "$work/outside.svg" "$work/proof/$relative/python3.10.svg"
reject bash "$audit" --verified-cutefish-payload "$work/proof" "$work/root"
rm "$work/root/$relative/python3.10.svg" "$work/proof/$relative/python3.10.svg"
printf '#!/usr/bin/python3\n' > "$work/root/$relative/unapproved.py"
cp "$work/root/$relative/unapproved.py" "$work/proof/$relative/unapproved.py"
reject bash "$audit" --verified-cutefish-payload "$work/proof" "$work/root"
echo 'Only byte-identical nonexecutable passive SVG icons pass; scripts, active SVG, changed bytes and escaping links reject.'
