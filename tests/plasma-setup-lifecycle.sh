#!/usr/bin/env bash
# Run in the disposable AArch64 composer; only a temporary copy is changed.
set -Eeuo pipefail
[[ $# == 1 && -d $1 && ! -L $1 && $EUID == 0 ]] || exit 2
root=$(realpath -- "$1")
[[ $root != / && -f $root/usr/share/uke/alpha-release.json ]]
unit=$root/usr/lib/systemd/system/plasma-setup.service
grep -Fxq 'ConditionPathExists=!/etc/plasma-setup-done' "$unit"
grep -Fxq 'ExecStart=/usr/libexec/plasma-setup-bootutil' "$unit"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cp -a --reflink=auto "$root/." "$fixture/"
rm -f "$fixture/etc/plasma-setup-done" "$fixture/etc/sddm.conf.d/99-plasma-setup.conf"
start_if_unfinished() {
    # The original unit, rather than bootutil itself, checks this condition.
    [[ -e $fixture/etc/plasma-setup-done ]] || chroot "$fixture" /usr/libexec/plasma-setup-bootutil
}
start_if_unfinished
grep -Fxq 'User=plasma-setup' "$fixture/etc/sddm.conf.d/99-plasma-setup.conf"
[[ ! -e $fixture/etc/plasma-setup-done ]]
rm "$fixture/etc/sddm.conf.d/99-plasma-setup.conf"
start_if_unfinished
[[ -s $fixture/etc/sddm.conf.d/99-plasma-setup.conf ]]
rm "$fixture/etc/sddm.conf.d/99-plasma-setup.conf"
touch "$fixture/etc/plasma-setup-done"
start_if_unfinished
[[ ! -e $fixture/etc/sddm.conf.d/99-plasma-setup.conf ]]
echo 'Original bootutil first start and retry passed; completed-setup unit condition checked offline. GUI and user creation remain untested.'
