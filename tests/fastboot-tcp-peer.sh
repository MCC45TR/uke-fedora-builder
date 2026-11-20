#!/usr/bin/env bash
# Disposable host-only protocol peer. socat binds it to loopback; never a device.
set -Eeuo pipefail
export LC_ALL=C
[[ $# == 1 && -d $1 ]]
work=$1
max_download=1048576
[[ ! -f $work/boot-only ]] || max_download=100663296
receive_length() {
    local b n=0 bytes
    bytes=$(dd bs=8 count=1 iflag=fullblock status=none | od -An -v -tu1)
    read -r -a octets <<< "$bytes"
    [[ ${#octets[@]} == 8 ]] || return 1
    for b in "${octets[@]}"; do n=$((n * 256 + b)); done
    ((n > 0 && n <= max_download)) || return 1
    length=$n
}
send_packet() {
    local value=$1 shift byte
    for shift in 56 48 40 32 24 16 8 0; do
        printf -v byte '\\%03o' "$(((${#value} >> shift) & 255))"
        printf '%b' "$byte"
    done
    printf '%s' "$value"
}
[[ $(dd bs=4 count=1 iflag=fullblock status=none) == FB01 ]]
printf FB01
while receive_length; do
    command=$(dd bs="$length" count=1 iflag=fullblock status=none)
    printf '%s\n' "$command" >> "$work/commands.txt"
    case $command in
        getvar:*)
            key=${command#getvar:}
            value=$(jq -er --arg key "$key" '.[$key]' "$work/vars.json") || {
                send_packet 'FAILUnknown variable'; continue;
            }
            send_packet "OKAY$value";;
        set_active:a|set_active:b) send_packet OKAY;;
        download:*)
            size=${command#download:}
            [[ $size =~ ^[0-9a-f]{8}$ ]] && ((16#$size <= max_download))
            remaining=$((16#$size))
            send_packet "DATA$size"
            : > "$work/download.bin"
            while ((remaining)); do
                receive_length
                ((length <= remaining))
                dd bs=65536 count="$length" iflag=count_bytes,fullblock status=none >> "$work/download.bin"
                remaining=$((remaining - length))
            done
            [[ $(stat -c %s "$work/download.bin") == "$((16#$size))" ]]
            send_packet OKAY;;
        flash:*)
            partition=${command#flash:}
            jq -e --arg name "$partition" 'index($name) != null' "$work/allowed.json" >/dev/null
            # Only a synthetic sparse fixture needs expansion accounting here.
            # This is not the production image validator or real flash behavior.
            magic=$(od -An -v -N4 -tx1 "$work/download.bin" | tr -d ' \n')
            bytes=$(stat -c %s "$work/download.bin")
            if [[ $magic == 3aff26ed ]]; then
                read -r b0 b1 b2 b3 < <(od -An -v -j16 -N4 -tu1 "$work/download.bin")
                bytes=$(((b0 + (b1 << 8) + (b2 << 16) + (b3 << 24)) * 4096))
            fi
            capacity=$(jq -er --arg key "partition-size:$partition" '.[$key]' "$work/vars.json")
            if ((bytes > capacity)); then
                printf '%s\n' "$partition" > "$work/too-large.txt"
                send_packet 'FAILexpanded image too large'
            else
                printf '%s %s\n' "$partition" "$bytes" >> "$work/accepted.txt"
                send_packet OKAY
            fi;;
        boot)
            [[ -f $work/boot-only && $(stat -c %s "$work/download.bin") == "$max_download" ]]
            send_packet OKAY
            exit 0;;
        reboot)
            send_packet OKAY
            exit 0;;
        *) send_packet 'FAILUnexpected mutation'; exit 1;;
    esac
done
