#!/usr/bin/bash
# Pure command-line and service policy; no device or shell execution.
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/image/early-super-policy.sh
# shellcheck disable=SC1091
source "$repo/src/image/early-super-policy.sh"
normal='root=PARTLABEL=userdata rw rootfstype=ext4,f2fs,xfs,btrfs panic=10'
rescue='root=/dev/mapper/uke-rescue ro rootfstype=ext4 senemos.role=rescue senemos.super=seed4-v1 noresume'
[[ $(uke_early_super_policy "$normal") == none ]]
[[ $(uke_early_super_policy "$normal senemos.super=seed4-v1") == userdata ]]
[[ $(uke_early_super_policy "$rescue") == rescue ]]
[[ $(uke_early_super_policy "$normal senemos.super=seed4-v1 resume=/dev/mapper/private-swap") == userdata ]]
reject() { if uke_early_super_policy "$1" >/dev/null 2>&1;then echo 'Unsafe early-super role accepted' >&2;exit 1;fi; }
for suffix in 'root=PARTLABEL=userdata' 'rootfstype=ext4' rw ro 'resume=/dev/mapper/uke-swap' resume_offset=1 noresume senemos.role=rescue senemos.super=seed4-v1;do
    reject "$rescue $suffix"
done
reject "${rescue/noresume/}"
reject "${rescue/ ro / rw }"
reject "${rescue/seed4-v1/seed5-v1}"
reject "${rescue/rootfstype=ext4/rootfstype=f2fs}"
reject "${rescue/ senemos.super=seed4-v1/}"
reject "$normal senemos.role=rescue"
reject "$normal senemos.super=seed5-v1"
reject "$normal senemos.super=seed4-v1 senemos.super=seed4-v1"
reject "$normal senemos.super=seed4-v1"$'\n'"$normal"
printf -v huge '%8193s' ''
reject "$huge"
grep -Fxq 'ConditionKernelCommandLine=senemos.super=seed4-v1' "$repo/src/image/dracut/96uke-super-boot/uke-super-prepare.service"
grep -Fxq 'if [[ $mode != rescue ]];then exec /usr/libexec/uke-root-guard;fi' "$repo/src/image/guard-early-rescue.sh"
echo 'Early-super pure policy: normal root delegated; exact opt-in/rescue accepted; duplicate, foreign, writable and resume rescue selectors refused. No device test.'
