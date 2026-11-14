#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Real original-tool provisioning on one owned 4-KiB loop device in CI.
set -Eeuo pipefail
export LC_ALL=C
umask 077
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
helper=$root/src/image/provision-fastboot-super.sh
case ${1:-} in
    prepare-seed)
        [[ $# == 3 && -d $2 && ! -L $2 && ! -e $3 && ! -L $3 ]]
        source_seed=$(realpath "$2")
        output=$(realpath -m "$3")
        available=$(df -Pk "$(dirname "$output")" | awk 'NR==2 {print $4}')
        ((available >= 14680064)) || { echo 'Need a bounded 12-GiB peak and 2-GiB reserve' >&2; exit 1; }
        jq -e '.artifact_kind=="unqualified-fastboot-super-seed" and
            .seed_layout.phase=="seed" and .seed_layout.super_bytes<8589934592' "$source_seed/super-seed.json" >/dev/null
        [[ $(sha256sum "$source_seed/super.img" | cut -d ' ' -f1) == "$(jq -er .super_sparse_sha256 "$source_seed/super-composition.json")" ]]
        mkdir -m700 "$output"
        work=$(mktemp -d "$output/work.XXXXXXXX")
        trap 'find "$work" -depth -delete' EXIT
        cp "$source_seed/super-layout.json" "$output/seed.json"
        simg2img "$source_seed/super.img" "$output/super.raw"
        [[ $(stat -c %s "$output/super.raw") == "$(jq -er .super_bytes "$output/seed.json")" ]]
        sync "$output/super.raw"
        fadvise --advice dontneed "$output/super.raw"
        lpunpack -p system_b "$output/super.raw" "$work"
        release=$(jq -er '.rescue_input.kernel.kernel_release' "$source_seed/super-seed.json")
        [[ $release =~ ^7[.]3[.][0-9]+-[1-9][0-9]*-unstable$ ]]
        debugfs -R "dump /usr/lib/systemd/systemd $output/systemd.expected" "$work/system_b.img" >/dev/null 2>&1
        debugfs -R "dump /etc/fstab $output/fstab.expected" "$work/system_b.img" >/dev/null 2>&1
        debugfs -R "dump /usr/share/senemos/uke/$release/source-commit $output/source.expected" "$work/system_b.img" >/dev/null 2>&1
        [[ $(cat "$output/source.expected") == "$(jq -er '.rescue_input.kernel.kernel_source_commit' "$source_seed/super-seed.json")" ]]
        jq -n --arg release "$release" --arg hash "$(sha256sum "$source_seed/super.img" | cut -d ' ' -f1)" \
            '{kernel_release:$release,seed_sparse_sha256:$hash,extra_fixture_files_in_rescue:false}' > "$output/actual-rescue.json"
        truncate -s 8589934592 "$output/super.raw"
        ;;
    prepare)
        [[ $# == 2 && ! -e $2 && ! -L $2 ]]
        output=$(realpath -m "$2")
        available=$(df -Pk "$(dirname "$output")" | awk 'NR==2 {print $4}')
        ((available >= 14680064)) || { echo 'Need a bounded 12-GiB peak and 2-GiB reserve' >&2; exit 1; }
        mkdir -m700 "$output"
        work=$(mktemp -d "$output/work.XXXXXXXX")
        trap 'find "$work" -depth -delete' EXIT
        bash "$root/src/image/fastboot-singleboot-layout.sh" seed 67108864 8321499136 > "$output/seed.json"
        seed=$(jq -er .super_bytes "$output/seed.json")
        swap=$(jq -er '.partitions[0].bytes' "$output/seed.json")
        rescue=$(jq -er '.partitions[1].bytes' "$output/seed.json")
        usable=$(jq -er .usable_payload_bytes "$output/seed.json")
        mkdir "$work/files"
        printf 'Rescue survives capacity provisioning and phase restarts.\n' > "$work/files/sentinel.txt"
        cp "$work/files/sentinel.txt" "$output/sentinel.txt"
        truncate -s 64M "$work/rescue.raw"
        mke2fs -q -F -t ext4 -b 4096 -L FEDORA_RESCUE -d "$work/files" "$work/rescue.raw"
        truncate -s "$rescue" "$work/rescue.raw"
        resize2fs "$work/rescue.raw" >/dev/null 2>&1
        truncate -s "$swap" "$work/swap.raw"
        mkswap --pagesize 4096 --label linux_swap "$work/swap.raw" >/dev/null 2>&1
        lpmake --device-size "$seed" --super-name super --alignment 1048576 --metadata-size 65536 --metadata-slots 3 \
            --group "uke_seed:$usable" --partition "system_b:none:$rescue:uke_seed" --partition "system_a:none:$swap:uke_seed" \
            --image "system_b=$work/rescue.raw" --image "system_a=$work/swap.raw" --sparse --output "$work/super.sparse"
        simg2img "$work/super.sparse" "$output/super.raw"
        truncate -s 8589934592 "$output/super.raw"
        ;;
    run)
        [[ $# == 4 && $(id -u) == 0 && -b $2 && -d $3 && ! -e $4 && ! -L $4 ]]
        device=$(readlink -e "$2")
        fixture=$(realpath "$3")
        report=$(realpath -m "$4")
        [[ $device =~ ^/dev/loop[0-9]+$ && $(blockdev --getsize64 "$device") == 8589934592 && $(blockdev --getss "$device") == 4096 ]]
        [[ $(losetup -n -O BACK-INO "$device" | tr -d '[:space:]') == "$(stat -c %i "$fixture/super.raw")" ]]
        [[ $(losetup -n -O BACK-MAJ:MIN "$device" | tr -d '[:space:]') == "$(findmnt -nro MAJ:MIN --target "$fixture/super.raw")" ]]
        devno=$(lsblk -dnro MAJ:MIN "$device")
        tag=${devno/:/-}
        work=$(mktemp -d "$fixture/run.XXXXXXXX")
        real_lpflash=$(command -v lpflash)
        real_mkswap=$(command -v mkswap)
        real_dmsetup=$(command -v dmsetup)
        alias_node=$work/owned-loop-alias
        mknod "$alias_node" b "${devno%:*}" "${devno#*:}"
        cleanup() {
            local status=$? name uuid
            trap - EXIT
            for name in uke-rescue uke-super-grow-rescue uke-super-grow-swap uke-super-grow-oldswap uke-super-test-busy; do
                if uuid=$(dmsetup info -c --noheadings -o uuid "$name" 2>/dev/null | tr -d '[:space:]'); then
                    case $uuid in
                        "UKE-GROW-v1-$tag-rescue"|"UKE-GROW-v1-$tag-swap"|"UKE-GROW-v1-$tag-oldswap"|"UKE-GROW-TEST-v1-$tag"|"UKE-RESCUE-v1-$tag")
                            dmsetup --noudevsync remove --retry "$name" || status=1;;
                    esac
                fi
            done
            find "$work" -depth -delete
            exit "$status"
        }
        trap cleanup EXIT
        for name in uke-rescue uke-super-grow-rescue uke-super-grow-swap uke-super-grow-oldswap uke-super-test-busy; do
            if dmsetup info "$name" >/dev/null 2>&1; then echo 'Fixture mapper name occupied' >&2; exit 1; fi
        done
        invoke() { bash "$helper" --fresh-install "$device" "$fixture/seed.json"; }
        prefix() { dd if="$device" of="$1" bs=1048576 count=1 iflag=fullblock status=none; }
        expect_failure() {
            if invoke > "$work/refused.json" 2> "$work/refused.log"; then echo 'Injected failure was not reached' >&2; exit 1; fi
        }
        # Block unrelated holders before the first metadata/payload write.
        prefix "$work/seed-prefix"
        printf '0 8 linear %s 0\n' "$devno" | dmsetup --noudevsync create --readonly --uuid "UKE-GROW-TEST-v1-$tag" uke-super-test-busy
        expect_failure
        grep -q 'active holder' "$work/refused.log"
        if bash "$helper" --fresh-install "$alias_node" "$fixture/seed.json" > "$work/alias-refused.json" 2> "$work/alias-refused.log"; then
            echo 'Alternate block node bypassed the active-holder check' >&2; exit 1
        fi
        grep -q 'active holder' "$work/alias-refused.log"
        prefix "$work/after-refusal"
        cmp "$work/seed-prefix" "$work/after-refusal"
        dmsetup --noudevsync remove uke-super-test-busy
        # A saved-image signature at the old seed swap would lie inside the
        # enlarged rescue. Refuse it before changing metadata or filesystem.
        old_start=$(jq -er '.partitions[0].start_byte' "$fixture/seed.json")
        dd if="$device" of="$work/old-swap-page" bs=4096 skip="$((old_start / 4096))" count=1 status=none
        printf 'S1SUSPEND\000' | dd of="$device" bs=1 seek="$((old_start + 4096 - 10))" conv=notrunc status=none
        expect_failure
        grep -q 'saved or encrypted state' "$work/refused.log"
        prefix "$work/after-refusal"
        cmp "$work/seed-prefix" "$work/after-refusal"
        dd if="$work/old-swap-page" of="$device" bs=4096 seek="$((old_start / 4096))" count=1 conv=notrunc status=none
        # Stop after original lpflash committed the growing phase.
        mkdir "$work/stop-after-metadata" "$work/stop-after-payload" "$work/forbid-writes"
        cat > "$work/stop-after-metadata/lpflash" <<SH
#!/usr/bin/env bash
set -Eeuo pipefail
'$real_lpflash' "\$@"
[[ \${2##*/} != metadata-growing.img ]] || exit 97
SH
        cat > "$work/stop-after-payload/mkswap" <<SH
#!/usr/bin/env bash
set -Eeuo pipefail
'$real_mkswap' "\$@"
exit 97
SH
        for tool in lpflash mkswap resize2fs e2fsck; do
            printf '#!/bin/sh\necho "Mutation unexpectedly repeated" >&2\nexit 97\n' > "$work/forbid-writes/$tool"
        done
        chmod +x "$work/stop-after-metadata/lpflash" "$work/stop-after-payload/mkswap" "$work/forbid-writes/"*
        PATH="$work/stop-after-metadata:$PATH" expect_failure
        prefix "$work/growing-prefix"
        # The retry really grows EXT4 and initializes the final swap, then stops
        # before the ready commit. There are no production test switches.
        PATH="$work/stop-after-payload:$PATH" expect_failure
        # Replace only the private alias after the last read-only preflight
        # mapping is removed. The writer must still use the checked inode.
        mkdir "$work/replace-alias"
        cat > "$work/replace-alias/dmsetup" <<SH
#!/usr/bin/env bash
set -Eeuo pipefail
'$real_dmsetup' "\$@"
if [[ \$* == '--noudevsync remove --retry uke-super-grow-swap' && ! -e '$work/alias-replaced' ]]; then
    unlink '$alias_node'
    ln -s /dev/null '$alias_node'
    : > '$work/alias-replaced'
fi
SH
        chmod +x "$work/replace-alias/dmsetup"
        PATH="$work/replace-alias:$PATH" bash "$helper" --fresh-install "$alias_node" "$fixture/seed.json" > "$work/completed.json"
        [[ -f $work/alias-replaced && -L $alias_node && $(readlink "$alias_node") == /dev/null ]]
        jq -e '.prior_action=="grow-fresh-seed" and .all_metadata_views_ready and
            .rescue_full_capacity_and_swap_initialized_this_boot and
            (.rescue_payload_relocated|not) and (.userdata_modified|not)' "$work/completed.json" >/dev/null
        prefix "$work/ready-prefix"
        bash "$root/src/image/map-fastboot-rescue.sh" "$device" > "$work/mapped.json"
        actual_fedora=false
        if [[ -f $fixture/actual-rescue.json && ! -L $fixture/actual-rescue.json ]]; then
            release=$(jq -er .kernel_release "$fixture/actual-rescue.json")
            [[ $release =~ ^7[.]3[.][0-9]+-[1-9][0-9]*-unstable$ ]]
            debugfs -R "dump /usr/lib/systemd/systemd $work/systemd" /dev/mapper/uke-rescue >/dev/null 2>&1
            debugfs -R "dump /etc/fstab $work/fstab" /dev/mapper/uke-rescue >/dev/null 2>&1
            debugfs -R "dump /usr/share/senemos/uke/$release/source-commit $work/source" /dev/mapper/uke-rescue >/dev/null 2>&1
            cmp "$fixture/systemd.expected" "$work/systemd"
            cmp "$fixture/fstab.expected" "$work/fstab"
            cmp "$fixture/source.expected" "$work/source"
            debugfs -R 'ea_list /usr/lib/systemd/systemd' /dev/mapper/uke-rescue 2>/dev/null |
                grep -F 'system_u:object_r:init_exec_t:s0' >/dev/null
            actual_fedora=true
        else
            debugfs -R "dump /sentinel.txt $work/sentinel.txt" /dev/mapper/uke-rescue >/dev/null 2>&1
            cmp "$fixture/sentinel.txt" "$work/sentinel.txt"
        fi
        dmsetup --noudevsync remove uke-rescue
        # Emulate a torn final metadata commit: only slot0 reached ready. The
        # retry may repair copies but must never touch filesystem/swap payloads.
        dd if="$work/growing-prefix" of="$device" bs=1048576 count=1 conv=notrunc status=none
        for block in 3 51; do
            dd if="$work/ready-prefix" of="$device" bs=4096 skip="$block" seek="$block" count=16 conv=notrunc status=none
        done
        mkdir "$work/forbid-payload"
        for tool in mkswap resize2fs e2fsck; do cp "$work/forbid-writes/$tool" "$work/forbid-payload/$tool"; done
        before=$(sha256sum "$device" | cut -d ' ' -f1)
        PATH="$work/forbid-payload:$PATH" invoke > "$work/metadata-retry.json"
        jq -e '.prior_action=="finish-ready-metadata" and .metadata_written_this_boot and
            (.rescue_full_capacity_and_swap_initialized_this_boot|not)' "$work/metadata-retry.json" >/dev/null
        # Full ready is a read-only no-op, including during a later encrypted or
        # hibernated installation. Verify every byte of this owned loop device.
        stable=$(sha256sum "$device" | cut -d ' ' -f1)
        PATH="$work/forbid-writes:$PATH" invoke > "$work/noop.json"
        after=$(sha256sum "$device" | cut -d ' ' -f1)
        [[ $stable == "$after" && $before != "$stable" ]]
        jq -e '.prior_action=="verify-ready" and (.metadata_written_this_boot|not)' "$work/noop.json" >/dev/null
        cp "$work/completed.json" "$fixture/provision-result.json"
        cp "$work/noop.json" "$fixture/provision-noop.json"
        jq -M -n --arg hash "$stable" --argjson seed "$(jq -er .super_bytes "$fixture/seed.json")" --argjson fedora "$actual_fedora" \
            '{schema_version:1,owned_loop_only:true,seed_bytes:$seed,actual_super_bytes:8589934592,
              actual_fedora_root_readback_tested:$fedora,extra_fixture_files_in_actual_rescue:false,
              original_tools_used:true,real_ext4_growth_and_swap_initialization:true,
              rescue_file_preserved_without_relocation:true,active_holder_refused_before_write:true,
              alternate_node_holder_refused_before_write:true,writer_pinned_across_path_replacement:true,
              old_saved_image_signature_refused_before_write:true,
              restarted_after_growing_metadata:true,restarted_after_payload_initialization:true,
              torn_final_commit_completed_without_payload_mutation:true,
              ready_noop_whole_device_sha256:$hash,ready_noop_byte_unchanged:true,
              physical_ufs_tested:false,real_power_loss_tested:false,
              secure_boot_tested:false,encryption_tested:false,operating_system_booted:false}' > "$report"
        ;;
    *) printf 'Usage: %s prepare NEW_DIRECTORY | prepare-seed SUPER_SEED_DIRECTORY NEW_DIRECTORY | run OWNED_4K_LOOP FIXTURE_DIRECTORY NEW_REPORT\n' "${0##*/}" >&2; exit 2;;
esac
