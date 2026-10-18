#!/usr/bin/env bash
# Host composer only; configure an offline root with original Fedora first-run tools.
set -Eeuo pipefail
[[ $# == 1 && -d $1 && ! -L $1 ]] || exit 2
root=$(realpath -- "$1")
[[ $root != / && $root != /usr && $root != /etc && -f $root/usr/share/uke/alpha-release.json ]] || exit 2
[[ $(stat -c %u "$root/etc/passwd") == 0 ]] || exit 2
rpm --root "$root" -q plasma-setup sddm shadow-utils sudo >/dev/null
for program in useradd usermod chpasswd userdel visudo; do
    [[ -x $root/usr/sbin/$program ]] || exit 1
done
[[ -x $root/usr/bin/kwriteconfig6 && ! -L $root/etc/xdg && ! -L $root/etc/xdg/plasmasetuprc ]] || exit 1
for path in usr/libexec/plasma-setup usr/libexec/plasma-setup-bootutil usr/lib/sysusers.d/plasma-setup-sysuser.conf usr/lib/systemd/system/plasma-setup.service; do
    [[ -f $root/$path && ! -L $root/$path ]] || exit 1
done
minimum=$(awk '$1=="UID_MIN" {print $2}' "$root/etc/login.defs")
[[ $minimum =~ ^[0-9]+$ && $minimum -ge 1000 ]]
while IFS=: read -r name _ uid _; do
    [[ $uid =~ ^[0-9]+$ ]] || exit 1
    if (( uid >= minimum && uid != 65534 )); then
        [[ $name == uke && $uid == 1000 ]] || { echo 'An unexpected ordinary account is present; refusing to erase it' >&2; exit 1; }
    fi
done < "$root/etc/passwd"
if grep -q '^uke:' "$root/etc/passwd"; then
    chroot "$root" /usr/sbin/userdel uke
fi
rm -rf "$root/home/uke"
rm -f "$root/var/spool/mail/uke" "$root/etc/sddm.conf.d/80-uke-alpha.conf" \
    "$root/etc/sudoers.d/90-uke-alpha" "$root/etc/plasma-setup-done" \
    "$root/etc/sddm.conf.d/99-plasma-setup.conf"
for tty in tty1 tty2; do
    rm -f "$root/etc/systemd/system/getty@$tty.service.d/80-uke-alpha.conf"
done
chroot "$root" /usr/sbin/usermod -L root
grep -Eq '^root:!' "$root/etc/shadow"
grep -Eq '^wheel:[^:]*:[0-9]+:' "$root/etc/group"
grep -Eq '^%wheel[[:space:]]+ALL=\(ALL\)[[:space:]]+ALL' "$root/etc/sudoers"
chroot "$root" /usr/sbin/visudo -cf /etc/sudoers
mkdir -p "$root/etc/xdg"
chroot "$root" /usr/bin/kwriteconfig6 --file /etc/xdg/plasmasetuprc --group Accounts --key UserGroups wheel
chroot "$root" /usr/bin/systemd-sysusers /usr/lib/sysusers.d/plasma-setup-sysuser.conf
chroot "$root" /usr/bin/systemctl --root / enable plasma-setup.service
[[ ! -e $root/etc/plasma-setup-done && ! -e $root/home/uke ]]
setup_uid=$(awk -F: '$1=="plasma-setup" {print $3}' "$root/etc/passwd")
[[ $setup_uid =~ ^[0-9]+$ && $setup_uid -lt $minimum ]]
[[ -L $root/etc/systemd/system/multi-user.target.wants/plasma-setup.service ]]
echo 'Original Plasma Setup enabled; no ordinary user, autologin or passwordless sudo is preconfigured.'
