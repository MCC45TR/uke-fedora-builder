#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Read-only classification of a seed/growing/ready liblp transaction.
# The input is a full-size raw image or a bounded metadata snapshot of a device.
set -Eeuo pipefail
export LC_ALL=C
umask 077
[[ $# == 2 && -f $1 && ! -L $1 && -f $2 && ! -L $2 ]] || exit 2
here=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=fastboot-singleboot-layout.sh
# shellcheck disable=SC1091
source "$here/fastboot-singleboot-layout.sh"
fail() { printf 'UKE_PROVISION_REJECTED: %s\n' "$*" >&2; exit 1; }
seed_file=$(realpath "$1")
input=$(realpath "$2")
seed_capacity=$(jq -er .super_bytes "$seed_file")
seed=$(fastboot_super_layout "$seed_capacity" seed)
[[ $(jq -Sc . "$seed_file") == "$(jq -Sc . <<< "$seed")" ]] || fail 'invalid seed contract'
capacity=$(stat -c %s "$input")
target=$(fastboot_super_layout "$capacity")
((capacity >= seed_capacity && capacity % 4096 == 0)) || fail 'device cannot hold the seed'
cmp -s -n 4096 /dev/zero "$input" || fail 'not a raw super layout'
work=$(mktemp -d "${TMPDIR:-/tmp}/uke-super-plan.XXXXXXXX")
trap 'find "$work" -depth -delete' EXIT
dd if="$input" of="$work/actual.raw" bs=1048576 count=1 iflag=fullblock status=none
cp "$work/actual.raw" "$work/seed.raw"
truncate -s "$capacity" "$work/actual.raw"
truncate -s "$seed_capacity" "$work/seed.raw"
printf '[]\n' > "$work/states.json"
ready=0 growing=0 initial=0 valid=0
for slot in 0 1 2; do
    result=0
    (ulimit -v 262144; ulimit -f 128; timeout --kill-after=1s 5s lpdump --json --slot="$slot" "$work/actual.raw") \
        > "$work/native.json" 2> "$work/diagnostic" || result=$?
    # Original lpdump may return success with {} when no metadata could be
    # decoded. That is an unreadable copy, never a valid empty Linux layout.
    if ((result == 0)) && jq -e 'type=="object" and length==0' "$work/native.json" >/dev/null; then result=70; fi
    if ((result == 0)); then
        group=$(jq -er '[.groups[] | select(.name != "default") | .name] | if length==1 then .[0] else error("ambiguous groups") end' "$work/native.json")
        case $group in
            uke_seed) phase=seed; view=$work/seed.raw; view_capacity=$seed_capacity;;
            uke_growing) phase=growing; view=$work/actual.raw; view_capacity=$capacity;;
            uke_linux) phase=ready; view=$work/actual.raw; view_capacity=$capacity;;
            *) fail "slot $slot contains a foreign valid layout";;
        esac
        TMPDIR="$work" bash "$here/inspect-fastboot-super.sh" --image "$view_capacity" "$view" "$phase" "$slot" > "$work/validated.json" || fail "slot $slot violates the declared phase"
        valid=$((valid + 1))
        case $phase in seed) initial=$((initial + 1));; growing) growing=$((growing + 1));; ready) ready=$((ready + 1));; esac
    else
        case $result in 1|65|70) phase=corrupt;; *) fail "metadata parser failed with status $result";; esac
    fi
    jq --arg phase "$phase" --argjson slot "$slot" '. + [{slot:$slot,phase:$phase}]' "$work/states.json" > "$work/next.json"
    mv "$work/next.json" "$work/states.json"
done
((valid > 0)) || fail 'no recoverable metadata view'
((ready == 0 || initial == 0)) || fail 'ready and seed phases conflict; do not overwrite a possible previous installation'
if ((ready == 3)); then action=verify-ready
elif ((ready > 0)); then action=finish-ready-metadata
else action=grow-fresh-seed
fi
jq -M -n --arg action "$action" --argjson seed "$seed" --argjson target "$target" \
    --argjson initialize "$([[ $action == grow-fresh-seed ]] && printf true || printf false)" \
    --slurpfile states "$work/states.json" \
    '{schema_version:1,action:$action,seed_layout:$seed,target_layout:$target,
      observed_metadata_slots:$states[0],may_initialize_swap:$initialize,
      rescue_payload_relocation_required:false,device_write_executed:false,
      metadata_authenticity_verified:false,operating_system_verified:false}'
