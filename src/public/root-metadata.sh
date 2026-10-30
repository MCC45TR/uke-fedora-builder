#!/usr/bin/env bash
# Shared archive/readback policy for the real image stage and COPR guest checks.
public_root_archive() {
    local root=$1 output=$2
    [[ $(id -u) == 0 && -d $root && ! -L $root && ! -e $output && ! -L $output ]] || return 1
    tar --create --format=posix --numeric-owner --one-file-system --sort=name --acls --xattrs \
        --xattrs-include=security.capability -f "$output" -C "$root" .
}
public_root_compare() {
    local root=$1 original=$2 readback=$3 scratch=$4 auditor=$5 comparison
    [[ $(id -u) == 0 && -d $root && ! -L $root && -f $original && -f $readback && -d $scratch ]] || return 1
    # SELinux labels are generated from policy; all data, owners, modes, ACLs and
    # capability bytes must match the original staging tree independently.
    comparison=$(mktemp -d "$scratch/metadata.XXXXXX") || return
    if ! tar --compare --numeric-owner --acls --xattrs --xattrs-include=security.capability \
        -f "$readback" -C "$root" > "$comparison/diff.log" 2>&1; then
        cat "$comparison/diff.log" >&2
        return 1
    fi
    tar -tf "$original" | sed -e 's|^\./||' -e 's|/$||' | LC_ALL=C sort > "$comparison/original" || return
    tar -tf "$readback" | sed -e 's|^\./||' -e 's|/$||' | LC_ALL=C sort > "$comparison/readback" || return
    if ! cmp "$comparison/original" "$comparison/readback"; then
        diff -u "$comparison/original" "$comparison/readback" >&2 || true
        return 1
    fi
    mkdir "$comparison/root" || return
    tar --extract --numeric-owner --acls --xattrs --xattrs-include=security.capability \
        -f "$readback" -C "$comparison/root" || return
    "$auditor" "$root" "$comparison/root" || return
    find "$comparison" -depth -delete
}
