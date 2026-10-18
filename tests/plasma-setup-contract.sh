#!/usr/bin/env bash
# Host fixtures mock privileged tools; no host account, service or package is changed.
set -Eeuo pipefail
builder=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin"
cat > "$fixture/bin/rpm" <<'SH'
#!/bin/sh
exit 0
SH
cat > "$fixture/bin/stat" <<'SH'
#!/bin/sh
printf '0\n'
SH
cat > "$fixture/bin/chroot" <<'SH'
#!/bin/bash
set -euo pipefail
root=$1 program=$2; shift 2
case "$program" in
 /usr/sbin/userdel) [[ $1 == uke ]]; sed -i '/^uke:/d' "$root/etc/passwd";;
 /usr/sbin/usermod) [[ $* == '-L root' ]];;
 /usr/sbin/visudo) [[ $* == '-cf /etc/sudoers' ]];;
 /usr/bin/kwriteconfig6)
   [[ $* == '--file /etc/xdg/plasmasetuprc --group Accounts --key UserGroups wheel' ]]
   printf '[Accounts]\nUserGroups=wheel\n' > "$root/etc/xdg/plasmasetuprc";;
 /usr/bin/systemd-sysusers)
   [[ $1 == /usr/lib/sysusers.d/plasma-setup-sysuser.conf ]]
   grep -q '^plasma-setup:' "$root/etc/passwd" || printf 'plasma-setup:x:999:999::/run/plasma-setup:/bin/sh\n' >> "$root/etc/passwd";;
 /usr/bin/systemctl)
   [[ $* == '--root / enable plasma-setup.service' ]]
   mkdir -p "$root/etc/systemd/system/multi-user.target.wants"
   ln -sfn /usr/lib/systemd/system/plasma-setup.service "$root/etc/systemd/system/multi-user.target.wants/plasma-setup.service";;
 *) exit 2;;
esac
SH
chmod +x "$fixture/bin/"*
export PATH=$fixture/bin:$PATH
new_root() {
    local dir=$1
    mkdir -p "$dir"/{etc/sddm.conf.d,etc/sudoers.d,etc/systemd/system/getty@tty2.service.d,home/uke,usr/bin,usr/sbin,usr/libexec,usr/lib/sysusers.d,usr/lib/systemd/system,usr/share/uke}
    printf '{}\n' > "$dir/usr/share/uke/alpha-release.json"
    printf 'root:x:0:0::/root:/bin/bash\nuke:x:1000:1000::/home/uke:/bin/bash\nnobody:x:65534:65534::/:/sbin/nologin\n' > "$dir/etc/passwd"
    printf 'root:!:1:0:99999:7:::\n' > "$dir/etc/shadow"
    printf 'wheel:x:10:\n' > "$dir/etc/group"
    printf 'UID_MIN 1000\n' > "$dir/etc/login.defs"
    printf '%%wheel ALL=(ALL) ALL\n' > "$dir/etc/sudoers"
    for program in useradd usermod chpasswd userdel visudo; do touch "$dir/usr/sbin/$program"; chmod +x "$dir/usr/sbin/$program"; done
    touch "$dir/usr/bin/kwriteconfig6"; chmod +x "$dir/usr/bin/kwriteconfig6"
    touch "$dir/usr/libexec/"{plasma-setup,plasma-setup-bootutil} "$dir/usr/lib/sysusers.d/plasma-setup-sysuser.conf" "$dir/usr/lib/systemd/system/plasma-setup.service"
    touch "$dir/etc/sddm.conf.d/80-uke-alpha.conf" "$dir/etc/sudoers.d/90-uke-alpha" "$dir/etc/plasma-setup-done" "$dir/etc/systemd/system/getty@tty2.service.d/80-uke-alpha.conf"
}
new_root "$fixture/root"
bash "$builder/src/image/prepare-plasma-setup.sh" "$fixture/root"
[[ ! -d $fixture/root/home/uke && ! -e $fixture/root/etc/plasma-setup-done && ! -e $fixture/root/etc/sudoers.d/90-uke-alpha ]]
if grep -q '^uke:' "$fixture/root/etc/passwd"; then exit 1; fi
[[ -L $fixture/root/etc/systemd/system/multi-user.target.wants/plasma-setup.service ]]
grep -Fx 'UserGroups=wheel' "$fixture/root/etc/xdg/plasmasetuprc"
bash "$builder/src/image/prepare-plasma-setup.sh" "$fixture/root"
new_root "$fixture/unexpected"
printf 'another:x:1001:1001::/home/another:/bin/bash\n' >> "$fixture/unexpected/etc/passwd"
if bash "$builder/src/image/prepare-plasma-setup.sh" "$fixture/unexpected" >/dev/null 2>&1; then exit 1; fi
[[ -d $fixture/unexpected/home/uke && -f $fixture/unexpected/etc/plasma-setup-done ]]
ln -s "$fixture/root" "$fixture/link"
if bash "$builder/src/image/prepare-plasma-setup.sh" "$fixture/link" >/dev/null 2>&1; then exit 1; fi
new_root "$fixture/config-link"
mkdir "$fixture/config-link/etc/xdg"
ln -s /etc/xdg/plasmasetuprc "$fixture/config-link/etc/xdg/plasmasetuprc"
if bash "$builder/src/image/prepare-plasma-setup.sh" "$fixture/config-link" >/dev/null 2>&1; then exit 1; fi
[[ -d $fixture/config-link/home/uke ]]
echo 'First-run account cleanup, idempotence, unexpected-user and symlink refusal fixtures passed.'
