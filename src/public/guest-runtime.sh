#!/usr/bin/env bash
# Virtual filesystems belong only to the disposable SDK, never the host.
public_guest_mounts() {
    [[ $(id -u) == 0 && -f /.uke-copr-sdk && $(< /.uke-copr-sdk) == 1 ]] || return 1
    PUBLIC_GUEST_MOUNTS=()
    local tree
    for tree in proc dev sys run; do
        [[ -d /$tree && ! -L /$tree ]] || return 1
        if findmnt --mountpoint "/$tree" --noheadings >/dev/null; then return 1; fi
    done
    mount -t proc -o nosuid,nodev,noexec proc /proc || return
    PUBLIC_GUEST_MOUNTS+=(/proc)
    mount -t devtmpfs -o nosuid devtmpfs /dev || return
    PUBLIC_GUEST_MOUNTS+=(/dev)
    mount -t sysfs -o ro,nosuid,nodev,noexec sysfs /sys || return
    PUBLIC_GUEST_MOUNTS+=(/sys)
    mount -t tmpfs -o nosuid,nodev tmpfs /run || return
    PUBLIC_GUEST_MOUNTS+=(/run)
}

public_guest_unmounts() {
    local index status=0
    for ((index=${#PUBLIC_GUEST_MOUNTS[@]}-1; index>=0; index--)); do
        umount "${PUBLIC_GUEST_MOUNTS[index]}" || status=1
    done
    return "$status"
}
