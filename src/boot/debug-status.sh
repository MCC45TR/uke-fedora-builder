#!/bin/sh
# Tablet-side diagnostic helper; POSIX shell and native Fedora commands only.
set -u
printf '%s\n' 'UKE_BUILTIN_FEDORA_DEBUG_READY'
uname -r
printf 'forced_cmdline='
cat /proc/cmdline
/usr/bin/uke-boot-status --identity
status=$?
printf 'identity_exit=%s\n' "$status"
systemctl show uke-initrd-shell.service -p ActiveState -p SubState -p NRestarts
printf '%s\n' 'debug_mounts_begin'
cat /proc/mounts
printf '%s\n' 'debug_mounts_end'
