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
capability_version=1
capability_flags='='
rpm() {
 [[ $# == 7 && $1 == --root && $3 == -q && $4 == --whatprovides && $5 == 'uke-control(setup-cdc-v1)' && $6 == --qf && $7 == '[%{PROVIDENAME}\t%{PROVIDEFLAGS:depflags}\t%{PROVIDEVERSION}\n]' ]] || return 1
 ((capability==1)) || return 1
 printf 'unrelated-capability\t=\t99\nuke-control(setup-cdc-v1)\t%s\t%s\n' "$capability_flags" "$capability_version"
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
for capability_version in 0 '' 2;do
 new_root "$work/version-${capability_version:-unversioned}"
 reject "$work/version-${capability_version:-unversioned}"
 grep -Fq 'exact setup-cdc-v1 = 1 interface' "$work/refused"
 [[ ! -e $work/version-${capability_version:-unversioned}/etc/uke-control/first-setup-cdc ]]
done
capability_version=1
capability_flags='>'
new_root "$work/inequality"
reject "$work/inequality"
[[ ! -e $work/inequality/etc/uke-control/first-setup-cdc ]]
capability_flags='='
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
grep -Fq 'required unit is missing or linked: uke-control-setup-console.service' "$work/refused"
[[ ! -e $work/missing/etc/uke-control/first-setup-cdc ]]
reject /
echo 'Offline setup image: named RPM capability and exact version required; original systemctl enables only marked setup access; repeat preserves marker; completed, old, wrong-version, linked, writable, foreign and incomplete roots refuse with diagnostics.'
