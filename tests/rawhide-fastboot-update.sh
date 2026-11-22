#!/usr/bin/env bash
# Exercise stock fastboot update over loopback with non-bootable test images.
set -Eeuo pipefail
export LC_ALL=C
metadata=
vendor_boot=false
if [[ ${1:-} == --vendor-boot ]]; then vendor_boot=true; shift; fi
(( $# <= 1 ))
if (( $# )); then
    [[ $# == 1 && -f $1 && $(stat -c %s "$1") -le 69632 ]]
    metadata=$(realpath "$1")
fi
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
server=''
cleanup() {
    local status=$?
    if [[ -n $server ]]; then kill "$server" 2>/dev/null || :; wait "$server" 2>/dev/null || :; fi
    if ((status != 0)); then
        for log in "$work/"*/*.log; do [[ ! -f $log ]] || tail -n 20 -- "$log" >&2; done
    fi
    find "$work" -depth -delete
}
trap cleanup EXIT
mkdir "$work/images"
(
    cd "$work/images"
    cp "$repo/configs/images/rawhide-fastboot/"*.txt .
    truncate -s 4096 boot.img dtbo.img rescue-boot.img
    if [[ $vendor_boot == true ]]; then
        truncate -s 4096 vendor_boot.img
        sed -i '/^flash dtbo/i flash vendor_boot vendor_boot.img' fastboot-info.txt
        cat >> android-info.txt <<'RULES'
require has-slot:vendor_boot=yes
require partition-size:vendor_boot_a=0x6000000|0x06000000|0x0000000006000000
require partition-size:vendor_boot_b=0x6000000|0x06000000|0x0000000006000000
RULES
    fi
    # Two valid Android sparse chunks with a 4096-byte block size. The FILL
    # chunk carries one nonzero block, then DONT_CARE covers the rest.
    sparse_fixture() {
        printf '\x3a\xff\x26\xed\x01\x00\x00\x00\x1c\x00\x0c\x00\x00\x10\x00\x00'
        printf '%b' "$1"
        printf '\x02\x00\x00\x00\x00\x00\x00\x00'
        printf '\xc2\xca\x00\x00\x01\x00\x00\x00\x10\x00\x00\x00\x78\x56\x34\x12'
        printf '\xc3\xca\x00\x00%b\x0c\x00\x00\x00' "$2"
    }
    sparse_fixture '\x00\x00\x10\x00' '\xff\xff\x0f\x00' > super.img
    sparse_fixture '\x00\x00\x20\x00' '\xff\xff\x1f\x00' > userdata.img
    if [[ -n $metadata ]]; then cp "$metadata" super_empty.img; fi
    zip -q "$work/fedora-fixture.zip" ./*
)
jq -n '{
    product:"uke", "is-userspace":"no", "current-slot":"a", "slot-count":"2",
    "snapshot-update-status":"none", "version-bootloader":"fixture", "version-baseband":"fixture",
    serialno:"FIXTURE", "max-download-size":"0x00100000",
    "has-slot:vendor_boot":"yes", "partition-size:vendor_boot_a":"0x06000000", "partition-size:vendor_boot_b":"0x06000000",
    "has-slot:boot":"yes", "has-slot:dtbo":"yes", "has-slot:super":"no", "has-slot:userdata":"no",
    "partition-size:boot_a":" 0x06000000", "partition-size:boot_b":" 0x06000000",
    "partition-size:dtbo_a":" 0x01800000", "partition-size:dtbo_b":" 0x01800000",
    "partition-size:super":" 0x00000002A0000000", "partition-size:userdata":" 0x00000073D7700000"
}' > "$work/vars.json"

run_case() {
    local name=$1 slot=$2 condition=$3 port status=0
    local case_dir=$work/$name dtbo
    mkdir "$case_dir"
    cat > "$case_dir/vars.json"
    dtbo=dtbo_$slot
    if [[ $(jq -er '."has-slot:dtbo"' "$case_dir/vars.json") == no ]]; then dtbo=dtbo; fi
    jq -n --arg slot "$slot" --arg dtbo "$dtbo" --argjson vendor "$vendor_boot" '
        ["super","userdata"]+(if $vendor then ["vendor_boot_"+$slot] else [] end)+[$dtbo,"boot_"+$slot]'  > "$case_dir/allowed.json"
    : > "$case_dir/commands.txt"
    for _ in {1..10}; do
        port=$((30000 + RANDOM % 20000))
        socat -T8 "TCP4-LISTEN:$port,bind=127.0.0.1,nodelay" \
            "EXEC:bash $repo/tests/fastboot-tcp-peer.sh $case_dir" > "$case_dir/server.log" 2>&1 &
        server=$!
        sleep 0.1
        if kill -0 "$server" 2>/dev/null; then break; fi
        wait "$server" || :
        server=''
    done
    [[ -n $server ]]
    timeout --kill-after=2s 20s fastboot -s "tcp:127.0.0.1:$port" update "$work/fedora-fixture.zip" > "$case_dir/client.log" 2>&1 || status=$?
    kill "$server" 2>/dev/null || :
    wait "$server" 2>/dev/null || :
    server=''
    case $condition in
        accept)
            [[ $status == 0 ]]
            {
                printf 'super 4294967296\nuserdata 8589934592\n'
                if [[ $vendor_boot == true ]]; then printf 'vendor_boot_%s 4096\n' "$slot"; fi
                printf '%s 4096\nboot_%s 4096\n' "$dtbo" "$slot"
            } | cmp - "$case_dir/accepted.txt"
            grep -Ev '^(getvar:|download:)' "$case_dir/commands.txt" > "$case_dir/mutations.txt"
            {
                printf 'set_active:%s\nflash:super\nflash:userdata\n' "$slot"
                if [[ $vendor_boot == true ]]; then printf 'flash:vendor_boot_%s\n' "$slot"; fi
                printf 'flash:%s\nflash:boot_%s\nreboot\n' "$dtbo" "$slot"
            } | cmp - "$case_dir/mutations.txt"
            if [[ -n $metadata ]]; then
                grep -Fq 'extracting super_empty.img' "$case_dir/client.log"
                if grep -Fq "archive does not contain 'super_empty.img'" "$case_dir/client.log"; then return 1; fi
            fi;;
        reject)
            [[ $status != 0 && $status != 124 && $status != 137 ]]
            grep -Fq 'requirements not met' "$case_dir/client.log"
            if grep -Ev '^getvar:' "$case_dir/commands.txt"; then return 1; fi;;
        undersized)
            [[ $status != 0 && $status != 124 && $status != 137 ]]
            [[ $(cat "$case_dir/too-large.txt") == super && ! -e $case_dir/accepted.txt ]]
            if grep -Eq '^flash:(userdata|boot|dtbo)|^reboot$' "$case_dir/commands.txt"; then return 1; fi;;
    esac
}
run_case poco-512 a accept < "$work/vars.json"
run_case pad-256 b accept < <(jq '."current-slot"="b" | ."partition-size:super"=" 0x220000000" |
    ."partition-size:userdata"=" 0x37D7700000"' "$work/vars.json")
# Pad 7 128 GB reported userdata size, with a simulated minimum-size super.
run_case pad-128-minimum b accept < <(jq '."current-slot"="b" | ."partition-size:super"=" 0x100000000" |
    ."partition-size:userdata"=" 0x1A767FB000"' "$work/vars.json")
# The observed bootloader on slot B reports DTBO through its unqualified alias.
run_case slot-b-dtbo-alias b accept < <(jq '."current-slot"="b" | ."has-slot:dtbo"="no" |
    ."partition-size:dtbo"=."partition-size:dtbo_b"' "$work/vars.json")
run_case foreign a reject < <(jq '.product="foreign"' "$work/vars.json")
run_case fastbootd a reject < <(jq '."is-userspace"="yes"' "$work/vars.json")
run_case snapshot a reject < <(jq '."snapshot-update-status"="merging"' "$work/vars.json")
run_case single-slot a reject < <(jq '."slot-count"="1"' "$work/vars.json")
run_case too-small a undersized < <(jq '."partition-size:super"=" 0x20000000"' "$work/vars.json")
if [[ $vendor_boot == true ]]; then
    run_case vendor-boot-missing b reject < <(jq '."has-slot:vendor_boot"="no"' "$work/vars.json")
    run_case vendor-boot-too-small b reject < <(jq '."partition-size:vendor_boot_b"="0x05000000"' "$work/vars.json")
fi
printf 'Stock fastboot update passed active-slot, 128/256/512 GB geometry, and refusal fixtures.\n'
