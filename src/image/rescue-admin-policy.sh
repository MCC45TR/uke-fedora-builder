#!/usr/bin/bash
# SPDX-License-Identifier: MIT
# Read an existing enabled administrator's hash; never validate passwords here.
# The caller captures stdout privately and uses original Fedora sulogin.
uke_rescue_admin_hash() (
    set -Eeuo pipefail
    export LC_ALL=C.UTF-8
    [[ $# == 2 && $(id -u) == 0 ]] || exit 1
    local root=$1 account=$2 path mode
    [[ $root == /* && -d $root && ! -L $root && -d $root/etc && ! -L $root/etc ]] || exit 1
    [[ ${#account} -ge 1 && ${#account} -le 64 && $account != -* &&
       $account != *$'\\'* && $account != *[[:cntrl:][:space:]:/]* ]] || exit 1
    for path in "$root" "$root/etc" "$root/etc/passwd" "$root/etc/group" "$root/etc/shadow";do
        [[ ! -L $path && $(stat -c %u "$path") == 0 ]] || exit 1
        mode=$(stat -c %a "$path") || exit 1
        (( (8#$mode & 0022) == 0 )) || exit 1
    done
    for path in passwd group shadow;do
        [[ -f $root/etc/$path && $(stat -c %h "$root/etc/$path") == 1 &&
           $(stat -c %s "$root/etc/$path") -le 1048576 ]] || exit 1
    done
    awk -F: -v who="$account" '
      FILENAME==ARGV[1]&&$1==who {
        users++;if(NF!=7||$3!~/^[0-9]+$/||$4!~/^[0-9]+$/||$3<1000||$3>=65534)bad=1;
        primary=$4
      }
      FILENAME==ARGV[2]&&$1=="wheel" {
        groups++;if(NF!=4||$3!~/^[0-9]+$/)bad=1;wheel=$3;
        n=split($4,members,",");for(i=1;i<=n;i++)if(members[i]==who)member=1
      }
      FILENAME==ARGV[3]&&$1==who {
        shadows++;hash=$2;
        if(NF!=9||hash!~/^[$]/||length(hash)<10||length(hash)>1024||hash~/[^A-Za-z0-9./$=,+_-]/)bad=1
      }
      END {
        if(bad||users!=1||groups!=1||shadows!=1||(!member&&primary!=wheel))exit 1;
        print hash
      }' "$root/etc/passwd" "$root/etc/group" "$root/etc/shadow"
)
