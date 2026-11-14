#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Fresh-install early-boot layer. The protected caller selects the physical
# Uke super and supplies its trusted seed contract. No firmware/GPT/userdata I/O.
set -Eeuo pipefail
export LC_ALL=C
umask 077
fail() { printf 'UKE_PROVISION_REJECTED: %s\n' "$*" >&2; exit 1; }
[[ $# == 3 && $1 == --fresh-install && $(id -u) == 0 && -f $3 && ! -L $3 ]] || fail 'expected --fresh-install BLOCK_DEVICE SEED_LAYOUT_JSON as root'
here=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=fastboot-singleboot-layout.sh
# shellcheck disable=SC1091
source "$here/fastboot-singleboot-layout.sh"
device=$(readlink -e -- "$2")
[[ -b $device ]] || fail 'not a block device'
seed_file=$(realpath "$3")
exec 3< "$device"
capacity=$(blockdev --getsize64 /proc/self/fd/3)
[[ $(blockdev --getss /proc/self/fd/3) == 4096 ]] || fail 'the profile requires a 4096-byte logical block device'
devno=$(lsblk -dnro MAJ:MIN "$device")
[[ $devno =~ ^[0-9]+:[0-9]+$ ]] || fail 'ambiguous device identity'
tag=${devno/:/-}
runtime=/run/uke-super-provision
[[ ! -L $runtime ]] || fail 'runtime path is a symlink'
[[ -d $runtime ]] || mkdir -m700 "$runtime"
[[ $(stat -c '%u:%a' "$runtime") == 0:700 && ! -L $runtime/lock ]] || fail 'untrusted runtime directory'
exec 9>> "$runtime/lock"
flock -n 9 || fail 'another provisioner is active'
work=$(mktemp -d "$runtime/check.XXXXXXXX")
owned=()
cleanup() {
    local status=$? name uuid
    trap - EXIT
    for name in "${owned[@]}"; do
        if uuid=$(dmsetup info -c --noheadings -o uuid "$name" 2>/dev/null | tr -d '[:space:]'); then
            if [[ $uuid == "UKE-GROW-v1-$tag-${name##*-}" ]]; then
                dmsetup --noudevsync remove --retry "$name" || status=1
            else
                printf 'UKE_PROVISION_REJECTED: mapping ownership changed; unknown mapping retained\n' >&2
                status=1
            fi
        fi
    done
    if ((status != 0)); then
        for log in "$work/"*.log; do [[ ! -f $log ]] || tail -n 8 "$log" >&2; done
    fi
    find "$work" -depth -delete
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
snapshot() {
    dd if=/proc/self/fd/3 of="$work/snapshot.raw" bs=1048576 count=1 iflag=fullblock status=none
    truncate -s "$capacity" "$work/snapshot.raw"
}
snapshot
TMPDIR="$work" bash "$here/plan-super-provision.sh" "$seed_file" "$work/snapshot.raw" > "$work/plan.json"
action=$(jq -er .action "$work/plan.json")
target=$(jq -c .target_layout "$work/plan.json")
write_metadata() {
    local phase=$1 plan group usable swap rescue
    plan=$(fastboot_super_layout "$capacity" "$phase")
    group=$(jq -er .group.name <<< "$plan")
    usable=$(jq -er .usable_payload_bytes <<< "$plan")
    swap=$(jq -er '.partitions[0].bytes' <<< "$plan")
    rescue=$(jq -er '.partitions[1].bytes' <<< "$plan")
    lpmake --device-size "$capacity" --super-name super --alignment 1048576 \
        --metadata-size 65536 --metadata-slots 3 --group "$group:$usable" \
        --partition "system_b:none:$rescue:$group" --partition "system_a:none:$swap:$group" \
        --output "$work/metadata-$phase.img" > "$work/lpmake.log" 2>&1
    [[ $(stat -c %s "$work/metadata-$phase.img") -le 1048576 ]]
    lpflash /proc/self/fd/4 "$work/metadata-$phase.img" > "$work/lpflash.log" 2>&1
}
create_map() {
    local role=$1 index=$2 mode=${3:-rw} map_layout=${4:-$target} start sectors name=uke-super-grow-$1
    local -a options=()
    [[ $mode != ro ]] || options+=(--readonly)
    if dmsetup info "$name" >/dev/null 2>&1; then fail 'provisioning mapper name already occupied'; fi
    start=$(jq -er --argjson index "$index" '.partitions[$index].start_byte / 512' <<< "$map_layout")
    sectors=$(jq -er --argjson index "$index" '.partitions[$index].bytes / 512' <<< "$map_layout")
    owned+=("$name")
    printf '0 %s linear %s %s\n' "$sectors" "$devno" "$start" |
        dmsetup --noudevsync create "${options[@]}" --uuid "UKE-GROW-v1-$tag-$role" "$name"
    dmsetup mknodes "$name"
    [[ $(blockdev --getsize64 "/dev/mapper/$name") == "$((sectors * 512))" ]]
}
check_saved_state() {
    local path=$1 signature status=0
    signature=$(blkid -p -s TYPE -o value "$path" 2>/dev/null) || status=$?
    [[ $status == 0 || $status == 2 ]] || fail 'ambiguous swap signature'
    case $signature in swsuspend|crypto_LUKS|BitLocker) fail 'possible saved or encrypted state; refusing fresh swap initialization';; esac
}
remove_maps() {
    local name uuid
    for name in "${owned[@]}"; do
        uuid=$(dmsetup info -c --noheadings -o uuid "$name" | tr -d '[:space:]')
        [[ $uuid == "UKE-GROW-v1-$tag-${name##*-}" ]] || fail 'mapper ownership changed'
        dmsetup --noudevsync remove --retry "$name"
    done
    owned=()
}
payload_checked=false
metadata_written=false
if [[ $action != verify-ready ]]; then
    [[ $(blockdev --getro /proc/self/fd/3) == 0 ]] || fail 'super is read-only'
    node=${device##*/}
    for holder in /sys/class/block/"$node"/holders/*; do
        [[ ! -e $holder ]] || fail 'super has an active holder; no provisioning while a mapped volume is in use'
    done
    if awk -v dev="$devno" '$3==dev {found=1} END {exit !found}' /proc/self/mountinfo; then fail 'super is mounted'; fi
    while read -r path _; do
        [[ -b $path ]] || continue
        [[ $(lsblk -dnro MAJ:MIN "$path") != "$devno" ]] || fail 'super is active swap'
    done < /proc/swaps
    if [[ $action == grow-fresh-seed ]]; then
        create_map rescue 1 ro
        rescue=/dev/mapper/uke-super-grow-rescue
        [[ $(blkid -p -s TYPE -o value "$rescue") == ext4 && $(blkid -p -s LABEL -o value "$rescue") == FEDORA_RESCUE ]] || fail 'fresh rescue identity differs'
        dumpe2fs -h "$rescue" > "$work/header" 2>/dev/null
        blocks=$(awk '/^Block count:/ {print $3}' "$work/header")
        block_size=$(awk '/^Block size:/ {print $3}' "$work/header")
        [[ $blocks =~ ^[1-9][0-9]*$ && $block_size == 4096 ]]
        minimum=$(jq -er '.seed_layout.partitions[1].bytes' "$work/plan.json")
        maximum=$(jq -er '.partitions[1].bytes' <<< "$target")
        ((blocks * block_size >= minimum && blocks * block_size <= maximum)) || fail 'rescue filesystem is outside the seed/target bounds'
        create_map swap 0 ro
        check_saved_state /dev/mapper/uke-super-grow-swap
        if jq -e 'any(.observed_metadata_slots[]; .phase=="seed")' "$work/plan.json" >/dev/null; then
            seed=$(jq -c .seed_layout "$work/plan.json")
            create_map oldswap 0 ro "$seed"
            check_saved_state /dev/mapper/uke-super-grow-oldswap
        fi
        remove_maps
    fi
    exec 4<> "$device"
    [[ $(blockdev --getsize64 /proc/self/fd/4) == "$capacity" ]]
    if [[ $action == grow-fresh-seed ]]; then
        write_metadata growing
        snapshot
        TMPDIR="$work" bash "$here/inspect-fastboot-super.sh" --image "$capacity" "$work/snapshot.raw" growing > "$work/growing.json"
        create_map rescue 1
        rescue=/dev/mapper/uke-super-grow-rescue
        [[ $(blkid -p -s TYPE -o value "$rescue") == ext4 && $(blkid -p -s LABEL -o value "$rescue") == FEDORA_RESCUE ]] || fail 'fresh rescue identity differs'
        status=0
        (ulimit -f 1024; timeout --kill-after=2s 60s e2fsck -pf "$rescue") > "$work/fsck.log" 2>&1 || status=$?
        [[ $status == 0 || $status == 1 ]] || fail 'rescue needs manual recovery before growth'
        (ulimit -f 1024; timeout --kill-after=2s 60s resize2fs "$rescue") > "$work/resize.log" 2>&1
        dumpe2fs -h "$rescue" > "$work/header" 2>/dev/null
        blocks=$(awk '/^Block count:/ {print $3}' "$work/header")
        block_size=$(awk '/^Block size:/ {print $3}' "$work/header")
        [[ $blocks =~ ^[1-9][0-9]*$ && $block_size == 4096 ]]
        expected=$(jq -er '.partitions[1].bytes' <<< "$target")
        ((blocks * block_size == expected)) || fail 'rescue did not fill its allocation'
        create_map swap 0
        swap=/dev/mapper/uke-super-grow-swap
        check_saved_state "$swap"
        mkswap --pagesize 4096 --label linux_swap "$swap" > "$work/mkswap.log"
        [[ $(blkid -p -s TYPE -o value "$swap") == swap && $(blkid -p -s LABEL -o value "$swap") == linux_swap ]]
        read -r b0 b1 b2 b3 < <(od -An -v -j1028 -N4 -tu1 "$swap")
        last_page=$((b0 + (b1 << 8) + (b2 << 16) + (b3 << 24)))
        expected=$(jq -er '.partitions[0].bytes' <<< "$target")
        (((last_page + 1) * 4096 == expected)) || fail 'swap does not fill its allocation'
        remove_maps
        blockdev --flushbufs /proc/self/fd/4
        payload_checked=true
    fi
    # A ready view forbids payload initialization, including on restart after
    # a torn final metadata commit. Only make the same geometry consistent.
    write_metadata ready
    metadata_written=true
fi
snapshot
TMPDIR="$work" bash "$here/inspect-fastboot-super.sh" --image "$capacity" "$work/snapshot.raw" > "$work/ready.json"
jq -M -n --arg prior "$action" --argjson layout "$target" --argjson payload "$payload_checked" --argjson written "$metadata_written" \
    '{schema_version:1,prior_action:$prior,layout:$layout,all_metadata_views_ready:true,
      rescue_full_capacity_and_swap_initialized_this_boot:$payload,metadata_written_this_boot:$written,
      rescue_payload_relocated:false,userdata_modified:false,gpt_modified:false,
      physical_ufs_selection_verified:false,metadata_authenticity_verified:false,
      real_power_loss_tested:false,operating_system_booted:false}'
