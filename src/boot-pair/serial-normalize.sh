#!/usr/bin/env bash
# Host-only decoding of the generic VM's terminal observation stream.
normalize() {
    local escape=$'\033' bell=$'\007'
    tr -d '\r' < "$1" | sed -E \
        "s/${escape}\\][^${escape}${bell}]*(${bell}|${escape}\\\\)//g;s/${escape}P[^${escape}]*${escape}\\\\//g;s/${escape}\\[[0-?]*[ -/]*[@-~]//g;s/${escape}[78M]//g"
}
