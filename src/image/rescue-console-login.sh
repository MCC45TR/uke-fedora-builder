#!/usr/bin/bash
# SPDX-License-Identifier: MIT
# Prepare a volatile credential for a separate original Fedora sulogin process.
# No password is handled by shell, no persistent credential or force shell.
set +x
set -Eeuo pipefail
export LC_ALL=C.UTF-8
umask 077
fail(){ printf 'UKE_RESCUE_LOGIN_REJECTED: %s\n' "$*" >&2;exit 1; }
[[ $(id -u) == 0 ]] || fail 'root service required'
runtime=/run/uke-rescue-auth
[[ $(findmnt -rn -o FSTYPE --target /run) == tmpfs && -d $runtime && ! -L $runtime &&
   $(stat -c '%u:%a' "$runtime") == 0:700 ]] || fail 'private volatile runtime directory required'
if [[ $# == 1 && $1 == --cleanup ]];then
    # Fixed owned RAM directory only. Do not follow copied configuration links.
    [[ ! -L $runtime/etc ]] || fail 'runtime configuration directory is linked'
    if [[ -d $runtime/etc ]];then find "$runtime/etc" -xdev -depth -delete;fi
    rm -f -- "$runtime/lock"
    exit 0
fi
[[ $# == 0 && $(readlink /proc/self/ns/mnt) != "$(readlink /proc/1/ns/mnt)" &&
   $(findmnt -rn -o PROPAGATION /) == private ]] || fail 'private mount namespace required'
[[ $(findmnt -rn -o FSTYPE --target /run) == tmpfs && -f /etc/shadow && ! -L /etc/shadow ]] || fail 'volatile runtime and a regular rescue shadow file are required'
[[ ! -e $runtime/etc && ! -L $runtime/etc ]] || fail 'fresh systemd runtime directory required'
[[ ! -L $runtime/lock ]] || fail 'runtime lock is linked'
exec 9>> "$runtime/lock"
flock -n 9 || fail 'another rescue credential preparation is active'
[[ -c /dev/ttyGS0 ]] || fail 'USB console device unavailable'
# CDC ACM is not a UART baud generator. g_serial may retain its default line
# coding until the host opens it; forcing 115200 makes GNU stty reject that
# otherwise usable TTY. Keep carrier handling and sane terminal flags explicit.
stty -F /dev/ttyGS0 sane -clocal
here=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=select-uke-userdata.sh
# shellcheck disable=SC1091
source "$here/select-uke-userdata.sh"
# shellcheck source=rescue-admin-policy.sh
# shellcheck disable=SC1091
source "$here/rescue-admin-policy.sh"
uke_userdata_devno=''
uke_open_physical_userdata
[[ $uke_userdata_devno =~ ^[0-9]+:[0-9]+$ ]] || fail 'physical userdata selection did not provide a device identity'
[[ $(blkid -p -s TYPE -o value /proc/self/fd/3) == ext4 ]] || fail 'a mountable installed EXT4 root is required; no automatic unlock or filesystem repair is performed'
work=$(mktemp -d "$runtime/check.XXXXXXXX")
mkdir -m700 "$work/installed"
mounted=false
credential=''
cleanup(){
    local status=$?
    trap - EXIT
    if $mounted;then umount "$work/installed" || status=1;fi
    [[ -z $credential ]] || rm -f -- "$credential"
    if ! mountpoint -q "$work/installed";then
        rmdir "$work/installed" "$work" || status=1
    fi
    exit "$status"
}
trap cleanup EXIT
mount -t ext4 -o ro,noload /proc/self/fd/3 "$work/installed"
mounted=true
[[ $(findmnt -rn -o MAJ:MIN --mountpoint "$work/installed") == "$uke_userdata_devno" ]] || fail 'mounted userdata identity differs'
case ,$(findmnt -rn -o OPTIONS --mountpoint "$work/installed"), in
    *,ro,*) :;;
    *) fail 'installed userdata is not read-only';;
esac
account=$(awk -F: '$3==1000{n++;who=$1} END{if(n!=1)exit 1;print who}' "$work/installed/etc/passwd") || fail 'one primary installed account with UID1000 is required'
hash=$(uke_rescue_admin_hash "$work/installed" "$account") || fail 'an enabled installed administrator in wheel is required'
# Copy the immutable rescue configuration into bounded RAM, retaining original
# labels and relative links. PID1 can bind the directory using Fedora's existing
# etc_t rules; mounting directly onto shadow_t would require an extra MAC rule.
etc_bytes=$(du -sb /etc | awk '{print $1}')
[[ $etc_bytes =~ ^[0-9]+$ ]] || fail 'cannot measure rescue configuration'
((etc_bytes<=67108864)) || fail 'rescue configuration exceeds the 64-MiB runtime bound'
(( $(df -B1 --output=avail /run | tail -n1) >= etc_bytes*2+33554432 )) || fail 'insufficient volatile runtime reserve'
cp -a /etc "$runtime/etc"
# PID1 binds this RAM directory read-only only for the separate sulogin command.
# The rescue disk remains locked. ExecStopPost cleans labeled files even when
# the login process is killed; RuntimeDirectory then removes the empty parent.
credential=$(mktemp "$runtime/shadow.XXXXXXXX")
printf 'root:%s:%s:0:99999:7:::\n' "$hash" "$(( $(date -u +%s)/86400 ))" > "$credential"
unset hash
chmod 600 "$credential"
chcon --reference=/etc/shadow "$credential"
# Link creation refuses an existing name; do not replace another credential.
rm -- "$runtime/etc/shadow"
ln -- "$credential" "$runtime/etc/shadow"
rm -- "$credential"
credential=''
printf 'Authenticate with the installed primary administrator password (%s).\n' "$account"
printf 'Installed userdata is released after this identity check. Mount and chroot repair require explicit commands.\n'
