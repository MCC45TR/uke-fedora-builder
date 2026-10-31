#!/usr/bin/env bash
# Formatting and non-recovery readback policy shared by both assembly routes.
public_filesystem_format() {
    case $1 in
        btrfs) echo 'mkfs-btrfs /dev/sda label:UKE_LINUX sectorsize:4096';;
        f2fs) echo 'mkfs f2fs /dev/sda label:UKE_LINUX features:extra_attr,inode_checksum,sb_checksum';;
        ext4|xfs) printf 'mkfs %s /dev/sda label:UKE_LINUX blocksize:4096\n' "$1";;
        *) return 1;;
    esac
}
public_filesystem_ro_options() {
    case $1 in
        ext4) echo ro,noload;;
        f2fs|xfs) echo ro,norecovery;;
        btrfs) echo ro,rescue=nologreplay;;
        *) return 1;;
    esac
}
