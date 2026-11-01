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
for desktop in kde gnome cutefish nextkde; do
    case $desktop in
        kde) packages plasma-workspace plasma-setup libplasma > "$work/$desktop";;
        gnome) packages gnome-shell gdm gnome-initial-setup libplasma plasma-workspace-common > "$work/$desktop";;
        cutefish) packages cutefish-desktop gdm gnome-shell gnome-session-wayland-session libplasma > "$work/$desktop";;
        nextkde) packages plasma-workspace plasma-setup nextkde quickshell > "$work/$desktop";;
    esac
    public_desktop_isolation "$work/$desktop" "$desktop"
done
packages plasma-workspace >> "$work/gnome"
if public_desktop_isolation "$work/gnome" gnome > /dev/null 2>&1; then exit 1; fi
packages gnome-shell >> "$work/kde"
if public_desktop_isolation "$work/kde" kde > /dev/null 2>&1; then exit 1; fi
echo 'GNOME cannot inherit Plasma, KDE cannot inherit GNOME, and every selected session is required; GDM dependencies are explicit.'
