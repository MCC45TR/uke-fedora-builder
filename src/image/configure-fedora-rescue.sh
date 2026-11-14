#!/usr/bin/env bash
# Configure an owned offline root; never mount or repair userdata.
set -Eeuo pipefail
[[ $# == 1 && $(id -u) == 0 && -d $1 && ! -L $1 ]]
root=$(realpath "$1")
[[ $root != / && -f $root/usr/lib/os-release && -x $root/usr/bin/systemctl && -f $root/etc/shadow ]]
[[ -z $(find "$root/proc" -mindepth 1 -maxdepth 1 -print -quit) ]]
mkdir -p "$root/etc/systemd/system" "$root/etc/systemd/system-generators" "$root/etc/systemd/journald.conf.d" "$root/etc/ssh/sshd_config.d"
cat > "$root/etc/fstab" <<'FSTAB'
LABEL=FEDORA_RESCUE / ext4 ro 0 0
tmpfs /var tmpfs nosuid,nodev,mode=0755,size=64M 0 0
tmpfs /tmp tmpfs nosuid,nodev,mode=1777,size=32M 0 0
FSTAB
cat > "$root/etc/systemd/journald.conf.d/40-uke-rescue.conf" <<'CONF'
[Journal]
Storage=volatile
RuntimeMaxUse=8M
RuntimeKeepFree=32M
RateLimitIntervalSec=30s
RateLimitBurst=100
CONF
# A rescue image never brings up a network listener with a generic credential.
cat > "$root/etc/ssh/sshd_config.d/40-uke-rescue.conf" <<'CONF'
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
AuthorizedKeysFile /run/uke-rescue/authorized_keys
HostKey /run/uke-rescue/ssh_host_ed25519_key
CONF
for unit in sshd.service sshd.socket sshd-keygen.target systemd-networkd.service systemd-networkd.socket systemd-firstboot.service systemd-pstore.service; do
    ln -sfn /dev/null "$root/etc/systemd/system/$unit"
done
for generator in systemd-gpt-auto-generator systemd-cryptsetup-generator systemd-hibernate-resume-generator; do
    ln -sfn /dev/null "$root/etc/systemd/system-generators/$generator"
done
ln -sfn /usr/lib/systemd/system/rescue.target "$root/etc/systemd/system/default.target"
# Original systemd/sulogin remains the console boundary. No unauthenticated
# force shell, persistent credential, automatic repair or plaintext unlock key.
chroot "$root" /usr/sbin/usermod --lock root
printf 'uke-rescue\n' > "$root/etc/hostname"
: > "$root/etc/machine-id"
[[ ! -L $root/var/lib/dbus/machine-id ]] || unlink "$root/var/lib/dbus/machine-id"
if [[ -f $root/var/lib/dbus/machine-id ]]; then : > "$root/var/lib/dbus/machine-id"; fi
find "$root/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*' -delete
[[ ! -e $root/root/.ssh/authorized_keys && ! -e $root/root/.bash_history ]]
awk -F: '$1=="root" && $2 ~ /^[!*]/ {found++} END {exit found!=1}' "$root/etc/shadow"
