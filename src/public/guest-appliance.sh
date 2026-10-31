#!/usr/bin/env bash
# Extend a private appliance recipe; never change the distribution's files.
public_guest_appliance() {
    [[ $# == 1 ]] || return 1
    local output=$1 base=/usr/lib64/guestfs/supermin.d
    [[ $output =~ ^/[A-Za-z0-9_./+-]+$ && ! -e $output && ! -L $output &&
       -d $base && -f $base/packages ]] || return 1
    mkdir -m700 "$output" || return
    mkdir "$output/supermin.d" || return
    cp -R --preserve=mode,timestamps --no-dereference "$base/." "$output/supermin.d" || return
    [[ ! -e $output/supermin.d/packages-uke-filesystems &&
       ! -L $output/supermin.d/packages-uke-filesystems ]] || return 1
    # Supermin resolves the installed packages and their dependencies at launch.
    printf '%s\n' btrfs-progs e2fsprogs f2fs-tools xfsprogs \
        > "$output/supermin.d/packages-uke-filesystems" || return
    export LIBGUESTFS_PATH=$output
}
