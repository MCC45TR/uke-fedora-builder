#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Pure calculations for a capacity-derived Android logical-partition container.
# Sourcing this file neither probes nor writes a device.

fastboot_rescue_kernel() {
    jq -e '
        .kernel_profile=="normal" and .kernel_rpm_signature=="verified COPR signature" and
        .kernel_family=="senemos-uke-linux-kernel-mainline" and
        (.kernel_source_commit|test("^[a-f0-9]{40}$")) and
        (.kernel_repository|IN("mcc45tr/uke-linux","mcc45tr/uke-linux-test","mcc45tr/uke-linux-unstable")) and
        ((.kernel_release|test("^7[.]4[.][0-9]+-senemos$")) or
         ((.kernel_release|test("^7[.]3[.]5-([2-9][0-9]|[1-9][0-9]{2,})$")) and
          .kernel_release==.rpm_version_release))
    ' "$1" >/dev/null
}

fastboot_super_layout() {
    local capacity=$1 phase=${2:-ready} group alignment=1048576 metadata_size=65536 metadata_slots=3
    local metadata_bytes first_byte last_byte usable swap rescue unallocated
    [[ $capacity =~ ^[1-9][0-9]{0,12}$ ]] || return 2
    case $phase in ready) group=uke_linux;; seed) group=uke_seed;; growing) group=uke_growing;; *) return 2;; esac
    # Bound all arithmetic and reject geometries too small for the actual rescue.
    ((capacity <= 2199023255552)) || return 2
    # liblp reserved bytes + two geometry records + primary/backup metadata slots.
    metadata_bytes=$((4096 + 2 * 4096 + 2 * metadata_size * metadata_slots))
    first_byte=$(((metadata_bytes + alignment - 1) / alignment * alignment))
    last_byte=$((capacity / alignment * alignment))
    usable=$((last_byte - first_byte))
    ((usable > 0)) || return 2
    # Round the percentage DOWN to whole allocation units, leaving every
    # remaining unit to rescue. Do not combine these integer divisions.
    swap=$((usable / alignment))
    swap=$((swap * 80 / 100))
    swap=$((swap * alignment))
    rescue=$((usable - swap))
    ((swap >= 1048576 && rescue >= 805306368)) || return 2
    unallocated=$((capacity - metadata_bytes - swap - rescue))
    jq -n --argjson capacity "$capacity" --argjson first "$first_byte" \
        --argjson usable "$usable" --argjson swap "$swap" --argjson rescue "$rescue" \
        --argjson padding "$unallocated" --argjson metadata "$metadata_bytes" \
        --arg phase "$phase" --arg group "$group" \
        --argjson alignment "$alignment" --argjson msize "$metadata_size" --argjson slots "$metadata_slots" \
        '{schema_version:3,super_bytes:$capacity,phase:$phase,partition_table_changes:false,
          layout_kind:"liblp",metadata_size:$msize,metadata_slots:$slots,
          metadata_reserved_bytes:$metadata,alignment_bytes:$alignment,
          first_logical_byte:$first,usable_payload_bytes:$usable,alignment_padding_bytes:$padding,
          group:{name:$group,maximum_size:$usable},allocation_order:["system_b","system_a"],
          rescue_relocation_required:false,
          partitions:[
            {name:"system_a",label:"linux_swap",role:"swap",format:"swap",bytes:$swap,start_byte:($first+$rescue),percentage:80},
            {name:"system_b",label:"FEDORA_RESCUE",role:"fedora-live-rescue",format:"ext4",bytes:$rescue,start_byte:$first,percentage:20}],
          opt_partition:false,android_restore:"restore matching stock super and boot cohort; GPT geometry remains unchanged",
          physical_acceptance:false}'
}

fastboot_seed_layout() {
    local rescue_bytes=$1 minimum_super=$2 aligned capacity
    [[ $rescue_bytes =~ ^[1-9][0-9]{0,11}$ && $minimum_super =~ ^[1-9][0-9]{0,12}$ ]] || return 2
    ((rescue_bytes <= 68719476736 && minimum_super <= 2199023255552)) || return 2
    aligned=$(((rescue_bytes + 1048575) / 1048576 * 1048576))
    # Every seed keeps the same 80/20 roles. At least 4 GiB covers the minimum
    # rescue contract; larger rescue inputs determine a larger aligned seed.
    capacity=$((aligned * 5 + 1048576))
    ((capacity >= 4294967296)) || capacity=4294967296
    ((capacity <= minimum_super)) || return 2
    fastboot_super_layout "$capacity" seed
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -Eeuo pipefail
    case ${1:-} in
        layout) [[ $# == 2 || $# == 3 ]]; fastboot_super_layout "$2" "${3:-ready}";;
        seed) [[ $# == 3 ]]; fastboot_seed_layout "$2" "$3";;
        *) printf 'Usage: %s layout SUPER_BYTES [ready|seed|growing] | seed RESCUE_BYTES MINIMUM_SUPER_BYTES\n' "${0##*/}" >&2; exit 2;;
    esac
fi
