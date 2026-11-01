#!/usr/bin/env bash
# Host-side RPM language policy and offline payload audit, shared by every DE.
public_language_policy() {
    local macros=${1:-/etc/rpm}
    mkdir -p "$macros" || return
    printf '%%_install_langs all\n' > "$macros/macros.zz-uke-languages" || return
    [[ $(rpm --eval '%{_install_langs}') == all ]] || {
        echo 'RPM still filters installed languages; root composition refused' >&2
        return 1
    }
}

public_language_audit() {
    local root=$1 inventory=$2 desktop=$3 locales=$4 output=$5 listing path _flags _language status
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
    # RPM flags: documentation=2, ghost=64. Documentation is deliberately
    # omitted; translated runtime files must survive the nodocs transaction.
    if ! LC_ALL=C awk -F '\t' '
        NF!=3 || $1!~/^\// || $1~/\/\.\.?($|\/)/ || $2!~/^[0-9]+$/ {exit 1}
        {
            flags=$2+0
            # GNOME help directories can carry a language tag without the doc
            # flag even when their children are documentation. RPM nodocs omits
            # those directories too; they are not runtime UI catalogs.
            if (int(flags/64)%2 || int(flags/2)%2 || $1~/^\/usr\/share\/(doc|man|info|help|gnome\/help)\//) next
            if (($3!="" && $3!="(none)") || $1~/^\/usr\/share\/locale\// || $1~/^\/usr\/share\/qt[56]\/translations\//) print
        }' "$inventory" > "$listing"; then
        rm -f "$listing"
        echo 'Invalid RPM language file inventory' >&2
        return 1
    fi
    while IFS=$'\t' read -r path _flags _language; do
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
        '{schema:1,desktop:$desktop,rpm_install_languages:"all",localized_paths_checked:$checked,
          turkish_catalogs:$turkish,missing_localized_paths:0,turkish_utf8_locale:true,locale_directories:$directories,
          plasmashell_catalogs:$shell,plasma_setup_catalogs:$setup,plasmalogin_catalogs:$login,qt_translation_paths:$qt}' > "$output"
}

public_language_receipt() {
    jq -e '.schema==1 and .desktop=="core" and .rpm_install_languages=="all" and
        .localized_paths_checked>0 and .turkish_catalogs>0 and .missing_localized_paths==0 and
        .turkish_utf8_locale==true' "$1" >/dev/null
}
