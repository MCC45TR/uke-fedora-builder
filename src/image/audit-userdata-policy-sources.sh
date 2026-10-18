#!/usr/bin/env bash
# Native host stage: bind generated contexts to signed Fedora and Uke inputs.
set -Eeuo pipefail
[[ $# == 0 && -f /job/device-packages.complete && ! -e /job/rootfs-frozen ]]
root=/job/root original=/job/original-fedora proof=/job/audit/selinux-recompiled
rpm_file=/job/inputs/device-rpms/uke-power-profile-backend-0.1.0-4.fc46.aarch64.rpm
mkdir -p /job/audit/policy-keydb /job/audit/policy-rpm "$proof"
rpmkeys --dbpath /job/audit/policy-keydb --import /job/inputs/uke-copr.asc
rpmkeys --dbpath /job/audit/policy-keydb --checksig "$rpm_file"
rpm2cpio "$rpm_file" > /job/audit/policy-rpm.cpio
(cd /job/audit/policy-rpm; cpio -idmu --quiet --no-absolute-filenames < ../policy-rpm.cpio)
cil=usr/share/selinux/packages/uke-power-profile.cil
cmp "$root/$cil" "/job/audit/policy-rpm/$cil"
printf '%s\n' '(filecon "/usr/libexec/uke-power-profiles-daemon" file (system_u object_r powerprofiles_exec_t ((s0) (s0))))' \
    > "$proof/expected-power-profile.cil"
cmp "$root/$cil" "$proof/expected-power-profile.cil"
contexts=etc/selinux/targeted/contexts/files
line=$(printf '/usr/libexec/uke-power-profiles-daemon\t--\tsystem_u:object_r:powerprofiles_exec_t:s0')
[[ $(grep -Fxc -- "$line" "$root/$contexts/file_contexts") == 1 ]]
grep -Fxv -- "$line" "$root/$contexts/file_contexts" > "$proof/fedora-file-contexts"
cmp "$proof/fedora-file-contexts" "$original/$contexts/file_contexts"
cmp "$root/$contexts/file_contexts.homedirs" "$original/$contexts/file_contexts.homedirs"
for name in file_contexts file_contexts.homedirs; do
    cmp "$root/$contexts/$name" "$root/var/lib/selinux/targeted/active/$name"
    cp "$root/$contexts/$name" "$proof/$name"
done
echo 'Generated context text equals original signed Fedora text plus the exact signed Uke power-profile file context.'
