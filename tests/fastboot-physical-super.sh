#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Synthetic kernel view over the same owned growth loop; no physical hardware.
set -Eeuo pipefail
trap 'printf "UKE_PHYSICAL_FIXTURE_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
[[ $# == 4 && $(id -u) == 0 && -b $1 && -d $2 && -f $3 && ! -L $3 && ! -e $4 && ! -L $4 ]]
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
device=$(readlink -e "$1")
fixture=$(realpath "$2")
report=$(realpath -m "$4")
[[ $device =~ ^/dev/loop[0-9]+$ && $(blockdev --getsize64 "$device") == 8589934592 && $(blockdev --getss "$device") == 4096 ]]
[[ $(losetup -n -O BACK-INO "$device" | tr -d '[:space:]') == "$(stat -c %i "$fixture/super.raw")" ]]
[[ $(losetup -n -O BACK-MAJ:MIN "$device" | tr -d '[:space:]') == "$(findmnt -nro MAJ:MIN --target "$fixture/super.raw")" ]]
before=$(jq -er '.ready_noop_whole_device_sha256 | select(test("^[a-f0-9]{64}$"))' "$3")
jq -e '.owned_loop_only and .actual_super_bytes==8589934592 and .ready_noop_byte_unchanged' "$3" >/dev/null
devno=$(lsblk -dnro MAJ:MIN "$device")
work=$(mktemp -d "$fixture/physical.XXXXXXXX")
cleanup() {
    local status=$?
    trap - EXIT
    if ((status)); then
        for file in "$work/result.json" "$work/result.log"; do [[ ! -f $file ]] || tail -n16 "$file" >&2; done
    fi
    find "$work" -depth -delete
    exit "$status"
}
trap cleanup EXIT
view=$work/view
controller=/sys/devices/platform/soc/1d84000.ufshc
reset_view() {
    local name=${1:-sda31} disk=${1:-sda31}
    disk=${disk%%[0-9]*}
    [[ ! -e $view ]] || find "$view" -depth -delete
    node=$controller/host0/target0:0:0/0:0:0:0/block/$disk/$name
    mkdir -p "$view$node" "$view${node%/*}/queue" "$view/sys/class/block" "$view/sys/dev/block" \
        "$view/sys/bus/platform/drivers/ufshcd-qcom" "$view/sys/firmware/devicetree/base" "$view/dev/disk/by-partlabel"
    ln -s "$node" "$view/sys/class/block/$name"
    ln -s "$node" "$view/sys/dev/block/$devno"
    ln -s /sys/bus/platform/drivers/ufshcd-qcom "$view$controller/driver"
    printf 'xiaomi,uke\0qcom,sm7675\0qcom,cliffs\0' > "$view/sys/firmware/devicetree/base/compatible"
    printf '31\n' > "$view$node/partition"
    printf '%s\n' "$devno" > "$view$node/dev"
    printf '16777216\n' > "$view$node/size"
    printf '4096\n' > "$view${node%/*}/queue/logical_block_size"
    printf 'MAJOR=%s\nMINOR=%s\nDEVNAME=%s\nDEVTYPE=partition\nPARTN=31\nPARTNAME=super\n' \
        "${devno%:*}" "${devno#*:}" "$name" > "$view$node/uevent"
    mknod "$view/dev/$name" b "${devno%:*}" "${devno#*:}"
    ln -s "../../$name" "$view/dev/disk/by-partlabel/super"
    mknod -m666 "$view/dev/null" c 1 3
    mknod -m666 "$view/dev/zero" c 1 5
}
cat > "$work/run-in-view.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
trap 'printf "UKE_NAMESPACE_SETUP_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
view=$1 selector=$2 mode=$3
# All mounts stay in this child namespace. No pivot_root or custom seccomp.
mount --make-rprivate /
mount --bind "$view/sys" /sys
mount -o remount,bind,ro,nosuid,nodev /sys
mount --bind "$view/dev" /dev
# Only the owned loop and null/zero exist here. Keep device access for it.
mount -o remount,bind,ro,nosuid,dev /dev
mount -t tmpfs -o size=64M,nosuid,nodev,mode=1777 uke-selection-test /tmp
mount -t tmpfs -o size=16M,nosuid,nodev,mode=0755 uke-selection-run /run
# Read variables only in the post-setpriv child.
# shellcheck disable=SC2016
exec env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C \
    setpriv --bounding-set=-all --inh-caps=-all --ambient-caps=-all --no-new-privs \
    /usr/bin/bash -Eeuo pipefail -c '
        count=0 nnp=0
        while read -r key value _; do
            case $key in CapInh:|CapPrm:|CapEff:|CapBnd:|CapAmb:)
                [[ $value == 0000000000000000 ]]
                count=$((count+1));;
            NoNewPrivs:) [[ $value == 1 ]]; nnp=1;;
            esac
        done < "/proc/$$/status"
        [[ $count == 5 && $nnp == 1 ]]
        exec /usr/bin/bash "$1" "$2"
    ' capability-free-selector "$selector" "$mode"
