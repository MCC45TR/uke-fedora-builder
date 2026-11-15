#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Host-only kernel fixture. Run accepts only its own exact regular-file loop.
set -Eeuo pipefail
trap 'printf "UKE_VERITY_MAP_TEST_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
case ${1:-} in
    prepare)
        [[ $# == 2 && ! -e $2 && ! -L $2 ]]
        fixture=$(realpath -m "$2")
        mkdir -m700 "$fixture"
        work=$(mktemp -d "$fixture/work.XXXXXXXX")
        trap 'find "$work" -depth -delete' EXIT
        mkdir "$work/files"
        printf 'Kernel-verified rescue file; no physical device.\n' > "$work/files/proof"
        cp "$work/files/proof" "$fixture/proof"
        truncate -s 16M "$work/seed.ext4"
        SOURCE_DATE_EPOCH=1794700800 mke2fs -q -F -t ext4 -b4096 -L FEDORA_RESCUE \
            -E lazy_itable_init=0,lazy_journal_init=0 -d "$work/files" "$work/seed.ext4"
        input=$(sha256sum "$work/seed.ext4" | cut -d ' ' -f1)
        bash "$repo/src/image/build-rescue-verity.sh" "$work/seed.ext4" "$input" \
            67108864 1794700800 1111111111111111111111111111111111111111111111111111111111111111 "$work/candidate"
        cp "$work/candidate/rescue-verity.json" "$fixture/recipe.json"
        data=$(jq -er .layout.data_bytes "$fixture/recipe.json")
        head -c "$data" "$work/candidate/rescue.verity" | sha256sum | cut -d ' ' -f1 > "$fixture/data-sha256"
        # One MiB outside each end of the emulated logical partition.
        truncate -s 69206016 "$fixture/carrier.raw"
        dd if="$work/candidate/rescue.verity" of="$fixture/carrier.raw" bs=1M seek=1 conv=notrunc,sparse status=none
        sha256sum "$fixture/carrier.raw" | cut -d ' ' -f1 > "$fixture/carrier-sha256"
        ;;
    run)
        [[ $# == 4 && $(id -u) == 0 && -b $2 && -d $3 && ! -e $4 && ! -L $4 ]]
        device=$(readlink -e "$2")
        fixture=$(realpath "$3")
        report=$(realpath -m "$4")
        [[ $device =~ ^/dev/loop[0-9]+$ && $(blockdev --getsize64 "$device") == 69206016 &&
           $(blockdev --getss "$device") == 4096 ]]
        [[ $(losetup -n -O BACK-INO "$device" | tr -d '[:space:]') == "$(stat -c %i "$fixture/carrier.raw")" &&
           $(losetup -n -O BACK-MAJ:MIN "$device" | tr -d '[:space:]') == "$(findmnt -nro MAJ:MIN --target "$fixture/carrier.raw")" ]]
        before=$(sha256sum "$device" | cut -d ' ' -f1)
        [[ $before == "$(cat "$fixture/carrier-sha256")" ]]
        jq -e '.layout.container_bytes==67108864 and .layout.format==1 and .layout.hash=="sha256" and
          .layout.data_block_size==4096 and .layout.hash_block_size==4096 and
          .layout.hash_offset_bytes==.layout.data_bytes and (.layout.superblock|not)' "$fixture/recipe.json" >/dev/null
        blocks=$(jq -er .layout.data_blocks "$fixture/recipe.json")
        hash_start=$(jq -er '.layout.hash_offset_bytes/4096' "$fixture/recipe.json")
        root=$(jq -er .root_hash "$fixture/recipe.json")
        salt=$(jq -er .salt "$fixture/recipe.json")
        [[ $root =~ ^[a-f0-9]{64}$ && $salt =~ ^[a-f0-9]{64}$ && $blocks =~ ^[1-9][0-9]*$ && $hash_start == "$blocks" ]]
        devno=$(lsblk -dnro MAJ:MIN "$device")
        tag=${devno/:/-}
        parent=uke-verity-fixture-data
        child=uke-verity-fixture-root
        parent_uuid=UKE-VERITY-FIXTURE-v1-$tag-data
        child_uuid=UKE-VERITY-FIXTURE-v1-$tag-root
        work=$(mktemp -d "$fixture/run.XXXXXXXX")
        cleanup() {
            local result=$? name actual expected
            trap - EXIT
            for name in "$child" "$parent"; do
                if [[ $name == "$child" ]]; then expected=$child_uuid; else expected=$parent_uuid; fi
                actual=$(dmsetup info -c --noheadings -o uuid "$name" 2>/dev/null | tr -d '[:space:]') || actual=''
                if [[ $actual == "$expected" ]]; then dmsetup --noudevsync remove --retry "$name" || result=1; fi
            done
            find "$work" -depth -delete
            exit "$result"
        }
        trap cleanup EXIT
        for name in "$child" "$parent"; do
            if dmsetup info "$name" >/dev/null 2>&1; then echo 'Fixture name occupied' >&2; exit 1; fi
        done
        close_maps() {
            dmsetup --noudevsync remove "$child"
            dmsetup --noudevsync remove "$parent"
        }
        open_maps() {
            local digest=$1 parent_devno
            dmsetup --noudevsync create --readonly --uuid "$parent_uuid" "$parent" \
                --table "0 131072 linear $devno 2048"
            dmsetup mknodes "$parent"
            parent_devno=$(lsblk -dnro MAJ:MIN "/dev/mapper/$parent")
            dmsetup --noudevsync create --readonly --uuid "$child_uuid" "$child" \
                --table "0 $((blocks*8)) verity 1 $parent_devno $parent_devno 4096 4096 $blocks $hash_start sha256 $digest $salt"
            dmsetup mknodes "$child"
            [[ $(blockdev --getro "/dev/mapper/$parent") == 1 && $(blockdev --getro "/dev/mapper/$child") == 1 ]]
            [[ $(blockdev --getsize64 "/dev/mapper/$child") == "$((blocks*4096))" ]]
            # Exactly the fixed verity arguments: no ignore, FEC, panic, restart,
            # zero-block or check-once option can mask an I/O failure here.
            [[ $(dmsetup table "$child" | awk '{print NF}') == 13 ]]
        }
        expect_bad_read() {
            if dd if="/dev/mapper/$child" of=/dev/null bs=4096 count=1 iflag=direct status=none > "$work/bad-read.log" 2>&1; then
                echo 'Corrupt rescue unexpectedly readable' >&2; exit 1
            fi
            grep -F 'Input/output error' "$work/bad-read.log" >/dev/null
            [[ $(dmsetup status "$child" | awk '{print $4}') == C ]]
        }
        open_maps "$root"
        [[ $(sha256sum "/dev/mapper/$child" | cut -d ' ' -f1) == "$(cat "$fixture/data-sha256")" ]]
        [[ $(dmsetup status "$child" | awk '{print $4}') == V ]]
        debugfs -R "dump /proof $work/proof" "/dev/mapper/$child" >/dev/null 2>&1
        cmp "$fixture/proof" "$work/proof"
        if dd if=/dev/zero of="/dev/mapper/$child" bs=4096 count=1 conv=notrunc status=none > "$work/write.log" 2>&1; then exit 1; fi
        dd if="/dev/mapper/$child" of="$work/past-end" bs=4096 skip="$blocks" count=1 iflag=direct status=none
        [[ ! -s $work/past-end && $(sha256sum "$device" | cut -d ' ' -f1) == "$before" ]]
        close_maps
        if [[ ${root:0:1} == 0 ]]; then wrong_root=1${root:1}; else wrong_root=0${root:1}; fi
        open_maps "$wrong_root"
        expect_bad_read
        close_maps
        # Remove both maps before each mutation, then create fresh devices so
        # cached successful verification cannot hide changed backing bytes.
        for block in 256 "$((256+hash_start))"; do
            dd if="$device" of="$work/original" bs=4096 skip="$block" count=1 iflag=direct status=none
            cp "$work/original" "$work/changed"
            if ((block == 256)); then byte=1024; else byte=0; fi
            value=$(od -An -tu1 -j "$byte" -N1 "$work/changed" | tr -d '[:space:]')
            printf -v octal '%03o' "$((value^1))"
            printf '%b' "\\$octal" | dd of="$work/changed" bs=1 seek="$byte" conv=notrunc status=none
            dd if="$work/changed" of="$device" bs=4096 seek="$block" count=1 oflag=direct conv=notrunc status=none
            open_maps "$root"
            expect_bad_read
            close_maps
            dd if="$work/original" of="$device" bs=4096 seek="$block" count=1 oflag=direct conv=notrunc status=none
            [[ $(sha256sum "$device" | cut -d ' ' -f1) == "$before" ]]
        done
        open_maps "$root"
        [[ $(sha256sum "/dev/mapper/$child" | cut -d ' ' -f1) == "$(cat "$fixture/data-sha256")" ]]
        close_maps
        jq -n --arg kernel "$(uname -r)" --arg backing "$before" \
          '{schema_version:1,owned_loop_only:true,host_kernel:$kernel,loop_logical_sector_size:4096,
            nested_readonly_linear_and_verity:true,complete_data_digest_matched:true,
            ext4_file_readback:true,write_refused:true,hash_tree_not_exposed_as_data:true,
            wrong_root_read_failed:true,data_corruption_read_failed:true,hash_corruption_read_failed:true,
            corruption_reported_by_kernel:true,fresh_maps_for_each_corruption:true,
            restored_backing_sha256:$backing,backing_restored:true,
            metadata_signature_verified:false,physical_ufs_tested:false,operating_system_booted:false,
            installable_archive_created:false}' > "$report"
        ;;
    *) echo 'Usage: rescue-verity-map.sh prepare NEW_DIRECTORY | run OWNED_LOOP FIXTURE NEW_REPORT' >&2; exit 2;;
esac
