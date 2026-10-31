#!/usr/bin/env bash
# Virtual filesystems belong only to the disposable SDK, never the host.
public_guest_mounts() {
    if [[ $(id -u) != 0 || ! -f /.uke-copr-sdk || $(< /.uke-copr-sdk) != 1 ]]; then
        echo 'Disposable SDK marker and root are required for virtual filesystem setup' >&2
        return 1
    fi
    PUBLIC_GUEST_MOUNTS=()
    local tree
    for tree in proc dev sys run; do
        if [[ ! -d /$tree || -L /$tree ]]; then
            echo "SDK virtual filesystem directory is absent or a symlink: /$tree" >&2
            return 1
        fi
        if findmnt --mountpoint "/$tree" --noheadings >/dev/null; then
            echo "SDK virtual filesystem is already mounted: /$tree" >&2
            return 1
        fi
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
