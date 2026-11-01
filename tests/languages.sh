#!/usr/bin/env bash
# Catch the released-image regression: installed RPM names do not prove that
# RPM retained their translated runtime files.
set -Eeuo pipefail
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/public/languages.sh
# shellcheck disable=SC1091
source "$builder/src/public/languages.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
reject() { if (set -Eeuo pipefail; "$@") > "$work/rejected" 2>&1; then echo "Incomplete languages accepted: $*" >&2; exit 1; fi; }
mkdir -p "$work/base/usr/share/locale/tr/LC_MESSAGES" "$work/base/usr/lib/locale" "$work/base/usr/share/doc/example"
mkdir -p "$work/base/usr/share/help/tr/malcontent" "$work/base/usr/share/help/de/example" "$work/base/usr/share/gnome/help/example/tr"
printf 'translated documentation\n' > "$work/base/usr/share/doc/example/tr.txt"
printf 'translated help\n' > "$work/base/usr/share/help/de/example/index.page"
printf 'Turkish libc messages\n' > "$work/base/usr/share/locale/tr/LC_MESSAGES/libc.mo"
printf 'all-language archive fixture\n' > "$work/base/usr/lib/locale/locale-archive"
printf '/usr/lib/locale/locale-archive\t0\t(none)\n/usr/share/locale/tr/LC_MESSAGES/libc.mo\t0\ttr\n/usr/share/doc/example/tr.txt\t2\ttr\n/ghost\t64\ttr\n' > "$work/base.tsv"
# Real GNOME RPMs tag localized help directories without %%doc on the directory;
# nodocs removes them together with their documented children.
printf '/usr/share/help/tr/malcontent\t0\ttr\t16877\n/usr/share/help/de/example/index.page\t2\tde\t33188\n/usr/share/gnome/help/example/tr\t0\ttr\t16877\n' >> "$work/base.tsv"
printf 'C\nC.utf8\nen_US.utf8\ntr_TR.utf8\n' > "$work/locales"
for desktop in core kde nextkde plasma-mobile gnome cutefish; do
    cp -a "$work/base" "$work/$desktop"
    cp "$work/base.tsv" "$work/$desktop.tsv"
    case $desktop in
        core) catalogs='';;
        kde|nextkde|plasma-mobile) catalogs='org.kde.plasmasetup.mo plasma_login.mo plasmashell.mo';;
        gnome) catalogs='gnome-initial-setup.mo gnome-shell.mo gdm.mo';;
        cutefish) catalogs='gnome-shell.mo gdm.mo mutter.mo';;
    esac
    for catalog in $catalogs; do
        printf 'catalog payload\n' > "$work/$desktop/usr/share/locale/tr/LC_MESSAGES/$catalog"
        printf '/usr/share/locale/tr/LC_MESSAGES/%s\t0\ttr\n' "$catalog" >> "$work/$desktop.tsv"
    done
    case $desktop in
        kde|nextkde|plasma-mobile)
            for ((n=0;n<80;n++)); do
                dir=/usr/share/locale/fixture_$n/LC_MESSAGES
                mkdir -p "$work/$desktop$dir"
                for catalog in plasmashell.mo org.kde.plasmasetup.mo plasma_login.mo; do
                    printf 'catalog\n' > "$work/$desktop$dir/$catalog"
                    printf '%s/%s\t0\tfixture\n' "$dir" "$catalog" >> "$work/$desktop.tsv"
                done
            done;;
    esac
    public_language_audit "$work/$desktop" "$work/$desktop.tsv" "$desktop" "$work/locales" "$work/$desktop.json"
    # Locale archive/package presence still cannot excuse stripped catalogs.
    rm "$work/$desktop/usr/share/locale/tr/LC_MESSAGES/libc.mo"
    reject public_language_audit "$work/$desktop" "$work/$desktop.tsv" "$desktop" "$work/locales" "$work/rejected.json"
    cp "$work/base/usr/share/locale/tr/LC_MESSAGES/libc.mo" "$work/$desktop/usr/share/locale/tr/LC_MESSAGES/"
done
public_language_receipt "$work/core.json"
jq '.schema=1 | del(.documentation_translations_included)' "$work/core.json" > "$work/runtime-only.json"
reject public_language_receipt "$work/runtime-only.json"
rm "$work/core/usr/share/doc/example/tr.txt"
reject public_language_audit "$work/core" "$work/core.tsv" core "$work/locales" "$work/rejected.json"
cp "$work/base/usr/share/doc/example/tr.txt" "$work/core/usr/share/doc/example/tr.txt"
cp "$work/core.tsv" "$work/non-doc-help.tsv"
printf '/usr/share/help/tr/runtime/translated.page\t0\ttr\t33188\n' >> "$work/non-doc-help.tsv"
reject public_language_audit "$work/core" "$work/non-doc-help.tsv" core "$work/locales" "$work/rejected.json"
cp "$work/core.tsv" "$work/untyped-help.tsv"
printf '/usr/share/help/tr/untyped\t0\ttr\n' >> "$work/untyped-help.tsv"
reject public_language_audit "$work/core" "$work/untyped-help.tsv" core "$work/locales" "$work/rejected.json"
printf '{"glibc_all_langpacks_installed":true}\n' > "$work/package-only.json"
reject public_language_receipt "$work/package-only.json"
printf 'C\nen_US.utf8\n' > "$work/english-only"
reject public_language_audit "$work/core" "$work/core.tsv" core "$work/english-only" "$work/rejected.json"
: > "$work/kde/usr/share/locale/tr/LC_MESSAGES/org.kde.plasmasetup.mo"
reject public_language_audit "$work/kde" "$work/kde.tsv" kde "$work/locales" "$work/rejected.json"
printf '/usr/share/locale/../outside\t0\ttr\n' > "$work/unsafe.tsv"
reject public_language_audit "$work/core" "$work/unsafe.tsv" core "$work/locales" "$work/rejected.json"
printf '/usr/share/qt6/translations/qt_tr.qm\t0\t(none)\n' >> "$work/core.tsv"
reject public_language_audit "$work/core" "$work/core.tsv" core "$work/locales" "$work/rejected.json"
mkdir "$work/bin" "$work/macros"
cat > "$work/bin/rpm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case $* in
    '--eval %{_install_langs}') macro=%_install_langs;;
    '--eval %{_excludedocs}') macro=%_excludedocs;;
    *) exit 1;;
esac
if [[ ${UKE_TEST_LANGUAGE_STUCK:-0} == 1 ]]; then printf 'en_US\n'; exit; fi
awk -v macro="$macro" '$1==macro{value=$2} END{print value}' "$UKE_TEST_LANGUAGE_MACROS"/macros.*
SH
chmod +x "$work/bin/rpm"
export PATH="$work/bin:$PATH" UKE_TEST_LANGUAGE_MACROS=$work/macros
printf '%%_install_langs en_US\n' > "$work/macros/macros.image-language-conf"
public_language_policy "$work/macros"
[[ $(rpm --eval '%{_install_langs}') == all ]]
[[ $(rpm --eval '%{_excludedocs}') == 0 ]]
export UKE_TEST_LANGUAGE_STUCK=1
reject public_language_policy "$work/macros"
echo 'All DEs require complete RPM translations including help/docs; ghost entries alone are exempt; missing catalogs, Qt payloads, docs, locales and surviving host filters reject.'
