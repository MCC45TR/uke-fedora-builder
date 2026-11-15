#!/usr/bin/env bash
# Source-only policy checks; no DNF, compiler, container or target execution.
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../src/public/root-packages.sh
# shellcheck disable=SC1091
source "$root/src/public/root-packages.sh"
contains() { local value; for value in "${packages[@]}"; do [[ $value != "$1" ]] || return 0; done; return 1; }
for channel in stable testing unstable; do
    for desktop in core kde plasma-mobile gnome cutefish nextkde; do
        for login_shell in bash fish zsh; do
            if [[ $desktop == cutefish && $channel != unstable ]]; then
                if public_root_packages packages rawhide "$channel" "$desktop" "$login_shell"; then exit 1; fi
                continue
            fi
            public_root_packages packages rawhide "$channel" "$desktop" "$login_shell"
            contains "$login_shell"
            contains fedora-repos-rawhide
            contains uke-touchscreen
            contains uke-firmware
            contains uke-offline-charge
            if [[ $channel == unstable ]]; then
                contains uke-core-meta
                contains uke-pipewire
                contains uke-pipewire-pulseaudio
                if contains uke-additional || contains uke-core || contains uke-hw || contains uke-power || contains uke-sensors; then exit 1; fi
                if contains pipewire || contains pipewire-pulseaudio; then exit 1; fi
            else
                contains uke-additional
                contains pipewire
                contains pipewire-pulseaudio
            fi
            if [[ $desktop == kde || $desktop == plasma-mobile || $desktop == nextkde ]]; then
                contains plasma-setup
                [[ $desktop != nextkde ]] || { contains nextkde; contains quickshell; }
                if [[ $desktop == plasma-mobile ]]; then contains plasma-mobile; contains plasma-settings; contains plasma-keyboard; contains qmlkonsole; if contains uke-kde-plasma-meta; then exit 1; fi; fi
                if contains gdm; then exit 1; fi
            elif [[ $desktop == gnome ]]; then
                contains gnome-initial-setup
                if contains plasma-setup; then exit 1; fi
            elif [[ $desktop == cutefish ]]; then
                contains cutefish-desktop
                contains cutefish-dm
                contains uke-cutefish-firstboot
                contains uke-cutefish-session-config
                contains cutefish-preview
                contains wvkbd
                contains dbus-daemon
                if contains gdm; then exit 1; fi
                if contains gnome-initial-setup || contains plasma-setup; then exit 1; fi
            else
                if contains gdm || contains plasma-setup || contains nextkde || contains cutefish-desktop; then exit 1; fi
            fi
        done
    done
done
for release in 44 45; do
    public_root_packages packages "$release" testing kde bash
    if contains fedora-repos-rawhide; then exit 1; fi
done
for choice in '43 unstable kde bash' 'rawhide invalid kde bash' 'rawhide unstable nonexistent bash' 'rawhide unstable kde /bin/sh'; do
    packages=(keep-previous-selection)
    # Fixed source fixture arguments, intentionally split.
    # shellcheck disable=SC2086
    if public_root_packages packages $choice; then exit 1; fi
    [[ ${packages[*]} == keep-previous-selection ]]
done
for profile in normal unstable el2-require; do
    excluded=$(public_root_exclusions "$profile")
    [[ $excluded == *uke-local-touch-data* && $excluded == *uke-video-firmware-local* ]]
    IFS=, read -r -a patterns <<< "$excluded"
    for component in '' -core -modules -dtbs -boot -singleboot; do
        for family in senemos-uke-linux-kernel-mainline senemos-uke-linux-kernel-mainline-unstable senemos-uke-linux-kernel-mainline-kvm; do
            blocked=0
            for pattern in "${patterns[@]}"; do
                # Intentional matching against the actual DNF exclude globs.
                # shellcheck disable=SC2053
                [[ $family$component != $pattern ]] || blocked=1
            done
            case $profile in
                normal) selected_family=senemos-uke-linux-kernel-mainline;;
                unstable) selected_family=senemos-uke-linux-kernel-mainline-unstable;;
                el2-require) selected_family=senemos-uke-linux-kernel-mainline-kvm;;
            esac
            if [[ $family == "$selected_family" ]]; then ((blocked == 0)); else ((blocked == 1)); fi
        done
    done
done
if public_root_exclusions invalid; then exit 1; fi
echo 'Original desktop, firmware, shell and channel selections retained; invalid inputs leave the selection unchanged.'
