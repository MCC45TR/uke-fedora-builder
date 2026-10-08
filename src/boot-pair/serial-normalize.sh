#!/usr/bin/env bash
# Host-only decoding of the generic VM's terminal observation stream.
normalize() {
    local escape=$'\033' bell=$'\007'
    tr -d '\r' < "$1" | sed -E \
        "s/${escape}\\][^${escape}${bell}]*(${bell}|${escape}\\\\)//g;s/${escape}P[^${escape}]*${escape}\\\\//g;s/${escape}\\[[0-?]*[ -/]*[@-~]//g;s/${escape}[78M]//g"
}
tty_command_observed() {
    # ttyAMA0 also carries agetty output. Its prompt may precede the shell's
    # independent write on the same line. Require the complete marker at the
    # line end, separated from any preceding word; never accept an echoed
    # command, a longer word or a partial marker.
    normalize "$1" | grep -Eq '(^|[^[:alnum:]_])realrootok$'
}
