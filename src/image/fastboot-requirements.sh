#!/usr/bin/env bash
# Host-only android-info requirements. Original fastboot checks these before
# selecting a slot or downloading/flashing any payload. No wildcard capacities.
fastboot_requirements() {
    local geometry partition bytes lower padded8 padded16 options values
    (($# >= 1 && $# <= 16)) || return 1
    for geometry in "$@"; do
        [[ -f $geometry && ! -L $geometry ]] || return 1
        jq -e '.product == "uke" and (.partitions|type)=="object" and
          (.partitions|keys) == ["boot_a","boot_b","dtbo_a","dtbo_b","super","userdata",
            "vbmeta_a","vbmeta_b","vendor_boot_a","vendor_boot_b"] and
          all(.partitions[]; type=="number" and floor==. and .>0 and .<=2199023255552)' "$geometry" >/dev/null || return 1
    done
    printf 'require product=uke\nrequire is-userspace=no\nrequire slot-count=2\n'
    for partition in boot_a boot_b dtbo_a dtbo_b super userdata vbmeta_a vbmeta_b vendor_boot_a vendor_boot_b; do
        values=''
        while read -r bytes; do
            printf -v lower '0x%x' "$bytes"
            printf -v padded8 '0x%08x' "$bytes"
            printf -v padded16 '0x%016x' "$bytes"
            values+=$(printf '%s\n' "$lower" "$padded8" "$padded16")$'\n'
        done < <(jq -er --arg key "$partition" '.partitions[$key]' "$@" | LC_ALL=C sort -nu)
        values+=$(printf '%s' "$values" | tr 'a-f' 'A-F')$'\n'
        options=$(printf '%s' "$values" | sed '/^$/d' | LC_ALL=C sort -u | paste -sd '|')
        printf 'require partition-size:%s=%s\n' "$partition" "$options"
    done
}
