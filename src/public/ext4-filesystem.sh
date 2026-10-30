#!/usr/bin/env bash
# Populate a new regular-file image from a genuinely owned staging tree.
# COPR callers run this inside the SDK guest, never under fake host ownership.
public_ext4_populate() {
    local image=$1 root=$2 size=$3 labeler=$4 owner mode
    [[ $(id -u) == 0 && -d $root && ! -L $root && -x $labeler && ! -L $labeler ]] || return 1
    [[ $size =~ ^[1-9][0-9]{3,6}$ && ! -e $image && ! -L $image ]] || return 1
    ((size <= 65536)) || return 1
    [[ -s $root/etc/selinux/targeted/contexts/files/file_contexts ]] || return 1
    owner=$(stat -c '%u:%g' "$root") || return
    mode=$(stat -c '%a' "$root") || return
    [[ $owner =~ ^[0-9]+:[0-9]+$ && $mode =~ ^[0-7]{3,4}$ ]] || return 1
    truncate -s "${size}M" "$image" || return
    [[ -f $image && ! -L $image ]] || return 1
    # Preserve real root inode metadata as well as the populated descendants.
    # mke2fs copies xattrs by default; the labeler independently checks capabilities.
    mke2fs -q -F -t ext4 -b 4096 -L UKE_LINUX \
        -E "root_owner=$owner,root_perms=0$mode,lazy_itable_init=0,lazy_journal_init=0" \
        -d "$root" "$image" || return
    "$labeler" apply "$image" "$root" "$root/etc/selinux/targeted/contexts/files/file_contexts" || return
    "$labeler" verify "$image" "$root" "$root/etc/selinux/targeted/contexts/files/file_contexts"
}
