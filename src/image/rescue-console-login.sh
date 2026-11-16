#!/usr/bin/bash
# SPDX-License-Identifier: MIT
# Rescue glue: a mountable installed EXT4 root supplies administrator identity.
# No password is handled by shell, no persistent credential or force shell.
set +x
set -Eeuo pipefail
export LC_ALL=C.UTF-8
umask 077
fail(){ printf 'UKE_RESCUE_LOGIN_REJECTED: %s\n' "$*" >&2;exit 1; }
[[ $(id -u) == 0 ]] || fail 'root service required'
[[ $# == 0 && $(readlink /proc/self/ns/mnt) != "$(readlink /proc/1/ns/mnt)" &&
   $(findmnt -rn -o PROPAGATION /) == private ]] || fail 'private mount namespace required'
# The systemd service creates a session before unshare. A blocking open with
# CLOCAL cleared waits for the USB host carrier rather than polling for it.
[[ -c /dev/ttyGS0 ]] || fail 'USB console device unavailable'
stty -F /dev/ttyGS0 sane 115200 -clocal
exec 8<> /dev/ttyGS0
exec <&8 >&8 2>&8
here=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=select-uke-userdata.sh
# shellcheck disable=SC1091
source "$here/select-uke-userdata.sh"
# shellcheck source=rescue-admin-policy.sh
# shellcheck disable=SC1091
source "$here/rescue-admin-policy.sh"
uke_open_physical_userdata
[[ $(blkid -p -s TYPE -o value /proc/self/fd/3) == ext4 ]] || fail 'a mountable installed EXT4 root is required; no automatic unlock or filesystem repair is performed'
work=$(mktemp -d /run/uke-rescue-auth.XXXXXXXX)
mkdir -m700 "$work/installed"
mounted=false
shadow_bound=false
cleanup(){
    local status=$?
    trap - EXIT
    if $shadow_bound;then umount --lazy /etc/shadow || status=1;fi
    if $mounted;then umount --lazy "$work/installed" || status=1;fi
    # Both mounts are private; namespace exit releases any remaining references.
    if ! mountpoint -q "$work/installed";then
        rm -f -- "$work/shadow"
        rmdir "$work/installed" "$work" || status=1
    fi
    exit "$status"
}
trap cleanup EXIT
mount -t ext4 -o ro,noload /proc/self/fd/3 "$work/installed"
mounted=true
[[ $(findmnt -rn -o MAJ:MIN --mountpoint "$work/installed") == "$uke_userdata_devno" ]] || fail 'mounted userdata identity differs'
account=$(awk -F: '$3==1000{n++;who=$1} END{if(n!=1)exit 1;print who}' "$work/installed/etc/passwd") || fail 'one primary installed account with UID1000 is required'
hash=$(uke_rescue_admin_hash "$work/installed" "$account") || fail 'an enabled installed administrator in wheel is required'
# This synthetic shadow exists only on volatile /run and only in this namespace.
# The original rescue root remains locked. No credential is copied to its disk.
printf 'root:%s:%s:0:99999:7:::\n' "$hash" "$(( $(date -u +%s)/86400 ))" > "$work/shadow"
unset hash
chmod 600 "$work/shadow"
chcon --reference=/etc/shadow "$work/shadow"
mount --bind "$work/shadow" /etc/shadow
shadow_bound=true
export UKE_RESCUE_INSTALLED_ROOT=$work/installed
export HISTFILE=/dev/null
printf 'Authenticate with the installed primary administrator password (%s).\n' "$account"
printf 'Installed userdata is read-only at %s. Repair and chroot require explicit commands.\n' "$UKE_RESCUE_INSTALLED_ROOT"
# Original Fedora crypt/TTY/password handling; never --force.
/usr/sbin/sulogin --login-shell /dev/ttyGS0
