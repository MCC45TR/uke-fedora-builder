#!/usr/bin/bash
# Original systemd offline verification, with inert fixture executables.
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
initdir=$work/root
systemdsystemunitdir=/usr/lib/systemd/system
moddir=$repo/src/image/dracut/96uke-super-boot
mkdir -p "$initdir$systemdsystemunitdir" "$initdir/usr/bin" "$initdir/usr/libexec" "$work/module"
cp /usr/bin/true "$initdir/usr/bin/true"
cp /usr/bin/true "$initdir/usr/libexec/uke-root-guard"
cp "$repo/src/image/"{early-super-policy,prepare-early-super,guard-early-rescue}.sh "$work/module/"
cp "$moddir/uke-super-prepare.service" "$work/module/"
inst_multiple() { [[ $* == udevadm ]]; }
inst_simple() { mkdir -p "$initdir$(dirname "$2")";cp "$1" "$initdir$2"; }
# shellcheck disable=SC1091
source "$moddir/module-setup.sh"
status=0
check || status=$?
[[ $status == 255 && $(depends) == 'systemd uke-super-tools' ]]
cp /usr/bin/true "$initdir/usr/libexec/uke-protected-boot-policy"
if install;then echo 'Plaintext profile replaced protected policy' >&2;exit 1;fi
[[ ! -e $initdir$systemdsystemunitdir/uke-super-prepare.service ]]
unlink "$initdir/usr/libexec/uke-protected-boot-policy"
moddir=$work/module
install
cmp /usr/bin/true "$initdir/usr/libexec/uke-root-guard"
for target in emergency shutdown umount local-fs-pre;do
 printf '[Unit]\nDefaultDependencies=no\n' > "$initdir$systemdsystemunitdir/$target.target"
done
for unit in systemd-udev-trigger uke-root-guard;do
 printf '[Unit]\nDefaultDependencies=no\n[Service]\nType=oneshot\nExecStart=/usr/bin/true\n' > "$initdir$systemdsystemunitdir/$unit.service"
done
cat > "$initdir$systemdsystemunitdir/sysroot.mount" <<'UNIT'
[Unit]
DefaultDependencies=no
Requires=uke-root-guard.service
After=uke-root-guard.service
[Mount]
What=/dev/fixture-root
Where=/sysroot
Type=ext4
Options=ro
UNIT
verify() {
 SYSTEMD_LOG_LEVEL=warning SYSTEMD_LOG_COLOR=0 systemd-analyze --root="$initdir" --man=no verify sysroot.mount uke-root-guard.service uke-super-prepare.service
}
if ! verify > "$work/verify.log" 2>&1;then cat "$work/verify.log" >&2;exit 1;fi
SYSTEMD_PROC_CMDLINE='root=PARTLABEL=userdata rw' systemd-analyze condition 'ConditionKernelCommandLine=!senemos.super=seed4-v1' > "$work/default.log" 2>&1
SYSTEMD_PROC_CMDLINE='senemos.super=seed4-v1' systemd-analyze condition 'ConditionKernelCommandLine=senemos.super=seed4-v1' > "$work/optin.log" 2>&1
mkdir -p "$initdir$systemdsystemunitdir/uke-super-prepare.service.d"
printf '[Unit]\nAfter=sysroot.mount\n' > "$initdir$systemdsystemunitdir/uke-super-prepare.service.d/cycle.conf"
if verify > "$work/cycle.log" 2>&1;then echo 'Root preparation ordering cycle accepted' >&2;exit 1;fi
grep -iq cycle "$work/cycle.log"
echo 'Original systemd: early-super install, original guard preservation, explicit condition and ordering passed; protected policy and cycles refused. No manager or device operation.'
