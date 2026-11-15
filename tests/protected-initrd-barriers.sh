#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Original systemd transaction verification; no manager, key or resume runs.
set -Eeuo pipefail
trap 'printf "UKE_INITRD_BARRIERS_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
[[ $# == 1 && ! -e $1 && ! -L $1 ]]
report=$(realpath -m "$1")
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
module=$repo/src/image/dracut/96uke-protected-boot
systemdsystemunitdir=/usr/lib/systemd/system
[[ -f $systemdsystemunitdir/systemd-hibernate-resume.service &&
   -x /usr/lib/systemd/systemd-hibernate-resume ]]
native_version=$(systemd-analyze --version | head -n1)
initdir=$work/root
# Consumed by the sourced dracut install interface.
# shellcheck disable=SC2034
moddir=$module
mkdir -p "$initdir$systemdsystemunitdir" "$initdir/usr/lib/systemd" "$initdir/usr/bin" "$initdir/etc"
printf 'ID=fedora\n' > "$initdir/etc/initrd-release"
cp /usr/bin/true "$initdir/usr/bin/true"
cp /usr/lib/systemd/systemd-hibernate-resume "$initdir/usr/lib/systemd/"
cp "$systemdsystemunitdir/systemd-hibernate-resume.service" "$initdir$systemdsystemunitdir/"
for target in emergency local-fs-pre umount shutdown; do
    printf '[Unit]\nDescription=Fixture target\nDefaultDependencies=no\n' > "$initdir$systemdsystemunitdir/$target.target"
done
cat > "$initdir$systemdsystemunitdir/sysroot.mount" <<'UNIT'
[Unit]
DefaultDependencies=no
[Mount]
What=/dev/fixture-root
Where=/sysroot
Type=ext4
Options=ro
UNIT
cat > "$initdir$systemdsystemunitdir/systemd-udev-trigger.service" <<'UNIT'
[Unit]
DefaultDependencies=no
[Service]
Type=oneshot
ExecStart=/usr/bin/true
UNIT
# These mock only dracut's host copy interface. The true binary is a clearly
# inert missing-policy stand-in; no role, mapping or snapshot is authenticated.
have_policy=0
require_binaries() { [[ $have_policy == 1 && $* == /usr/libexec/uke-protected-boot-policy ]]; }
inst_multiple() {
    mkdir -p "$initdir/usr/libexec"
    cp /usr/bin/true "$initdir/usr/libexec/uke-protected-boot-policy"
}
inst_simple() {
    mkdir -p "$initdir$(dirname "$2")"
    cp "$1" "$initdir$2"
}
# The fixture intentionally supplies the dracut copy functions above.
# shellcheck disable=SC1091
source "$module/module-setup.sh"
status=0
check || status=$?
[[ $status == 255 && $(depends) == 'systemd resume uke-super-tools' ]]
if install > "$work/missing-policy.log" 2>&1; then
    echo 'Missing native policy was accepted' >&2; exit 1
fi
[[ ! -e $initdir/etc/systemd && ! -e $initdir/usr/libexec ]]
have_policy=1
install
cmp "$module/uke-hwkm.conf" "$initdir/usr/lib/modprobe.d/uke-hwkm.conf"
# Parse the exact installed config with original kmod. This only emits config;
# it does not load a module, change a parameter or prove first-probe ordering.
modprobe --showconfig --config "$initdir/usr/lib/modprobe.d/uke-hwkm.conf" > "$work/kmod.conf"
[[ $(grep -c '^options qcom_ice ' "$work/kmod.conf") == 1 ]]
grep -Fx 'options qcom_ice use_wrapped_keys=1' "$work/kmod.conf" >/dev/null
for generator in systemd-hibernate-resume-generator systemd-cryptsetup-generator systemd-gpt-auto-generator; do
    [[ $(readlink "$initdir/etc/systemd/system-generators/$generator") == /dev/null ]]
done
for unit in swap.target systemd-cryptsetup@.service systemd-hibernate-resume@.service; do
    [[ $(readlink "$initdir/etc/systemd/system/$unit") == /dev/null ]]
done
verify() {
    SYSTEMD_LOG_LEVEL=warning SYSTEMD_LOG_COLOR=0 systemd-analyze --root="$initdir" --man=no verify \
        sysroot.mount uke-protected-role.service uke-protected-resume.service systemd-hibernate-resume.service
}
if ! verify > "$work/verify.log" 2>&1; then cat "$work/verify.log" >&2; exit 1; fi
[[ ! -e $initdir/run/uke-protected && ! -e $initdir/dev/mapper/uke-resume ]]
# Inspect the effective unit with original systemd: the automatic no-argument
# invocation must be cleared, retaining the original helper's explicit ABI.
SYSTEMD_LOG_COLOR=0 systemd-analyze --root="$initdir" cat-config \
    /etc/systemd/system/systemd-hibernate-resume.service.d/50-uke-protected.conf > "$work/resume.conf"
grep -Fx 'ExecStart=' "$work/resume.conf" >/dev/null
grep -Fx 'ExecStart=/usr/lib/systemd/systemd-hibernate-resume /dev/mapper/uke-resume 0' "$work/resume.conf" >/dev/null
grep -Fx 'ConditionPathExists=/run/uke-protected/normal' "$work/resume.conf" >/dev/null
grep -Fx 'ConditionPathExists=/run/uke-protected/resume-authorized' "$work/resume.conf" >/dev/null
grep -Fx 'ConditionKernelCommandLine=' "$work/resume.conf" >/dev/null
grep -Fx 'AssertKernelCommandLine=noresume' "$initdir$systemdsystemunitdir/uke-protected-role.service" >/dev/null
# Original systemd evaluates both path conditions as an AND. These owned
# fixture markers exercise that mechanism, not the absent authentication policy.
conditions() {
    systemd-analyze condition "ConditionPathExists=$initdir/run/uke-protected/normal" \
        "ConditionPathExists=$initdir/run/uke-protected/resume-authorized"
}
if conditions > "$work/unknown.log" 2>&1; then exit 1; fi
mkdir -p "$initdir/run/uke-protected"
: > "$initdir/run/uke-protected/rescue"
if conditions > "$work/rescue.log" 2>&1; then exit 1; fi
: > "$initdir/run/uke-protected/normal"
if conditions > "$work/cold-normal.log" 2>&1; then exit 1; fi
: > "$initdir/run/uke-protected/resume-authorized"
conditions > "$work/authorized-normal.log" 2>&1
SYSTEMD_PROC_CMDLINE=noresume systemd-analyze condition 'AssertKernelCommandLine=noresume' > "$work/noresume.log" 2>&1
if SYSTEMD_PROC_CMDLINE=fixture systemd-analyze condition 'AssertKernelCommandLine=noresume' > "$work/no-noresume.log" 2>&1; then exit 1; fi
# Native verification must notice a cycle and a missing mandatory policy.
mkdir "$initdir/etc/systemd/system/uke-protected-role.service.d"
printf '[Unit]\nAfter=sysroot.mount\n' > "$initdir/etc/systemd/system/uke-protected-role.service.d/cycle.conf"
if verify > "$work/cycle.log" 2>&1; then echo 'Ordering cycle was accepted' >&2; exit 1; fi
grep -i 'cycle' "$work/cycle.log" >/dev/null
unlink "$initdir/etc/systemd/system/uke-protected-role.service.d/cycle.conf"
mv "$initdir/usr/libexec/uke-protected-boot-policy" "$work/withheld-policy"
if verify > "$work/absent.log" 2>&1; then echo 'Absent policy executable was accepted' >&2; exit 1; fi
grep -F 'uke-protected-boot-policy' "$work/absent.log" >/dev/null
mv "$work/withheld-policy" "$initdir/usr/libexec/uke-protected-boot-policy"
verify > "$work/restored.log" 2>&1
jq -n --arg version "$native_version" \
    '{schema_version:1,original_systemd:$version,explicit_module_only:true,
      missing_native_policy_refused:true,automatic_generators_masked:true,
      hwkm_opt_in_config_copied_and_original_kmod_parsed:true,
      hwkm_first_probe_order_or_hardware_not_proved:true,
      initrd_swap_and_software_cryptsetup_masked:true,original_helper_explicit_device:true,
      kernel_noresume_required_by_role:true,kernel_profile_itself_qualified:false,
      native_condition_semantics_verified:true,fixture_role_markers_not_authentication:true,
      native_unit_transaction_verified:true,ordering_cycle_refused:true,
      missing_policy_executable_refused:true,fixture_helper_is_inert_true_binary:true,
      manager_started:false,device_or_key_access:false,resume_executed:false,
      role_or_snapshot_authenticated:false,boot_or_hardware_qualified:false}' > "$report"
