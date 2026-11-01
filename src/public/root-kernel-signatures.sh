#!/usr/bin/env bash
# An isolated root worker must establish its own signer trust, even when the
# producer's signed RPM bytes came from a verified shared-core archive.
public_root_kernel_signatures() {
    local key=$1 database=$2 archive result
    shift 2
    [[ -f $key && ! -L $key && $# -gt 0 ]] || return 1
    mkdir -p "$database" || return
    rpmkeys --dbpath "$database" --import "$key" || return
    for archive in "$@"; do
        [[ -f $archive && ! -L $archive ]] || return 1
        result=$(rpmkeys --dbpath "$database" --checksig "$archive") || { printf '%s\n' "$result" >&2; return 1; }
        printf '%s\n' "$result"
        [[ $result == *'signatures OK' ]] || return 1
    done
}
