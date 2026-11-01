#!/usr/bin/env bash
# Audit actual installed NEVRAs, distinguishing shared libraries from sessions.
public_desktop_isolation() {
    local inventory=$1 desktop=$2 package
    local required=() forbidden=()
    [[ -s $inventory ]] || return 1
    case $desktop in
        core)
            # shellcheck source=shared-core.sh
            # shellcheck disable=SC1091
            source /builder/src/public/shared-core.sh
            public_core_desktop_free "$inventory" || return;;
        kde|plasma-mobile)
            required=(plasma-workspace plasma-setup)
            forbidden=(gnome-shell gdm cutefish-desktop nextkde);;
        gnome)
            required=(gnome-shell gdm gnome-initial-setup)
            forbidden=(plasma-workspace plasma-setup uke-kde-plasma-meta cutefish-desktop nextkde);;
        cutefish)
            required=(cutefish-desktop gdm)
            forbidden=(plasma-workspace plasma-setup uke-kde-plasma-meta nextkde)
            # Fedora GDM itself requires GNOME Shell/session packages.
            ;;
        nextkde)
            required=(plasma-workspace plasma-setup nextkde quickshell)
            forbidden=(gnome-shell gdm cutefish-desktop);;
        *) return 1;;
    esac
    for package in "${required[@]}"; do
        LC_ALL=C grep -qE "^$package-[0-9]" "$inventory" || { printf 'Missing selected desktop package: %s\n' "$package" >&2; return 1; }
    done
    for package in "${forbidden[@]}"; do
        if LC_ALL=C grep -E "^$package-[0-9]" "$inventory"; then
            printf 'Unrelated desktop session in %s image: %s\n' "$desktop" "$package" >&2
            return 1
        fi
    done
    printf 'Desktop isolation verified: %s; shared libraries permitted; GDM GNOME greeter/session dependencies permitted for Cutefish.\n' "$desktop"
}
