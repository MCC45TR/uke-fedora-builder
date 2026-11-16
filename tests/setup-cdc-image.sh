#!/usr/bin/bash
# Offline image activation and refusal, using the distribution's systemctl.
set -Eeuo pipefail
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/public/desktop-setup.sh
# shellcheck disable=SC1091
source "$builder/src/public/desktop-setup.sh"
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
capability=1
rpm() {
 [[ $# == 5 && $1 == --root && $3 == -q && $4 == --whatprovides && $5 == 'uke-control(setup-cdc-v1) >= 1' ]]
 ((capability==1))
}
new_root() {
 local root=$1 unit
 mkdir -p "$root"/{etc/systemd/system,usr/bin,usr/lib/systemd/system,usr/lib/udev/rules.d,usr/lib/systemd/system-preset}
 printf '#!/bin/sh\nexit 99\n' > "$root/usr/bin/uke-control"
 chmod 755 "$root/usr/bin/uke-control"
 for unit in uke-control-setup-cdc.service uke-control-setup-console.service uke-control-setup-cdc-finish.service;do
  printf '[Unit]\nDescription=Offline fixture\n[Service]\nType=oneshot\nExecStart=/usr/bin/uke-control\n[Install]\nWantedBy=multi-user.target\n' > "$root/usr/lib/systemd/system/$unit"
 done
 printf '[Unit]\nDescription=Offline fixture\n[Path]\nPathExists=/etc/plasma-setup-done\n[Install]\nWantedBy=multi-user.target\n' > "$root/usr/lib/systemd/system/uke-control-setup-cdc-finish.path"
 printf '[Unit]\nDescription=Offline target\n' > "$root/usr/lib/systemd/system/multi-user.target"
 touch "$root/usr/lib/udev/rules.d/91-uke-control-setup-cdc.rules" "$root/usr/lib/systemd/system-preset/81-uke-control-setup-cdc.preset"
}
reject() { if public_plasma_setup_cdc "$1" > "$work/refused" 2>&1;then echo 'Unsafe setup image accepted' >&2;exit 1;fi; }
new_root "$work/fresh"
public_plasma_setup_cdc "$work/fresh"
marker=$work/fresh/etc/uke-control/first-setup-cdc
printf 'v1\n' | cmp - "$marker"
inode=$(stat -c %i "$marker")
public_plasma_setup_cdc "$work/fresh"
[[ $(stat -c %i "$marker") == "$inode" && $(stat -c %a "$marker") == 600 ]]
[[ ! -e $work/fresh/var/lib/uke-control/cdc-on ]]
touch "$work/fresh/etc/plasma-setup-done"
reject "$work/fresh"
[[ $(stat -c %i "$marker") == "$inode" ]]
new_root "$work/old"
capability=0
reject "$work/old"
[[ ! -e $work/old/etc/uke-control/first-setup-cdc ]]
capability=1
new_root "$work/linked"
ln -s "$work/fresh/etc/uke-control" "$work/linked/etc/uke-control"
reject "$work/linked"
new_root "$work/unsafe"
mkdir "$work/unsafe/etc/uke-control"
chmod 777 "$work/unsafe/etc/uke-control"
reject "$work/unsafe"
[[ ! -e $work/unsafe/etc/uke-control/first-setup-cdc ]]
new_root "$work/foreign"
mkdir "$work/foreign/etc/uke-control"
printf 'foreign\n' > "$work/foreign/etc/uke-control/first-setup-cdc"
chmod 600 "$work/foreign/etc/uke-control/first-setup-cdc"
reject "$work/foreign"
[[ $(< "$work/foreign/etc/uke-control/first-setup-cdc") == foreign ]]
new_root "$work/missing"
unlink "$work/missing/usr/lib/systemd/system/uke-control-setup-console.service"
reject "$work/missing"
[[ ! -e $work/missing/etc/uke-control/first-setup-cdc ]]
reject /
echo 'Offline setup image: original systemctl enables only marked setup access; repeat preserves marker; completed, old, linked, writable, foreign and incomplete roots refuse.'
