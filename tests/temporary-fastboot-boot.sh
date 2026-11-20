#!/usr/bin/env bash
# Record stock Fastboot's commands and image bytes on a loopback peer.
set -Eeuo pipefail
[[ ( $# == 1 || $# == 2 ) && -f $1 && $(stat -c %s "$1") == 100663296 ]]
zip=${2:-}
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
server=''
cleanup() {
    local status=$?
    if [[ -n $server ]]; then kill "$server" 2>/dev/null || :; wait "$server" 2>/dev/null || :; fi
    if ((status)); then tail -n 20 "$work/client.log" "$work/server.log" "$work/commands.txt" >&2 || :; fi
    find "$work" -depth -delete
}
trap cleanup EXIT
touch "$work/boot-only"
jq -n '{
    product:"uke", "is-userspace":"no", "max-download-size":"0x30000000",
    "version-bootloader":"fixture", "version-baseband":"fixture", serialno:"FIXTURE",
    "slot-count":"2", "current-slot":"b", "snapshot-update-status":"none",
    "has-slot:boot":"yes", "partition-size:boot_b":"0x06000000"
}' > "$work/vars.json"
if [[ -n $zip ]]; then
    [[ -f $zip ]]
    printf '["boot_b"]\n' > "$work/allowed.json"
    args=(update "$zip")
    printf 'set_active:b\ndownload:06000000\nflash:boot_b\nreboot\n' > "$work/expected.txt"
else
    printf '[]\n' > "$work/allowed.json"
    args=(boot "$1")
    printf 'download:06000000\nboot\n' > "$work/expected.txt"
fi
for _ in {1..10}; do
    port=$((30000 + RANDOM % 20000))
    socat -T10 "TCP4-LISTEN:$port,bind=127.0.0.1,nodelay" \
        "EXEC:bash $repo/tests/fastboot-tcp-peer.sh $work" > "$work/server.log" 2>&1 &
    server=$!
    sleep 0.1
    if kill -0 "$server" 2>/dev/null; then break; fi
    wait "$server" || :
    server=''
done
[[ -n $server ]]
timeout --kill-after=2s 45s fastboot -s "tcp:127.0.0.1:$port" "${args[@]}" > "$work/client.log" 2>&1
cmp "$1" "$work/download.bin"
grep -v '^getvar:' "$work/commands.txt" | cmp - "$work/expected.txt"
cat "$work/client.log"
printf 'Verified the image bytes and Fastboot %s command sequence.\n' "${args[0]}"
