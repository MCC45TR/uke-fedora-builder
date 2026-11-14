#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Native target probe: read one crypto data unit through a read-only mapping.
# No filesystem creation, partition write, key persistence or conversion.
set +x
set -Eeuo pipefail
export LC_ALL=C
if [[ $# != 2 || $1 != --device ]]; then
    printf 'Usage: %s --device BLOCK_DEVICE\n' "${0##*/}" >&2
    exit 2
fi
[[ $(id -u) == 0 ]] || { printf 'Run as root for a read-only device-mapper probe.\n' >&2; exit 2; }
device=$(readlink -e -- "$2")
[[ -b $device ]] || { printf 'Expected an existing block device.\n' >&2; exit 2; }
parent=$(lsblk -dnro PKNAME "$device")
[[ -n $parent ]] || parent=${device##*/}
[[ $parent =~ ^[a-zA-Z0-9_-]+$ ]]
crypto=/sys/class/block/$parent/queue/crypto
[[ -r $crypto/raw_keys && $(< "$crypto/raw_keys") == supported &&
   -r $crypto/modes/AES-256-XTS ]] || {
    printf 'Underlying device does not advertise raw-key inline AES-256-XTS.\n' >&2
    exit 1
}
mask=$(< "$crypto/modes/AES-256-XTS")
if [[ ! $mask =~ ^0x[0-9a-fA-F]+$ ]] || (( (mask & 4096) == 0 )); then
    printf 'Hardware does not advertise 4096-byte AES-256-XTS data units.\n' >&2
    exit 1
fi
name=uke-inlinecrypt-read-$BASHPID
created=0
module_owned=0
trace_owned=0
trace=/sys/kernel/tracing/instances/$name
cleanup() {
    local result=$?
    trap - EXIT
    set +e
    unset probe_key
    if (( trace_owned )); then
        printf '0\n' > "$trace/tracing_on"
        printf 'nop\n' > "$trace/current_tracer"
        rmdir "$trace" || result=1
    fi
    if (( created )) || dmsetup info "$name" >/dev/null 2>&1; then
        timeout 10s dmsetup remove "$name" || result=1
    fi
    if (( module_owned )); then modprobe -r dm-inlinecrypt || result=1; fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ ! -d /sys/module/dm_inlinecrypt ]]; then
    modprobe dm-inlinecrypt
    module_owned=1
fi
# A task-owned function trace observes key programming without printing keys.
if [[ -r /sys/kernel/tracing/available_filter_functions ]] &&
   grep -q '^qcom_ice_program_key ' /sys/kernel/tracing/available_filter_functions; then
    mkdir "$trace"
    trace_owned=1
    printf '16\n' > "$trace/buffer_size_kb"
    printf 'qcom_ice_program_key\n' > "$trace/set_ftrace_filter"
    printf 'function\n' > "$trace/current_tracer"
    printf '1\n' > "$trace/tracing_on"
fi
probe_key=$(od -An -v -N64 -tx1 /dev/urandom | tr -d ' \n')
[[ ${#probe_key} == 128 ]]
# The key travels over stdin, never in argv, a file, a report or dmsetup table.
# Two data units avoid a zero-width maximum DUN in the kernel constructor.
printf '0 16 inlinecrypt aes-xts-plain64 %s 0 %s 0 3 keytype:raw sector_size:4096 iv_large_sectors\n' \
    "$probe_key" "$device" | timeout 15s dmsetup create --readonly "$name"
created=1
unset probe_key
[[ $(blockdev --getro "/dev/mapper/$name") == 1 ]]
timeout 15s dd if="/dev/mapper/$name" of=/dev/null bs=4096 count=1 iflag=direct status=none
key_calls=null
if (( trace_owned )); then
    printf '0\n' > "$trace/tracing_on"
    key_calls=$(grep -c 'qcom_ice_program_key' "$trace/trace" || true)
fi
wrapped=false
[[ ! -r $crypto/hw_wrapped_keys ]] || wrapped=true
jq -M -n --arg kernel "$(uname -r)" --argjson keyslots "$(< "$crypto/num_keyslots")" \
    --argjson wrapped "$wrapped" --argjson calls "$key_calls" \
    '{schema_version:1,kernel_release:$kernel,hardware_advertises_aes_256_xts_4096:true,
      hardware_keyslots:$keyslots,hardware_wrapped_keys_advertised:$wrapped,
      readonly_inlinecrypt_read_bytes:4096,qcom_ice_program_key_calls:$calls,
      partition_write_executed:false,key_persisted:false,
      write_roundtrip_tested:false,ext4_conversion_tested:false,
      automatic_key_release_tested:false,software_fallback_excluded:false}'
