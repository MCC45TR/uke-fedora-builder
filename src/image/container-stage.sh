#!/usr/bin/env bash
# Retain target inode ownership while making outer artifacts usable by the host.
set -Eeuo pipefail
[[ $# -ge 3 && $1 == /builder/build/images/* ]]
work=$1 owner=$2; shift 2
[[ $owner == none || $owner =~ ^[0-9]+:[0-9]+$ ]]
if "$@"; then result=0; else result=$?; fi
if [[ $owner != none ]]; then
    # Rootful Docker maps container UID 0 to host UID 0. Only outer output files
    # are reassigned. Extracted roots stay untouched until metadata verification.
    find "$work" -maxdepth 1 -type f -exec chown -- "$owner" {} +
    if [[ -d $work/candidate && ! -L $work/candidate ]]; then
        chown -- "$owner" "$work/candidate"
        find "$work/candidate" -maxdepth 1 -type f -exec chown -- "$owner" {} +
    fi
fi
exit "$result"
