#!/usr/bin/env bash
# Exact-owner repair controls; no network, target execution or RPM transaction.
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/public/languages.sh
# shellcheck disable=SC1091
source "$repo/src/public/languages.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/root/usr/share/locale/tr/LC_MESSAGES" "$work/root/usr/share/help/tr/example"
mkdir -p "$work/root/usr/share/qt6/translations"
printf '/usr/share/locale/tr/LC_MESSAGES/libc.mo\t0\ttr\t33188\tglibc-2.44-1.fc46.aarch64\n/usr/share/help/tr/example/index.page\t2\ttr\t33188\texample-1.0-2.fc46.noarch\n' > "$work/files.tsv"
printf '/usr/share/qt6/translations/qt_tr.qm\t0\t\t33188\texample-1.0-2.fc46.noarch\n' >> "$work/files.tsv"
cp "$work/files.tsv" "$work/original.tsv"
printf 'tr_TR.utf8\n' > "$work/locales"
calls=0
public_root_transaction() {
    [[ $1 == "$work/root" && $6 == reinstall && $3 == fixture_dnf ]]
    local -n requested=$5
    [[ ${requested[*]} == 'example-1.0-2.fc46.noarch glibc-2.44-1.fc46.aarch64' ]]
    calls=$((calls+1))
    [[ ${transaction_failure:-0} == 0 ]] || return 1
    [[ ${omit_after_reinstall:-0} == 0 ]] || return 0
    printf 'catalog\n' > "$work/root/usr/share/locale/tr/LC_MESSAGES/libc.mo"
    printf 'help\n' > "$work/root/usr/share/help/tr/example/index.page"
    printf 'Qt catalog\n' > "$work/root/usr/share/qt6/translations/qt_tr.qm"
}
public_language_inventory() { [[ $1 == "$work/root" ]]; cp "$work/original.tsv" "$2"; cp "$work/locales" "$3.next"; mv "$3.next" "$3"; }
repair() { public_language_repair "$work/root" "$work/files.tsv" "$work/locales" fixture_dnf "$work/repair.log" "$work/receipt.json"; }
reject() { if (repair) > "$work/refused" 2>&1; then echo 'Incomplete language repair accepted' >&2; exit 1; fi; }
repair
[[ $calls == 1 ]]
jq -e '.exact_rpm_owners_reinstalled==["example-1.0-2.fc46.noarch","glibc-2.44-1.fc46.aarch64"] and .missing_translated_paths_after_repair==0 and .includes_localized_documentation' "$work/receipt.json" >/dev/null
repair
[[ $calls == 1 ]]
rm "$work/root/usr/share/locale/tr/LC_MESSAGES/libc.mo" "$work/root/usr/share/help/tr/example/index.page"
rm "$work/root/usr/share/qt6/translations/qt_tr.qm"
omit_after_reinstall=1; reject; unset omit_after_reinstall
transaction_failure=1; reject; unset transaction_failure
sed 's/glibc-2.44-1.fc46.aarch64/--unsafe/' "$work/original.tsv" > "$work/files.tsv"
reject
echo 'Missing runtime and DOC translations restore only exact RPM owners; repeat is a no-op; unsafe owners, failed reinstall and residual missing files reject.'
