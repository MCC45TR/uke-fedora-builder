#!/usr/bin/env bash
# Exercise the original Fedora fastboot ZIP parser against loopback-only TCP.
# Synthetic bytes only. No USB, tablet, root, compiler or installable OS image.
set -Eeuo pipefail
export LC_ALL=C
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
[[ $# -ge 1 && $# -le 2 && ! -e $1 && ! -L $1 ]]
padded_result=reject-before-mutation
normalized=false
if [[ $# == 2 ]]; then
    [[ $2 == --normalizes-partition-size ]]
    padded_result=success
    normalized=true
fi
report=$(realpath -m "$1")
for tool in fastboot socat zip jq lpmake; do command -v "$tool" >/dev/null; done
work=$(mktemp -d)
server=''
cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n $server ]]; then kill "$server" 2>/dev/null || :; wait "$server" 2>/dev/null || :; fi
    if ((status)); then
        for log in "${case_dir:-$work}/"{client,server}.log; do [[ ! -f $log ]] || tail -n 20 "$log" >&2; done
    fi
    find "$work" -depth -delete
    exit "$status"
}
trap cleanup EXIT
mkdir "$work/images"
cat > "$work/composition.json" <<'JSON'
{"kernel_release":"7.3.3-26-unstable","source_commit":"c7adc996350e3692b4492ab007cad63070dde6c2"}
JSON
cat > "$work/geometry.json" <<'JSON'
{"product":"uke","source":"synthetic-loopback-only","partitions":{"super":8589934592,"userdata":274877906944,"boot_a":100663296,"boot_b":100663296,"vendor_boot_a":100663296,"vendor_boot_b":100663296,"dtbo_a":25165824,"dtbo_b":25165824,"vbmeta_a":131072,"vbmeta_b":131072}}
JSON
bash "$root/src/image/plan-fastboot-update.sh" "$work/composition.json" "$work/geometry.json" "$work/plan" 141126
cp "$work/plan/"{android-info,fastboot-info}.txt "$work/images/"
# One common requirement file admits two synthetic capacities, never model names.
# shellcheck source=../src/image/fastboot-requirements.sh
# shellcheck disable=SC1091
source "$root/src/image/fastboot-requirements.sh"
jq '.partitions.super=11274289152 | .partitions.userdata=497535680512' "$work/geometry.json" > "$work/large.json"
fastboot_requirements "$work/geometry.json" "$work/large.json" > "$work/images/android-info.txt"
for image in userdata boot vendor_boot dtbo vbmeta; do
    printf 'Synthetic parser fixture, not a bootable image.\n' > "$work/images/$image.img"
    truncate -s4096 "$work/images/$image.img"
done
# Sparse 4GiB logical super, under1MiB stored. No expanded multi-GiB image.
lpmake --device-size 4294967296 --metadata-size 65536 --metadata-slots 3 \
    --group uke_seed:4293918720 --partition system_b:none:858783744:uke_seed \
    --partition system_a:none:3435134976:uke_seed --force-full-image --sparse \
    --output "$work/images/super.img"
[[ $(stat -c %s "$work/images/super.img") -lt 1048576 ]]
[[ $(od -An -v -N4 -tx1 "$work/images/super.img" | tr -d ' \n') == 3aff26ed ]]
read -r b0 b1 b2 b3 < <(od -An -v -j16 -N4 -tu1 "$work/images/super.img")
(((b0 + (b1 << 8) + (b2 << 16) + (b3 << 24)) * 4096 == 4294967296))
(cd "$work/images"; zip -q "$work/guarded.zip" android-info.txt fastboot-info.txt ./*.img)
cp "$work/guarded.zip" "$work/unguarded.zip"
printf 'require product=uke\n' > "$work/images/android-info.txt"
(cd "$work/images"; zip -q "$work/unguarded.zip" android-info.txt)
make_vars() {
    local partition bytes
    jq -n '{product:"uke","is-userspace":"no","slot-count":"2","current-slot":"a",
      "version-bootloader":"synthetic","version-baseband":"synthetic",serialno:"SYNTHETIC",
      "snapshot-update-status":"none","max-download-size":"0x00100000"}' > "$work/base.json"
    while read -r partition bytes; do
        printf -v hex '0x%016x' "$bytes"
        jq --arg partition "$partition" --arg size "$hex" \
            '. + {("partition-size:"+$partition):$size,("has-slot:"+$partition):"no",("is-logical:"+$partition):"no"}' \
            "$work/base.json" > "$work/next.json"
        mv "$work/next.json" "$work/base.json"
    done < <(jq -r '.partitions|to_entries[]|"\(.key) \(.value)"' "$work/geometry.json")
}
make_vars
run_case() {
    local name=$1 archive=$2 expected=$3 port status=0
    case_dir=$work/$name
    mkdir "$case_dir"
    # Select the mock write set per archive. A later two-payload test must not
    # change the peer's allowed list for a subsequent complete-cohort case.
    case $archive in
        "$work/test-profile.zip") printf '["boot_b","userdata"]\n' > "$case_dir/allowed.json";;
        "$work/guarded.zip"|"$work/unguarded.zip") jq '[.payloads[].partition]' "$root/configs/images/fastboot-update-uke.json" > "$case_dir/allowed.json";;
        *) return 1;;
    esac
    cat > "$case_dir/vars.json"
    : > "$case_dir/commands.txt"
    # socat alone listens, only on127.0.0.1. An occupied port is retried without
    # ever allowing the fastboot client to attach to an unrelated listener.
    for _ in {1..10}; do
        port=$((30000 + RANDOM % 20000))
        socat -T8 "TCP4-LISTEN:$port,bind=127.0.0.1,nodelay" \
            "EXEC:bash $root/tests/fastboot-tcp-peer.sh $case_dir" > "$case_dir/server.log" 2>&1 &
        server=$!
        sleep 0.1
        if kill -0 "$server" 2>/dev/null; then break; fi
        wait "$server" || :
        server=''
    done
    [[ -n $server ]]
    timeout --kill-after=2s 15s fastboot -s "tcp:127.0.0.1:$port" update "$archive" > "$case_dir/client.log" 2>&1 || status=$?
    kill "$server" 2>/dev/null || :
    wait "$server" 2>/dev/null || :
    server=''
    if [[ $expected == success ]]; then
        [[ $status == 0 ]]
        awk '/^flash:/ {sub(/^flash:/, ""); print}' "$case_dir/commands.txt" > "$case_dir/actual.txt"
        jq -r '.[]' "$case_dir/allowed.json" > "$case_dir/expected.txt"
        cmp "$case_dir/actual.txt" "$case_dir/expected.txt"
        [[ $(grep -c '^reboot$' "$case_dir/commands.txt") == 1 ]]
        [[ $(grep -c '^set_active:' "$case_dir/commands.txt") == 1 ]]
    else
        [[ $status != 0 && $status != 124 && $status != 137 ]]
        if [[ $expected == reject-before-mutation ]]; then
            if grep -Ev '^getvar:' "$case_dir/commands.txt"; then return 1; fi
            grep -q 'requirements not met' "$case_dir/client.log"
        else
            [[ $(cat "$case_dir/too-large.txt") == super ]]
            grep -q '^download:' "$case_dir/commands.txt"
        fi
    fi
    if grep -E '^(erase:|format:|resize-logical-partition:|update-super:|reboot-fastboot|flashing |oem )' "$case_dir/commands.txt"; then return 1; fi
}
run_case slot-a "$work/guarded.zip" success < "$work/base.json"
run_case slot-b "$work/guarded.zip" success < <(jq '."current-slot"="b"' "$work/base.json")
run_case large "$work/guarded.zip" success < <(jq '."partition-size:super"="0x00000002A0000000" |
    ."partition-size:userdata"="0x00000073D7700000"' "$work/base.json")
for partition in super userdata boot_a boot_b vendor_boot_a vendor_boot_b dtbo_a dtbo_b vbmeta_a vbmeta_b; do
    run_case "wrong-$partition" "$work/guarded.zip" reject-before-mutation < <(
        jq --arg key "partition-size:$partition" '.[$key]="0x00100000"' "$work/base.json")
done
run_case foreign "$work/guarded.zip" reject-before-mutation < <(jq '.product="foreign"' "$work/base.json")
run_case fastbootd "$work/guarded.zip" reject-before-mutation < <(jq '."is-userspace"="yes"' "$work/base.json")
run_case slots "$work/guarded.zip" reject-before-mutation < <(jq '."slot-count"="1"' "$work/base.json")
run_case missing "$work/guarded.zip" reject-before-mutation < <(jq 'del(."partition-size:dtbo_b")' "$work/base.json")
# Demonstrate why ZIP/sparse stored size is insufficient: original fastboot
# reaches download/flash without the whole-package android-info size checks.
run_case unguarded "$work/unguarded.zip" reject-at-flash < <(jq '."partition-size:super"="0x00100000"' "$work/base.json")
# The initial installation test has a distinct, strictly smaller write set.
# shellcheck source=../src/image/test-fastboot-profile.sh
# shellcheck disable=SC1091
source "$root/src/image/test-fastboot-profile.sh"
test_fastboot_requirements "$work/geometry.json" > "$work/images/android-info.txt"
test_fastboot_tasks > "$work/images/fastboot-info.txt"
(cd "$work/images"; zip -q "$work/test-profile.zip" android-info.txt fastboot-info.txt boot.img userdata.img)
run_case initial-test-b "$work/test-profile.zip" success < <(jq '."current-slot"="b"' "$work/base.json")
grep -Fxq 'set_active:b' "$work/initial-test-b/commands.txt"
run_case initial-test-a "$work/test-profile.zip" reject-before-mutation < "$work/base.json"
run_case initial-test-wrong-size "$work/test-profile.zip" reject-before-mutation < <(
    jq '."current-slot"="b" | ."partition-size:userdata"="0x00100000"' "$work/base.json")
# Uke ABL returns a leading space in numeric getvar responses. Upstream's
# requirement checker trims options but not the response, unlike get_uint_var.
# The unmodified client must demonstrate this refusal; the isolated host fix
# must accept the same exact capacities while retaining every negative gate.
run_case padded-capacities "$work/guarded.zip" "$padded_result" < <(
    jq 'with_entries(if (.key|startswith("partition-size:")) then .value=" "+.value else . end)' "$work/base.json")
run_case initial-test-b-padded "$work/test-profile.zip" "$padded_result" < <(
    jq '."current-slot"="b" | with_entries(if (.key|startswith("partition-size:")) then .value=" "+.value else . end)' "$work/base.json")
for value in ' 0x00100000' ' 0x6000000junk' ' '; do
    run_case "padded-invalid-${value//[^a-zA-Z0-9]/_}" "$work/test-profile.zip" reject-before-mutation < <(
        jq --arg value "$value" '."current-slot"="b" | ."partition-size:boot_b"=$value' "$work/base.json")
done
jq -n --arg version "$(fastboot --version | head -n1)" --argjson normalized "$normalized" \
    '{schema_version:1,original_fastboot:$version,loopback_only:true,usb_used:false,
      synthetic_nonbootable_payloads:true,explicit_ten_partition_order_verified:true,
      both_initial_active_slots_tested:true,foreign_or_missing_geometry_refused_before_mutation:true,
      same_archive_two_synthetic_capacities_tested:true,
      every_destination_size_checked_before_mutation:true,fastbootd_and_non_ab_refused:true,
      unguarded_sparse_extent_mismatch_reaches_flash:true,physical_fastboot_tested:false,
      initial_test_profile_exactly_boot_b_userdata:true,initial_test_other_slot_refused_before_mutation:true,
      initial_test_current_slot_b_preserved:true,
      partition_size_response_whitespace_normalized:$normalized,
      padded_wrong_capacity_and_malformed_values_refused:true,
      operating_system_booted:false,secure_boot_tested:false}' > "$report"
printf 'Original fastboot ZIP parser, explicit slots and pre-mutation capacity requirements passed on loopback only.\n'
