#!/usr/bin/bash
# SPDX-License-Identifier: MIT
# Demand-only initramfs preparation, behind an explicit kernel-admitted profile.
set -Eeuo pipefail
export LC_ALL=C
umask 077
fail() { printf 'UKE_EARLY_SUPER_REJECTED: %s\n' "$*" >&2;exit 1; }
[[ $# == 0 && $(id -u) == 0 ]] || fail 'no arguments are accepted; root is required'
here=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=early-super-policy.sh
# shellcheck disable=SC1091
source "$here/early-super-policy.sh"
IFS= read -r line < /proc/cmdline
mode=$(uke_early_super_policy "$line")
if [[ $mode == none ]];then echo 'UKE_EARLY_SUPER_SKIPPED: existing root profile';exit 0;fi
udevadm settle --timeout=40 || fail 'device discovery did not settle'
# shellcheck source=select-uke-super.sh
# shellcheck disable=SC1091
source "$here/select-uke-super.sh"
# shellcheck source=fastboot-singleboot-layout.sh
# shellcheck disable=SC1091
source "$here/fastboot-singleboot-layout.sh"
uke_open_physical_super
runtime=/run/uke-super-early
[[ ! -L $runtime ]] || fail 'runtime directory is linked'
[[ -d $runtime ]] || mkdir -m700 "$runtime"
[[ $(stat -c '%u:%a' "$runtime") == 0:700 && ! -L $runtime/lock ]] || fail 'untrusted runtime directory'
exec 9>> "$runtime/lock"
flock -n 9 || fail 'another early preparation is active'
work=$(mktemp -d "$runtime/check.XXXXXXXX")
trap 'find "$work" -depth -delete' EXIT
# A public immutable geometry, never a key-release or metadata-authenticity proof.
fastboot_super_layout 4294967296 seed > "$work/seed.json"
bash "$here/provision-fastboot-super.sh" --fresh-install /proc/self/fd/3 "$work/seed.json" > "$work/provision.json"
jq -e '.all_metadata_views_ready and (.userdata_modified|not) and (.gpt_modified|not)' "$work/provision.json" >/dev/null
if [[ $mode == rescue ]];then
    bash "$here/map-fastboot-rescue.sh" /proc/self/fd/3 > "$work/rescue.json"
    jq -e '.readonly_linear_mapping and .three_slot_topology_verified and .ext4_label_and_full_capacity_verified' "$work/rescue.json" >/dev/null
    echo 'UKE_EARLY_RESCUE_READY: unique physical super; read-only EXT4 mapper; resume disabled'
else
    echo 'UKE_EARLY_SUPER_READY: 80 percent swap and 20 percent rescue; userdata unchanged; swap activation is separate'
fi
