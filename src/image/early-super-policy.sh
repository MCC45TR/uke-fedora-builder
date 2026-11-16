#!/usr/bin/bash
# SPDX-License-Identifier: MIT
# Pure bounded policy. It never opens a device or executes supplied arguments.
uke_early_super_policy() {
    [[ $# == 1 && ${#1} -le 8192 ]] || { echo 'UKE_SUPER_ROLE_REJECTED: command line exceeds bounds' >&2;return 1; }
    local line=$1 argument root='' fstype='' super=0 role=0 roots=0 types=0 ro=0 rw=0 noresume=0 resume=0
    local -a arguments=()
    [[ $line != *$'\n'* && $line != *$'\r'* ]] || { echo 'UKE_SUPER_ROLE_REJECTED: multiline command line' >&2;return 1; }
    read -r -a arguments <<< "$line"
    for argument in "${arguments[@]}";do
        case $argument in
            senemos.super=seed4-v1) super=$((super+1));;
            senemos.role=rescue) role=$((role+1));;
            senemos.super=*|senemos.role=*) echo 'UKE_SUPER_ROLE_REJECTED: unknown role or seed contract' >&2;return 1;;
            root=*) roots=$((roots+1));root=$argument;;
            rootfstype=*) types=$((types+1));fstype=$argument;;
            ro) ro=$((ro+1));;
            rw) rw=$((rw+1));;
            noresume) noresume=$((noresume+1));;
            resume=*|resume_offset=*) resume=$((resume+1));;
        esac
    done
    if ((super==0&&role==0));then printf 'none\n';return 0;fi
    ((super==1&&role<=1&&roots==1&&types==1)) || { echo 'UKE_SUPER_ROLE_REJECTED: duplicate or incomplete role selectors' >&2;return 1; }
    if ((role==1));then
        [[ $root == root=/dev/mapper/uke-rescue && $fstype == rootfstype=ext4 && $ro == 1 && $rw == 0 && $noresume == 1 && $resume == 0 ]] || { echo 'UKE_SUPER_ROLE_REJECTED: rescue requires the exact read-only EXT4 root and no resume' >&2;return 1; }
        printf 'rescue\n'
    else
        [[ $root == root=PARTLABEL=userdata && $fstype == rootfstype=ext4,f2fs,xfs,btrfs && $rw == 1 && $ro == 0 ]] || { echo 'UKE_SUPER_ROLE_REJECTED: super provisioning requires the selected userdata root' >&2;return 1; }
        printf 'userdata\n'
    fi
}
