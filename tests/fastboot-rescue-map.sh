#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Original-tool, owned-loop mapper fixture. Never point run at a real device.
set -Eeuo pipefail
export LC_ALL=C
umask 077
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
helper=$root/src/image/map-fastboot-rescue.sh
case ${1:-} in
    prepare)
        [[ $# == 2 && ! -e $2 && ! -L $2 ]]
        output=$(realpath -m "$2")
        mkdir -m700 "$output"
        work=$(mktemp -d "$output/work.XXXXXXXX")
        trap 'find "$work" -depth -delete' EXIT
        bash "$root/src/image/fastboot-singleboot-layout.sh" layout 4294967296 > "$output/layout.json"
        swap=$(jq -er '.partitions[0].bytes' "$output/layout.json")
        rescue=$(jq -er '.partitions[1].bytes' "$output/layout.json")
        usable=$(jq -er .usable_payload_bytes "$output/layout.json")
        mkdir "$work/files"
        printf 'Independent rescue mapping fixture; not a bootable OS.\n' > "$work/files/sentinel.txt"
        cp "$work/files/sentinel.txt" "$output/sentinel.txt"
        truncate -s 64M "$work/rescue.raw"
        mke2fs -q -F -t ext4 -b 4096 -L FEDORA_RESCUE -d "$work/files" "$work/rescue.raw"
        truncate -s "$rescue" "$work/rescue.raw"
        resize2fs "$work/rescue.raw" >/dev/null 2>&1
        lpmake --device-size 4294967296 --super-name super --alignment 1048576 \
            --metadata-size 65536 --metadata-slots 3 --group "uke_linux:$usable" \
            --partition "system_b:none:$rescue:uke_linux" --partition "system_a:none:$swap:uke_linux" \
            --image "system_b=$work/rescue.raw" --sparse --output "$work/super.sparse"
        simg2img "$work/super.sparse" "$output/super.raw"
        [[ $(stat -c %s "$output/super.raw") == 4294967296 ]]
        ;;
    run)
        [[ $# == 4 && $(id -u) == 0 && -b $2 && -d $3 && ! -e $4 && ! -L $4 ]]
        device=$(readlink -e "$2")
        fixture=$(realpath "$3")
        report=$(realpath -m "$4")
        # Refuse non-loop devices even when they contain a plausible layout.
        [[ $device =~ ^/dev/loop[0-9]+$ ]]
        [[ $(blockdev --getsize64 "$device") == 4294967296 ]]
        # A container bind mount changes the pathname, but not the backing
        # filesystem/inode. Compare those identities instead of a host path.
        [[ $(losetup -n -O BACK-INO "$device" | tr -d '[:space:]') == "$(stat -c %i "$fixture/super.raw")" ]]
        [[ $(losetup -n -O BACK-MAJ:MIN "$device" | tr -d '[:space:]') == "$(findmnt -nro MAJ:MIN --target "$fixture/super.raw")" ]]
        devno=$(lsblk -dnro MAJ:MIN "$device")
        tag=${devno/:/-}
        expected_uuid=UKE-RESCUE-v1-$tag
        occupied_uuid=UKE-FIXTURE-RESCUE-occupied-$tag
        payload_uuid=UKE-FIXTURE-RESCUE-payload-$tag
        work=$(mktemp -d "$fixture/run.XXXXXXXX")
        real_blockdev=$(command -v blockdev)
        cleanup() {
            local result=$? name actual
            trap - EXIT
            for name in uke-rescue uke-rescue-test-payload; do
                if actual=$(dmsetup info -c --noheadings -o uuid "$name" 2>/dev/null | tr -d '[:space:]'); then
                    case $actual in
                        "$expected_uuid"|"$occupied_uuid"|"$payload_uuid") dmsetup --noudevsync remove --retry "$name" || result=1;;
                    esac
                fi
            done
            find "$work" -depth -delete
            exit "$result"
        }
        trap cleanup EXIT
        for name in uke-rescue uke-rescue-test-payload; do
            if dmsetup info "$name" >/dev/null 2>&1; then echo 'Fixture mapper name already exists' >&2; exit 1; fi
        done
        before=$(sha256sum "$device" | cut -d ' ' -f1)
        printf '0 8 linear %s 0\n' "$devno" | dmsetup --noudevsync create --uuid "$occupied_uuid" uke-rescue
        if bash "$helper" "$device" > "$work/refused.json" 2> "$work/refused.log"; then exit 1; fi
        grep -q 'already occupied' "$work/refused.log"
        [[ $(dmsetup info -c --noheadings -o uuid uke-rescue | tr -d '[:space:]') == "$occupied_uuid" ]]
        dmsetup --noudevsync remove uke-rescue
        # Change a private alternate node only after the helper has opened it.
        # Mapping identity must follow that descriptor, not a second path lookup.
        alias_node=$work/owned-loop-alias
        mknod "$alias_node" b "${devno%:*}" "${devno#*:}"
        mkdir "$work/replace-alias"
        cat > "$work/replace-alias/blockdev" <<SH
#!/usr/bin/env bash
set -Eeuo pipefail
'$real_blockdev' "\$@"
if [[ \$* == '--getsize64 /proc/self/fd/3' && ! -e '$work/alias-replaced' ]]; then
    unlink '$alias_node'
    ln -s /dev/null '$alias_node'
    : > '$work/alias-replaced'
fi
SH
        chmod +x "$work/replace-alias/blockdev"
        PATH="$work/replace-alias:$PATH" bash "$helper" "$alias_node" > "$work/mapping.json"
        [[ -f $work/alias-replaced && -L $alias_node && $(readlink "$alias_node") == /dev/null ]]
        jq -e '.readonly_linear_mapping and .three_slot_topology_verified and
            .ext4_label_and_full_capacity_verified and .rescue_bytes == 858783744 and
            (.root_switch_executed | not) and (.metadata_authenticity_verified | not)' "$work/mapping.json" >/dev/null
        [[ $(blockdev --getro /dev/mapper/uke-rescue) == 1 ]]
        debugfs -R "dump /sentinel.txt $work/sentinel.txt" /dev/mapper/uke-rescue >/dev/null 2>&1
        cmp "$fixture/sentinel.txt" "$work/sentinel.txt"
        if dd if=/dev/zero of=/dev/mapper/uke-rescue bs=4096 count=1 conv=notrunc status=none > "$work/write.log" 2>&1; then
            echo 'Read-only rescue unexpectedly accepted a write' >&2; exit 1
        fi
        after=$(sha256sum "$device" | cut -d ' ' -f1)
        [[ $before == "$after" ]]
        cp "$work/mapping.json" "$fixture/mapping-result.json"
        dmsetup --noudevsync remove uke-rescue
        # Change only this owned loop fixture, then exercise post-create failure
        # cleanup: a valid liblp layout must not admit the wrong filesystem label.
        start=$(jq -er '.partitions[1].start_byte / 512' "$fixture/layout.json")
        sectors=$(jq -er '.partitions[1].bytes / 512' "$fixture/layout.json")
        printf '0 %s linear %s %s\n' "$sectors" "$devno" "$start" |
            dmsetup --noudevsync create --uuid "$payload_uuid" uke-rescue-test-payload
        dmsetup mknodes uke-rescue-test-payload
        e2label /dev/mapper/uke-rescue-test-payload WRONG_RESCUE
        dmsetup --noudevsync remove uke-rescue-test-payload
        if bash "$helper" "$device" > "$work/refused.json" 2> "$work/refused.log"; then exit 1; fi
        grep -q 'not provisioned EXT4' "$work/refused.log"
        if dmsetup info uke-rescue >/dev/null 2>&1; then echo 'Failed helper left its own mapper active' >&2; exit 1; fi
        jq -M -n --arg before "$before" --arg after "$after" \
            '{schema_version:1,owned_loop_only:true,real_readonly_dm_mapping:true,
              independent_ext4_file_readback:true,write_to_readonly_mapping_refused:true,
              backing_sha256_before:$before,backing_sha256_after:$after,
              occupied_mapping_preserved:true,wrong_label_refused_and_own_mapper_removed:true,
              mapping_identity_pinned_across_path_replacement:true,
              userdata_dependency:false,physical_ufs_tested:false,rescue_os_boot_tested:false,
              secure_boot_tested:false,encryption_tested:false}' > "$report"
        ;;
    *) printf 'Usage: %s prepare NEW_DIRECTORY | run OWNED_LOOP FIXTURE_DIRECTORY NEW_REPORT\n' "${0##*/}" >&2; exit 2;;
esac
