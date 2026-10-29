#!/usr/bin/env bash
# Host installroot only; systemd reopens input descriptors through procfs.
public_root_proc_mount() {
    local root=$1
    [[ -d $root && ! -L $root && -d $root/proc && ! -L $root/proc ]] || return 1
    ! findmnt --mountpoint "$root/proc" --noheadings >/dev/null || return 1
    mount --rbind /proc "$root/proc" || return
    mount -o remount,bind,ro "$root/proc"
}
public_root_proc_unmount() {
    local root=$1
    [[ -d $root && ! -L $root && -d $root/proc && ! -L $root/proc ]] || return 1
    if findmnt --mountpoint "$root/proc" --noheadings >/dev/null; then
        # Detach the whole inherited proc tree, including locked masked submounts.
        umount -l "$root/proc" || return
    fi
    ! findmnt --mountpoint "$root/proc" --noheadings >/dev/null
}
