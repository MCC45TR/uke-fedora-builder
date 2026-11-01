#!/usr/bin/env bash
# Host-side RPM language policy and offline payload audit, shared by every DE.
public_language_policy() {
    local macros=${1:-/etc/rpm}
    mkdir -p "$macros" || return
    printf '%%_install_langs all\n%%_excludedocs 0\n' > "$macros/macros.zz-uke-languages" || return
    [[ $(rpm --eval '%{_install_langs}') == all && $(rpm --eval '%{_excludedocs}') == 0 ]] || {
        echo 'RPM still filters installed languages or documentation; root composition refused' >&2
        return 1
    }
}

public_language_inventory() {
    rpm --root "$1" -qa --qf '[%{FILENAMES}\t%{FILEFLAGS}\t%{FILELANGS}\t%{FILEMODES}\t%{=NEVRA}\n]' > "$2" || return
    chroot "$1" /usr/bin/locale -a > "$3"
}

public_language_candidates() {
    LC_ALL=C awk -F '\t' '
        (NF<3 || NF>5) || $1!~/^\// || $1~/\/\.\.?($|\/)/ || $2!~/^[0-9]+$/ || (NF>=4 && $4!~/^[0-9]+$/) {exit 1}
        {
            # Only genuine RPM ghost entries lack an installed payload.
            if (int(($2+0)/64)%2) next
            if (($3!="" && $3!="(none)") || $1~/^\/usr\/share\/(locale|help|gnome\/help)\// || $1~/^\/usr\/share\/qt[56]\/translations\//) print
        }' "$1"
}

# Restore missing translations from their exact installed RPM versions, using
# the caller's signature-enforcing repositories and ordinary scriptlet checks.
public_language_repair() {
    local root=$1 inventory=$2 locales=$3 dnf_name=$4 log=$5 output=$6 listing record path owner json invalid=0
    local -A owners=()
    # Consumed by public_root_transaction through the array name.
    # shellcheck disable=SC2034
    local -a repair_rpms=()
    local -a repair_packages=()
    listing=$(mktemp) || return
    if ! public_language_candidates "$inventory" > "$listing"; then rm -f "$listing"; return 1; fi
    while IFS= read -r record; do
        path=${record%%$'\t'*}; owner=${record##*$'\t'}
        [[ ! -e $root$path && ! -L $root$path ]] || continue
        [[ $owner =~ ^[A-Za-z0-9][A-Za-z0-9._+~^:-]*[.](aarch64|noarch)$ ]] || {
            echo 'Missing translation has no exact RPM owner identity' >&2; invalid=1; break;
        }
        owners[$owner]=1
    done < "$listing"
    if ((invalid)); then rm -f "$listing"; return 1; fi
    if ((${#owners[@]})); then
        mapfile -t repair_packages < <(printf '%s\n' "${!owners[@]}" | LC_ALL=C sort)
        public_root_transaction "$root" "$log" "$dnf_name" repair_rpms repair_packages reinstall || { rm -f "$listing"; return 1; }
        public_language_inventory "$root" "$inventory" "$locales" || { rm -f "$listing"; return 1; }
        public_language_candidates "$inventory" > "$listing" || { rm -f "$listing"; return 1; }
        while IFS= read -r record; do
            path=${record%%$'\t'*}
            [[ -e $root$path || -L $root$path ]] || {
                printf 'Translation still missing after exact-owner reinstall: %s\n' "$path" >&2
                invalid=1; break;
            }
        done < "$listing"
        if ((invalid)); then rm -f "$listing"; return 1; fi
    fi
    rm -f "$listing"
    json='[]'
    if ((${#repair_packages[@]})); then json=$(printf '%s\n' "${repair_packages[@]}" | jq -Rsc 'split("\n")[:-1]') || return; fi
    jq -n --argjson owners "$json" '{exact_rpm_owners_reinstalled:$owners,missing_translated_paths_after_repair:0,
        includes_localized_documentation:true,signature_policy:"unchanged caller repositories"}' > "$output"
}

public_language_audit() {
    local root=$1 inventory=$2 desktop=$3 locales=$4 output=$5 listing path _flags _language _mode status
    local checked=0 turkish=0 missing=0 required catalog locale shell=0 setup=0 login=0 qt=0
    local -A directories=()
    case $desktop in
        core) required='';;
        kde|nextkde|plasma-mobile) required='org.kde.plasmasetup.mo plasma_login.mo plasmashell.mo';;
        gnome) required='gnome-initial-setup.mo gnome-shell.mo gdm.mo';;
        cutefish) required='gnome-shell.mo gdm.mo mutter.mo';;
        *) return 1;;
    esac
    [[ -d $root && ! -L $root && -s $inventory && -s $locales && $root != / ]] || return 1
    LC_ALL=C grep -Eiq '^tr_TR\.(utf-?8)$' "$locales" || {
        echo 'Turkish UTF-8 locale missing from the installed glibc payload' >&2
        return 1
    }
    listing=$(mktemp) || return
    # Include translated documentation and its directory entries too. Locale
    # sentinels supplement this complete RPM inventory; they never replace it.
    if ! public_language_candidates "$inventory" > "$listing"; then
        rm -f "$listing"
        echo 'Invalid RPM language file inventory' >&2
        return 1
    fi
    while IFS=$'\t' read -r path _flags _language _mode; do
        checked=$((checked + 1))
        if [[ ! -e $root$path && ! -L $root$path ]]; then
            # Bound the diagnostics while retaining the full failure count.
            if ((missing < 12)); then printf 'Missing installed translation: %s\n' "$path" >&2; fi
            missing=$((missing + 1))
        fi
        [[ $path != /usr/share/locale/tr/LC_MESSAGES/* ]] || turkish=$((turkish + 1))
        if [[ $path == /usr/share/locale/*/* ]]; then
            locale=${path#/usr/share/locale/}; directories[${locale%%/*}]=1
            case $path in
                */plasmashell.mo) shell=$((shell+1));;
                */org.kde.plasmasetup.mo) setup=$((setup+1));;
                */plasma_login.mo) login=$((login+1));;
            esac
        fi
        [[ $path != /usr/share/qt[56]/translations/* ]] || qt=$((qt+1))
    done < "$listing"
    rm -f "$listing"
    [[ $checked -gt 0 && $turkish -gt 0 && $missing == 0 ]] || {
        printf 'Incomplete language payload: checked=%d Turkish=%d missing=%d\n' "$checked" "$turkish" "$missing" >&2
        return 1
    }
    for catalog in $required; do
        path=/usr/share/locale/tr/LC_MESSAGES/$catalog
        [[ -s $root$path && ! -L $root$path ]] || {
            printf 'Required Turkish desktop catalog missing or empty: %s\n' "$path" >&2
            return 1
        }
        # Do not admit an empty placeholder that RPM never declared.
        if LC_ALL=C awk -F '\t' -v path="$path" '$1==path {found=1} END {exit !found}' "$inventory"; then :
        else status=$?; return "$status"; fi
    done
    case $desktop in
        kde|nextkde|plasma-mobile)
            (( ${#directories[@]} >= 80 && shell >= 40 && setup >= 30 && login >= 30 )) || {
                echo 'KDE language breadth below the retained multilingual policy' >&2; return 1;
            };;
    esac
    jq -n --arg desktop "$desktop" --argjson checked "$checked" --argjson turkish "$turkish" \
        --argjson directories "${#directories[@]}" --argjson shell "$shell" --argjson setup "$setup" --argjson login "$login" --argjson qt "$qt" \
        '{schema:2,desktop:$desktop,rpm_install_languages:"all",localized_paths_checked:$checked,
          documentation_translations_included:true,
          turkish_catalogs:$turkish,missing_localized_paths:0,turkish_utf8_locale:true,locale_directories:$directories,
          plasmashell_catalogs:$shell,plasma_setup_catalogs:$setup,plasmalogin_catalogs:$login,qt_translation_paths:$qt}' > "$output"
}

public_language_receipt() {
    jq -e '.schema==2 and .documentation_translations_included==true and .desktop=="core" and .rpm_install_languages=="all" and
        .localized_paths_checked>0 and .turkish_catalogs>0 and .missing_localized_paths==0 and
        .turkish_utf8_locale==true' "$1" >/dev/null
}
