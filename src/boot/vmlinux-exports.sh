#!/usr/bin/env bash
# Host-only receipt from the final modpost table; legacy vmlinux.symvers may be stale.
set -Eeuo pipefail
[[ $# == 1 && -s $1 && -f $1 ]] || exit 2
awk '$3=="vmlinux" { print; found=1 } END { if (!found) exit 1 }' "$1" | LC_ALL=C sort
