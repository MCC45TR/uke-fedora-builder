#!/usr/bin/env bash
# Source-only policy checks; no DNF, compiler, container or target execution.
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../src/public/root-packages.sh
# shellcheck disable=SC1091
source "$root/src/public/root-packages.sh"
contains() { local value; for value in "${packages[@]}"; do [[ $value != "$1" ]] || return 0; done; return 1; }
for channel in stable testing unstable; do
    for desktop in kde gnome; do
        for login_shell in bash fish zsh; do
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
            if [[ $desktop == kde ]]; then
                contains plasma-setup
                if contains gdm; then exit 1; fi
            else
                contains gnome-initial-setup
                if contains plasma-setup; then exit 1; fi
            fi
        done
    done
done
for release in 44 45; do
    public_root_packages packages "$release" testing kde bash
    if contains fedora-repos-rawhide; then exit 1; fi
done
for choice in '43 unstable kde bash' 'rawhide invalid kde bash' 'rawhide unstable cutefish bash' 'rawhide unstable kde /bin/sh'; do
    packages=(keep-previous-selection)
    # Fixed source fixture arguments, intentionally split.
    # shellcheck disable=SC2086
    if public_root_packages packages $choice; then exit 1; fi
    [[ ${packages[*]} == keep-previous-selection ]]
done
for profile in normal el2-require; do
    excluded=$(public_root_exclusions "$profile")
    [[ $excluded == *uke-local-touch-data* && $excluded == *uke-video-firmware-local* ]]
done
if public_root_exclusions invalid; then exit 1; fi
echo 'Original desktop, firmware, shell and channel selections retained; invalid inputs leave the selection unchanged.'
