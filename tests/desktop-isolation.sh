#!/usr/bin/env bash
# Cross-desktop package contamination is rejected; shared Qt/KDE libraries pass.
set -Eeuo pipefail
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/public/desktop-isolation.sh
# shellcheck disable=SC1091
source "$builder/src/public/desktop-isolation.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
packages() { printf '%s-0:1-1.fc46.aarch64\n' "$@" | sort; }
for desktop in kde plasma-mobile gnome cutefish nextkde; do
    case $desktop in
        kde) packages plasma-workspace plasma-setup libplasma > "$work/$desktop";;
        plasma-mobile) packages plasma-workspace plasma-setup plasma-mobile plasma-settings plasma-keyboard plasma-lookandfeel-fedora-mobile > "$work/$desktop";;
        gnome) packages gnome-shell gdm gnome-initial-setup libplasma plasma-workspace-common > "$work/$desktop";;
        cutefish) mapfile -t selected < <(jq -r '.required_packages[]' "$builder/configs/images/cutefish-rawhide.json"); packages "${selected[@]}" gnome-keyring qt6-qtbase > "$work/$desktop";;
        nextkde) packages plasma-workspace plasma-setup nextkde quickshell > "$work/$desktop";;
    esac
    public_desktop_isolation "$work/$desktop" "$desktop"
done
packages plasma-workspace >> "$work/gnome"
if public_desktop_isolation "$work/gnome" gnome > /dev/null 2>&1; then exit 1; fi
packages gnome-shell >> "$work/kde"
if public_desktop_isolation "$work/kde" kde > /dev/null 2>&1; then exit 1; fi
for leak in gdm gnome-shell gnome-session-wayland-session plasma-workspace plasma-workspace-common kf6-kconfig kio-core libplasma sddm xdg-desktop-portal-gnome; do
    cp "$work/cutefish" "$work/leak"
    packages "$leak" >> "$work/leak"
    if public_desktop_isolation "$work/leak" cutefish >/dev/null 2>&1; then exit 1; fi
done
echo 'GNOME cannot inherit Plasma, KDE cannot inherit GNOME, and every selected session is required; Cutefish rejects every foreign desktop dependency.'
