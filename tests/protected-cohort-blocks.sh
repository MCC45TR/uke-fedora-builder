#!/usr/bin/bash
# SPDX-License-Identifier: MIT
# Run only from the signed diagnostic RPM. No physical device is accepted.
set -Eeuo pipefail
trap 'printf "UKE_COHORT_BLOCK_FIXTURE_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
[[ $# == 0 && $(id -u) == 0 && $(uname -m) == aarch64 ]]
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
tool=$here/cohort-content-inspect
physical_tool=$here/cohort-physical-inspect
fixture=/usr/share/uke-protected-cohort-source-check/fixtures
[[ -x $tool && -x $physical_tool && -d $fixture ]]
for command in jq losetup blockdev findmnt fadvise timeout sha256sum; do command -v "$command" >/dev/null; done
(cd "$fixture"; sha256sum -c SHA256SUMS) >/dev/null
jq -e '.schema_version==1 and .scope=="disposable-copr-fixture" and
 (.arguments|length)==14 and all(.arguments[];type=="string")' "$fixture/context.json" >/dev/null
mapfile -t context < <(jq -r '.arguments[]' "$fixture/context.json")
[[ ${context[8]} == 100663296 && ${context[10]} == 100663296 && ${context[12]} == 25165824 ]]
# Only about 100KiB is allocated. Keep a 1GiB reserve even though apparent
# loop capacity is 216.125MiB. No full partition image is copied or backed up.
available=$(df --output=avail -k /var/tmp | tail -n1)
inodes=$(df --output=iavail /var/tmp | tail -n1)
available=${available//[[:space:]]/} inodes=${inodes//[[:space:]]/}
[[ $available =~ ^[0-9]+$ && $inodes =~ ^[0-9]+$ ]]
(( available >= 1048576 && inodes >= 1024 ))
work=$(mktemp -d /var/tmp/uke-cohort-blocks.XXXXXXXX)
names=(boot vendor_boot dtbo vbmeta)
capacities=(100663296 100663296 25165824 131072)
loops=('' '' '' '')
assert_owned() {
    local i=$1 inode backing loop_read_only sector
    [[ ${loops[i]} =~ ^/dev/loop[0-9]+$ && -b ${loops[i]} && -f $work/${names[i]}.raw ]] || return 1
    read -r inode backing loop_read_only sector < <(losetup -n -O BACK-INO,BACK-MAJ:MIN,RO,LOG-SEC "${loops[i]}") || return 1
    [[ $inode == "$(stat -c %i "$work/${names[i]}.raw")" && $loop_read_only == 1 &&
       $backing == "$(findmnt -nro MAJ:MIN --target "$work/${names[i]}.raw")" &&
       ( $sector == 4096 || $sector == 512 ) ]]
}
detach() {
    local i=$1
    [[ -n ${loops[i]} ]] || return 0
    assert_owned "$i" || return 1
    losetup -d -- "${loops[i]}" || return 1
    [[ ! -e /sys/class/block/${loops[i]##*/}/loop/backing_file ]] || return 1
    loops[i]=''
}
cleanup() {
    local status=$? safe=1 i
    trap - EXIT
    exec 3<&- 4<&- 5<&- 6<&-
    for i in 0 1 2 3; do
        if [[ -n ${loops[i]} ]]; then
            if ! (set -Eeuo pipefail; detach "$i"); then safe=0; status=1; fi
        fi
    done
    if ((safe)); then find "$work" -depth -delete;
    else printf 'Owned-loop cleanup refused; preserve %s for inspection.\n' "$work" >&2; fi
    exit "$status"
}
trap cleanup EXIT
attach() {
    local i=$1 sector=${2:-4096}
    [[ -z ${loops[i]} ]] || return 1
    loops[i]=$(losetup --find --show --read-only --sector-size "$sector" "$work/${names[i]}.raw") || return 1
    assert_owned "$i" || return 1
    [[ $(blockdev --getsize64 "${loops[i]}") == "$(stat -c %s "$work/${names[i]}.raw")" &&
       $(blockdev --getss "${loops[i]}") == "$sector" && $(blockdev --getro "${loops[i]}") == 1 ]]
}
for i in 0 1 2 3; do
    cp --sparse=always "$fixture/${names[i]}.img" "$work/${names[i]}.raw"
    truncate -s "${capacities[i]}" "$work/${names[i]}.raw"
done
allocated=$(du -B1 -c "$work/"*.raw | tail -n1)
allocated=${allocated%%[[:space:]]*}
[[ $allocated =~ ^[0-9]+$ ]] && (( allocated < 1048576 ))
sha256sum "$work/"*.raw > "$work/before.sha256"
for i in 0 1 2 3; do sync "$work/${names[i]}.raw"; fadvise --advice dontneed "$work/${names[i]}.raw"; attach "$i"; done
slot=a inputs=(3 4 5)
open_inputs() { exec 3<"${loops[0]}" 4<"${loops[1]}" 5<"${loops[2]}"; }
close_inputs() { exec 3<&- 4<&- 5<&-; }
invoke() { timeout 8s "$tool" "$fixture/vbmeta.img" "${context[@]}" "$slot" "${inputs[@]}"; }
positive() {
    open_inputs
    invoke > "$work/positive-$slot.json"
    close_inputs
    jq -e '.fd_contents_verified and .block_input_count==3 and .verified_bytes==81920 and
      .kernel_image_slice_matched and .caller_positions_unchanged and .owned_handles_released and
      (.physical_identity_verified|not) and (.selected_slot_bound|not) and (.role_admitted|not)' \
        "$work/positive-$slot.json" >/dev/null
}
refused=0
reject_open() {
    local status=0
    invoke > "$work/refused.json" 2> "$work/refused.log" || status=$?
    [[ $status == 1 && ! -s $work/refused.json && $(tail -n1 "$work/refused.log") == UKE_COHORT_CONTENT_REJECTED ]]
    ((refused+=1))
}
reject() { open_inputs; reject_open; close_inputs; }
positive
slot=b; positive; slot=a
# Exact ioctl sector/capacity checks, independently of regular-file tests.
detach 0; attach 0 512; reject; detach 0; attach 0
for delta in 4096 -4096; do
    detach 0
    truncate -s "$((capacities[0]+delta))" "$work/boot.raw"
    attach 0; reject; detach 0
done
truncate -s "${capacities[0]}" "$work/boot.raw"; attach 0
open_inputs; exec 4<"${loops[0]}"; reject_open; close_inputs
inputs=(3 99 5); reject; inputs=(3 4 5)
flip() {
    local value octal
    value=$(od -An -tu1 -j "$2" -N1 "$1" | tr -d '[:space:]')
    printf -v octal '%03o' "$((value^1))"
    printf '%b' "\\$octal" | dd of="$1" bs=1 seek="$2" conv=notrunc status=none
}
offsets=(5000 10 10)
for i in 0 1 2; do
    detach "$i"
    flip "$work/${names[i]}.raw" "${offsets[i]}"
    attach "$i"; reject; detach "$i"
    flip "$work/${names[i]}.raw" "${offsets[i]}"
    attach "$i"
done
positive
[[ $refused == 8 ]]
# Read authenticated metadata from its own 128KiB loop through a retained FD.
fd_open() { open_inputs; exec 6<"${loops[3]}"; }
fd_close() { close_inputs; exec 6<&-; }
fd_invoke() { timeout 8s "$physical_tool" --fixture-vbmeta-fd 6 131072 "${context[@]}" a 3 4 5; }
fd_positive() {
    fd_open; fd_invoke > "$work/fd-positive.json"; fd_close
    jq -e '.metadata_verified and .metadata_block_input and .metadata_prefix_bytes==65536 and
      .boot_contents_verified and .boot_block_input_count==3 and .verified_boot_bytes==81920 and
      .caller_positions_unchanged and .owned_handles_released and (.physical_ufs_topology_verified|not) and
      (.selected_slot_bound|not) and (.role_admitted|not)' "$work/fd-positive.json" >/dev/null
}
fd_refused=0
fd_reject() {
    local status=0
    fd_open
    fd_invoke > "$work/fd-refused.json" 2> "$work/fd-refused.log" || status=$?
    fd_close
    [[ $status == 1 && ! -s $work/fd-refused.json && $(tail -n1 "$work/fd-refused.log") == UKE_PHYSICAL_COHORT_REJECTED ]]
    ((fd_refused+=1))
}
fd_positive
detach 3; attach 3 512; fd_reject; detach 3; attach 3
for delta in 4096 -4096; do
    detach 3; truncate -s "$((capacities[3]+delta))" "$work/vbmeta.raw"
    attach 3; fd_reject; detach 3
done
truncate -s "${capacities[3]}" "$work/vbmeta.raw"; attach 3
for offset in 0 65535; do
    detach 3; flip "$work/vbmeta.raw" "$offset"
    attach 3; fd_reject; detach 3
    flip "$work/vbmeta.raw" "$offset"; attach 3
done
fd_positive
for i in 0 1 2 3; do detach "$i"; done
sha256sum -c "$work/before.sha256" > "$work/unchanged.log"
for i in 0 1 2 3; do sync "$work/${names[i]}.raw"; fadvise --advice dontneed "$work/${names[i]}.raw"; done
[[ $fd_refused == 5 ]]
jq -n --arg kernel "$(uname -r)" --argjson refused "$refused" --argjson allocated "$allocated" \
 --argjson fd_refused "$fd_refused" --slurpfile positive "$work/positive-a.json" --slurpfile fd "$work/fd-positive.json" \
 '{schema_version:1,native_architecture:"aarch64",running_kernel:$kernel,
   owned_loop_devices_only:true,read_only_loop_devices:true,logical_sector_bytes:4096,
   block_device_branch_tested:true,block_input_count:3,refused_cases:$refused,
   initial_allocated_backing_bytes:$allocated,backing_byte_unchanged:true,loops_detached:true,
   context_and_keys_are_disposable_fixtures:true,positive_result:$positive[0],
   vbmeta_fd_snapshot_block_tested:true,vbmeta_fd_refused_cases:$fd_refused,vbmeta_fd_result:$fd[0],
   physical_ufs_selection_verified:false,actual_boot_partitions_read:false,selected_slot_bound:false,
   booted_kernel_verified:false,role_admitted:false,operating_system_booted:false,
   key_release_or_resume_executed:false}'