SH
run_selector() {
    unshare --mount --fork /usr/bin/bash "$work/run-in-view.sh" "$view" \
        "$repo/src/image/select-uke-super.sh" "$1" > "$work/result.json" 2> "$work/result.log"
}
reject() {
    if run_selector --inspect-ready; then echo 'Unsafe physical selection admitted' >&2; exit 1; fi
    [[ ! -s $work/result.json ]]
    grep -F UKE_PHYSICAL_SUPER_REJECTED "$work/result.log" >/dev/null
}
sync "$fixture/super.raw"
fadvise --advice dontneed "$fixture/super.raw"
reset_view
run_selector --identity-only
jq -e '.physical_ufs_selection_verified and (.linux_layout_verified|not) and
    .physical_selection.capacity_bytes==8589934592 and (.partition_write_executed|not)' "$work/result.json" >/dev/null
run_selector --inspect-ready
jq -e '.physical_ufs_selection_verified and .linux_layout_verified and .three_slot_topology_verified and
    .layout.phase=="ready" and (.metadata_authenticity_verified|not) and (.operating_system_verified|not)' "$work/result.json" >/dev/null
reset_view sde17
# Partition number comes from sysfs, not the example name or measured sda31.
printf '17\n' > "$view$node/partition"
sed -i 's/PARTN=31/PARTN=17/' "$view$node/uevent"
run_selector --inspect-ready
jq -e '.physical_ufs_selection_verified and .linux_layout_verified' "$work/result.json" >/dev/null
refused=0
for fault in board soc unterminated duplicate foreign-controller driver virtual whole-disk partition-number \
    device-name duplicate-event missing-event sysfs-dev sysfs-link opened-dev label missing-label capacity sector-size; do
    reset_view
    case $fault in
        board) printf 'xiaomi,other\0qcom,sm7675\0' > "$view/sys/firmware/devicetree/base/compatible";;
        soc) printf 'xiaomi,uke\0qcom,sm8650\0' > "$view/sys/firmware/devicetree/base/compatible";;
        unterminated) printf 'xiaomi,uke\0qcom,sm7675' > "$view/sys/firmware/devicetree/base/compatible";;
        duplicate)
            mkdir -p "$view/sys/devices/virtual/block/dm-1"
            printf 'PARTNAME=super\n' > "$view/sys/devices/virtual/block/dm-1/uevent"
            ln -s /sys/devices/virtual/block/dm-1 "$view/sys/class/block/dm-1";;
        foreign-controller|virtual)
            destination=/sys/devices/platform/other/block/sda/sda31
            [[ $fault != virtual ]] || destination=/sys/devices/virtual/block/dm-1
            mkdir -p "$view$destination"
            cp "$view$node/"{uevent,partition} "$view$destination/"
            ln -sfn "$destination" "$view/sys/class/block/sda31";;
        driver)
            mkdir "$view/sys/bus/platform/drivers/other"
            ln -sfn /sys/bus/platform/drivers/other "$view$controller/driver";;
        whole-disk) sed -i 's/DEVTYPE=partition/DEVTYPE=disk/' "$view$node/uevent";;
        partition-number) printf '32\n' > "$view$node/partition";;
        device-name) sed -i 's/DEVNAME=sda31/DEVNAME=sda32/' "$view$node/uevent";;
        duplicate-event) printf 'PARTN=31\n' >> "$view$node/uevent";;
        missing-event) sed -i '/DEVTYPE=/d' "$view$node/uevent";;
        sysfs-dev) printf '8:255\n' > "$view$node/dev";;
        sysfs-link) ln -sfn "$controller" "$view/sys/dev/block/$devno";;
        opened-dev)
            printf '8:255\n' > "$view$node/dev"
            sed -i -e 's/^MAJOR=.*/MAJOR=8/' -e 's/^MINOR=.*/MINOR=255/' "$view$node/uevent"
            ln -s "$node" "$view/sys/dev/block/8:255";;
        label) ln -sfn ../../null "$view/dev/disk/by-partlabel/super";;
        missing-label) unlink "$view/dev/disk/by-partlabel/super";;
        capacity) printf '8388608\n' > "$view$node/size";;
        sector-size) printf '512\n' > "$view${node%/*}/queue/logical_block_size";;
    esac
    reject
    refused=$((refused+1))
done
after=$(sha256sum "$device" | cut -d ' ' -f1)
[[ $before == "$after" && $refused == 19 ]]
jq -M -n --arg hash "$after" --argjson refused "$refused" \
    '{schema_version:1,owned_loop_only:true,synthetic_sysfs_and_device_tree:true,
      identity_only_and_three_slot_ready_inspection:true,two_device_names_and_partition_numbers:true,
      child_all_capability_sets_empty:true,docker_syscall_filter_relaxed:false,
      unsafe_selection_cases_refused:$refused,whole_backing_sha256:$hash,whole_backing_unchanged:true,
      physical_ufs_tested:false,metadata_authenticity_tested:false,operating_system_booted:false,
      encryption_or_resume_tested:false}' > "$report"
