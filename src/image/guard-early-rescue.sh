#!/usr/bin/bash
# SPDX-License-Identifier: MIT
# Retain the original physical-root guard for every non-rescue root.
set -Eeuo pipefail
export LC_ALL=C
[[ $# == 0 && $(id -u) == 0 ]]
here=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=early-super-policy.sh
# shellcheck disable=SC1091
source "$here/early-super-policy.sh"
IFS= read -r line < /proc/cmdline
mode=$(uke_early_super_policy "$line")
if [[ $mode != rescue ]];then exec /usr/libexec/uke-root-guard;fi
# shellcheck source=select-uke-super.sh
# shellcheck disable=SC1091
source "$here/select-uke-super.sh"
uke_open_physical_super
# Revalidate existing ownership, table, read-only mode, full filesystem and all
# three metadata views. Verification never creates or adopts an unknown mapper.
bash "$here/map-fastboot-rescue.sh" --verify /proc/self/fd/3 >/dev/null
echo 'UKE_ROOT_ADMITTED: read-only rescue mapping of unique physical Uke super; no resume'
