#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Pure calculations for a capacity-derived Android logical-partition container.
# Sourcing this file neither probes nor writes a device.

fastboot_install_name() {
    local day=$1 actual
    [[ $day =~ ^[0-9]{6}$ ]] || return 2
    actual=$(date -u -d "20${day:4:2}-${day:2:2}-${day:0:2}" +%d%m%y 2>/dev/null) || return 2
    [[ $actual == "$day" ]] || return 2
    printf 'fedora-rawhide-linux-kde-plasma-uke-senemos-sbfb-%s.zip\n' "$day"
}

fastboot_super_layout() {
    local capacity=$1 alignment=1048576 metadata_size=65536 metadata_slots=3
    local metadata_bytes first_byte last_byte usable swap rescue unallocated
    [[ $capacity =~ ^[1-9][0-9]{0,12}$ ]] || return 2
    # Bound all arithmetic and reject geometries too small for the actual rescue.
    ((capacity <= 2199023255552)) || return 2
    # liblp reserved bytes + two geometry records + primary/backup metadata slots.
    metadata_bytes=$((4096 + 2 * 4096 + 2 * metadata_size * metadata_slots))
    first_byte=$(((metadata_bytes + alignment - 1) / alignment * alignment))
    last_byte=$((capacity / alignment * alignment))
    usable=$((last_byte - first_byte))
    ((usable > 0)) || return 2
    swap=$((usable / alignment * 80 / 100 * alignment))
    rescue=$((usable - swap))
    ((swap >= 1048576 && rescue >= 805306368)) || return 2
    unallocated=$((capacity - metadata_bytes - swap - rescue))
    jq -n --argjson capacity "$capacity" --argjson first "$first_byte" \
        --argjson usable "$usable" --argjson swap "$swap" --argjson rescue "$rescue" \
        --argjson padding "$unallocated" --argjson metadata "$metadata_bytes" \
        --argjson alignment "$alignment" --argjson msize "$metadata_size" --argjson slots "$metadata_slots" \
        '{schema_version:2,super_bytes:$capacity,partition_table_changes:false,
          layout_kind:"liblp",metadata_size:$msize,metadata_slots:$slots,
          metadata_reserved_bytes:$metadata,alignment_bytes:$alignment,
          first_logical_byte:$first,usable_payload_bytes:$usable,alignment_padding_bytes:$padding,
          group:{name:"uke_linux",maximum_size:$usable},
          partitions:[
            {name:"system_a",label:"linux_swap",role:"swap",format:"swap",bytes:$swap,percentage:80},
            {name:"system_b",label:"FEDORA_RESCUE",role:"fedora-live-rescue",format:"ext4",bytes:$rescue,percentage:20}],
          opt_partition:false,android_restore:"restore matching stock super and boot cohort; GPT geometry remains unchanged",
          physical_acceptance:false}'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -Eeuo pipefail
    case ${1:-} in
        name) [[ $# == 2 ]]; fastboot_install_name "$2";;
        layout) [[ $# == 2 ]]; fastboot_super_layout "$2";;
        *) printf 'Usage: %s name DDMMYY | layout SUPER_BYTES\n' "${0##*/}" >&2; exit 2;;
    esac
fi
