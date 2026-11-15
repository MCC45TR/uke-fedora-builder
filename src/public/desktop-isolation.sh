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
        plasma-mobile)
            required=(plasma-workspace plasma-setup plasma-mobile plasma-settings plasma-keyboard plasma-lookandfeel-fedora-mobile)
            forbidden=(gnome-shell gdm cutefish-desktop nextkde uke-kde-plasma-meta);;
        kde)
            required=(plasma-workspace plasma-setup)
            forbidden=(gnome-shell gdm cutefish-desktop nextkde);;
        gnome)
            required=(gnome-shell gdm gnome-initial-setup)
            forbidden=(plasma-workspace plasma-setup uke-kde-plasma-meta cutefish-desktop nextkde);;
        cutefish)
            # shellcheck source=cutefish-profile.sh
            # shellcheck disable=SC1091
            source "$(dirname -- "${BASH_SOURCE[0]}")/cutefish-profile.sh"
            local selected_cutefish
            selected_cutefish=$(public_cutefish_profile '.required_packages[]') || return
            mapfile -t required <<< "$selected_cutefish"
            # Inspect every transitive NEVRA, including libraries and portals.
            if LC_ALL=C grep -E '^(plasma-|plasma5support-|kwin|kde|kf[56]-|kio-|sddm|breeze|dolphin|konsole-|spectacle-|okular|gwenview-|ark-|bluedevil-|kinfocenter-|kdialog-|kscreen-|kcm-|powerdevil-|libplasma-|uke-kde-plasma-meta-|uke-plasma-controls-|gdm-|gnome-shell-|gnome-session|xdg-desktop-portal-(kde|gnome)-|nextkde-)' "$inventory"; then
                echo 'Forbidden desktop dependency in Cutefish root' >&2; return 1
            fi
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
    printf 'Desktop isolation verified: %s; shared libraries permitted; installed transitive closure checked.\n' "$desktop"
}
