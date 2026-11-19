#!/usr/bin/env bash
# Host-side fastboot client wrapper. The check path uses only USB getvars.
set -Eeuo pipefail
export LC_ALL=C
umask 077
fail() { printf 'Uke fastboot: %s\n' "$*" >&2; exit 1; }
[[ $# == 2 && ( $1 == --check || $1 == --install ) && -f $2 ]] ||
    fail "usage: $0 --check|--install FASTBOOT_ZIP"
mode=$1 archive=$(realpath "$2")
for tool in fastboot jq unzip sha256sum timeout od df stat flock; do command -v "$tool" >/dev/null || fail "missing $tool"; done
exec 9< "$archive"
flock -n 9 || fail 'the same archive is already in use'
work=$(mktemp -d "${TMPDIR:-/tmp}/uke-fastboot.XXXXXXXX")
trap 'find "$work" -depth -delete' EXIT
files=(boot.img dtbo.img rescue-boot.img super.img userdata.img)
printf '%s\n' "${files[@]}" README.txt SHA256SUMS android-info.txt fastboot-info.txt install-stable-super-fastboot.sh manifest.json |
    sort > "$work/expected"
unzip -Z -1 "$archive" | sort | cmp - "$work/expected" || fail 'archive paths differ from the expected payload'

entry_size() {
    unzip -l "$archive" "$1" |
        awk -v name="$1" '$NF==name {count++; size=$1} END {if (count!=1) exit 1; print size}'
}
(( $(entry_size manifest.json) <= 65536 )) || fail 'oversized manifest'
unzip -p "$archive" manifest.json > "$work/manifest.json"
jq -e '
    .schema_version==1 and .artifact_kind=="uke-stable-super-fastboot" and .device=="uke" and
    .kernel_release=="7.4.5-senemos" and .super_layout.phase=="seed" and
    (.images|keys)==["boot.img","dtbo.img","rescue-boot.img","super.img","userdata.img"] and
    all(.images[]; (.sha256|type=="string" and test("^[a-f0-9]{64}$")) and
        (.stored_bytes|type=="number" and floor==. and .>=28 and .<=8589934592) and
        (.expanded_bytes|type=="number" and floor==. and .>=28 and .<=8589934592)) and
    .images["boot.img"].expanded_bytes==100663296 and .images["rescue-boot.img"].expanded_bytes==100663296 and
    .images["super.img"].expanded_bytes==4294967296 and .images["userdata.img"].expanded_bytes==8589934592
' "$work/manifest.json" >/dev/null || fail 'unexpected image manifest'
manifest=$work/manifest.json

timeout --kill-after=2s 10s fastboot devices > "$work/devices" || fail 'could not list fastboot devices'
mapfile -t devices < <(awk '$2=="fastboot"{print $1}' "$work/devices")
[[ ${#devices[@]} == 1 && ${devices[0]} =~ ^[a-zA-Z0-9._-]+$ ]] || fail 'connect one Uke to USB in bootloader fastboot'
client=(fastboot -s "${devices[0]}")
getvar() {
    local key=$1 result line value='' count=0
    result=$(timeout --kill-after=2s 10s "${client[@]}" getvar "$key" 2>&1) || fail "bootloader did not provide $key"
    [[ ${#result} -le 4096 ]] || fail "oversized $key response"
    while IFS= read -r line; do
        line=${line%$'\r'}
        line=${line#'(bootloader) '}
        if [[ $line == "$key:"* ]]; then
            value=${line#"$key:"}
            value=${value##+([[:space:]])}
            value=${value%%+([[:space:]])}
            count=$((count+1))
        fi
    done <<< "$result"
    [[ $count == 1 && -n $value ]] || fail "missing or ambiguous $key"
    printf '%s\n' "$value"
}

capacity() {
    local name=$1 value
    value=$(getvar "partition-size:$name") || return
    [[ $value =~ ^0[xX][0-9a-fA-F]{1,16}$ ]] || fail "invalid $name capacity"
    value=${value:2}
    value=${value##+(0)}
    [[ -n $value && ${#value} -le 11 ]] || fail "invalid $name capacity"
    (( 16#$value <= 2199023255552 )) || fail "unsupported $name capacity"
    printf '%s\n' "$((16#$value))"
}

measure() {
    local suffix name bytes super userdata unlocked
    [[ $(getvar product) == uke && $(getvar is-userspace) == no && $(getvar slot-count) == 2 ]] ||
        fail 'expected a two-slot Uke in bootloader fastboot'
    if unlocked=$(getvar unlocked 2>/dev/null); then
        [[ $unlocked == yes ]] || fail 'an unlocked Uke bootloader is required'
    else
        # Some Xiaomi ABL versions use this read-only OEM status command.
        unlocked=$(timeout --kill-after=2s 10s "${client[@]}" oem device-info 2>&1) ||
            fail 'could not read Xiaomi bootloader unlock state'
        [[ ${#unlocked} -le 4096 ]] || fail 'oversized OEM device-info response'
        [[ $(awk '{sub(/^[(]bootloader[)][[:space:]]*/, ""); sub(/\r$/, "")}
                  /^Device unlocked:/ {lines++; if ($3=="true" && NF==3) yes++}
                  END {print (lines==1 && yes==1) ? 1 : 0}' <<< "$unlocked") == 1 ]] || fail 'an unlocked Uke bootloader is required'
    fi
    [[ $(getvar snapshot-update-status) == none ]] || fail 'complete the Android snapshot update first'
    suffix=$(getvar current-slot) || return
    [[ $suffix == a || $suffix == b ]] || fail 'unknown active slot'
    for name in "boot_$suffix" "vendor_boot_$suffix" "dtbo_$suffix" "vbmeta_$suffix"; do
        bytes=$(capacity "$name") || return
        case $name in
            boot_*|vendor_boot_*) ((bytes == 100663296)) || fail "$name differs from the Uke boot geometry";;
            dtbo_*) ((bytes == 25165824)) || fail "$name differs from the Uke DTBO geometry";;
            vbmeta_*) ((bytes == 131072)) || fail "$name differs from the Uke vbmeta geometry";;
        esac
    done
    super=$(capacity super) || return
    userdata=$(capacity userdata) || return
    # The same 4 GiB seed grows in place against the measured super capacity.
    ((super >= 4294967296 && super % 4096 == 0)) || fail "super cannot hold the 4 GiB seed ($super bytes)"
    ((userdata >= 8589934592 && userdata % 4096 == 0)) || fail "userdata cannot hold the 8 GiB image ($userdata bytes)"
    printf '%s %s %s\n' "$suffix" "$super" "$userdata"
}

shopt -s extglob
geometry=$(measure)
read -r slot super userdata <<< "$geometry"
printf 'Uke slot %s, super %s bytes, userdata %s bytes.\n' "$slot" "$super" "$userdata"
if [[ $mode == --install ]]; then
    stored=$(jq -er '[.images | to_entries[] | select(.key!="rescue-boot.img") | .value.stored_bytes] | add' "$manifest")
    available=$(df -B1 --output=avail "$work" | tail -n1)
    (( available >= stored + 2147483648 )) || fail 'use TMPDIR on a host filesystem with space for the sparse images and 2 GiB free'
fi

for file in "${files[@]}"; do
    IFS=$'\t' read -r stored expanded expected < <(jq -er --arg file "$file" '.images[$file]|[.stored_bytes,.expanded_bytes,.sha256]|@tsv' "$manifest")
    [[ $(entry_size "$file") == "$stored" ]] || fail "ZIP entry size differs for $file"
    if [[ $mode == --install && $file != rescue-boot.img ]]; then
        unzip -p "$archive" "$file" > "$work/$file"
        actual=$(sha256sum "$work/$file")
    else
        actual=$(unzip -p "$archive" "$file" | sha256sum)
    fi
    [[ ${actual%% *} == "$expected" ]] || fail "SHA-256 differs for $file"
    case $file in
        userdata.img|super.img)
            if [[ -f $work/$file ]]; then
                od -An -N28 -tx1 "$work/$file" > "$work/header"
            else
                # The complete stream and CRC already passed. Drain this second
                # stream after capturing the sparse header to avoid SIGPIPE.
                unzip -p "$archive" "$file" | { od -An -N28 -tx1 > "$work/header"; cat > /dev/null; }
            fi
            read -r -a header < <(xargs < "$work/header")
            [[ ${#header[@]} == 28 && ${header[*]:0:12} == '3a ff 26 ed 01 00 00 00 1c 00 0c 00' ]] ||
                fail "invalid Android sparse header for $file"
            block=$((16#${header[15]}${header[14]}${header[13]}${header[12]}))
            count=$((16#${header[19]}${header[18]}${header[17]}${header[16]}))
            ((block == 4096 && count * block == expanded)) || fail "expanded size differs for $file"
            ;;
        *) ((stored == expanded)) || fail "raw size differs for $file";;
    esac
    printf '%s verified.\n' "$file"
done
[[ $(measure) == "$geometry" ]] || fail 'partition sizes or the active slot changed before installation'
if [[ $mode == --check ]]; then
    printf 'Compatibility and payload checks passed.\n'
    exit 0
fi
printf 'Replacing super and userdata and writing the active boot and DTBO slot.\n'
"${client[@]}" flash super "$work/super.img"
"${client[@]}" flash userdata "$work/userdata.img"
"${client[@]}" flash "dtbo_$slot" "$work/dtbo.img"
"${client[@]}" flash "boot_$slot" "$work/boot.img"
"${client[@]}" reboot
