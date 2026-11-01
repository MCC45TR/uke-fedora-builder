#!/usr/bin/env bash
# Real tiny tar/readback fixtures; native metadata code is separately exercised
# by image assembly. Prove that matching archives cannot excuse missing locales.
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/public/root-metadata.sh
# shellcheck disable=SC1091
source "$repo/src/public/root-metadata.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/root/usr/share/locale/tr/LC_MESSAGES" "$work/root/usr/share/help/tr/example" "$work/artifacts"
printf 'catalog\n' > "$work/root/usr/share/locale/tr/LC_MESSAGES/libc.mo"
printf 'localized help\n' > "$work/root/usr/share/help/tr/example/index.page"
printf '/usr/share/locale/tr/LC_MESSAGES/libc.mo\t0\ttr\n/usr/share/help/tr/example/index.page\t2\ttr\n' > "$work/artifacts/rpm-language-files.tsv"
printf 'tr_TR.utf8\n' > "$work/artifacts/supported-locales.txt"
id() { [[ $1 == -u ]]; printf '0\n'; }
seal() {
    tar --create --format=posix --numeric-owner -f "$work/original.tar" -C "$work/root" .
    cp "$work/original.tar" "$work/readback.tar"
}
run() { public_root_compare "$work/root" "$work/original.tar" "$work/readback.tar" "$work" /usr/bin/true "$work/artifacts" core; }
seal
run
jq -e '.schema==2 and .documentation_translations_included and .missing_localized_paths==0' "$work/artifacts/serialized-language-audit.json" >/dev/null
rm "$work/root/usr/share/help/tr/example/index.page"
seal
if run > "$work/refused" 2>&1; then echo 'Matching serialized archives with missing translated DOC payload accepted' >&2; exit 1; fi
grep -Fq '/usr/share/help/tr/example/index.page' "$work/refused"
echo 'Independent readback re-audits all RPM translations; matching archive metadata cannot excuse omitted localized help.'
