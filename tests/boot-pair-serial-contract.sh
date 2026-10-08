#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../src/boot-pair/serial-normalize.sh
# shellcheck disable=SC1091
source "$root/src/boot-pair/serial-normalize.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
# systemd/agetty CSI, OSC with both terminators, DCS query and cursor saves
# may share a serial line with the command's independent ttyAMA0 write.
printf '\033[32mUKE_ROOT_ADMITTED\033[0m\r\n\033]3008;fixture\033\\\033P+q6E616D65\033\\realrootok\r\n\033]104\007\0337\0338\033Mselinux=1\r\n' > "$fixture/serial"
printf 'UKE_ROOT_ADMITTED\nrealrootok\nselinux=1\n' > "$fixture/expected"
normalize "$fixture/serial" > "$fixture/actual"
cmp "$fixture/expected" "$fixture/actual"
tty_command_observed "$fixture/serial"
printf 'localhost login: realrootok\r\n' > "$fixture/login"
tty_command_observed "$fixture/login"
for text in unrealrootok realrootokextra 'echo realrootok > /dev/ttyAMA0' realroot; do
    printf '%s\n' "$text" > "$fixture/reject"
    if tty_command_observed "$fixture/reject"; then echo 'Non-command marker accepted' >&2; exit 1; fi
done
echo 'Serial CSI/OSC/DCS, shared login line and marker-rejection fixtures passed'
