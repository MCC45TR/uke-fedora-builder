#!/usr/bin/env bash
# Native controls only inside the COPR SDK; never run on the tablet.
set -Eeuo pipefail
[[ $(id -u) == 0 && -f /.uke-copr-sdk && $(< /.uke-copr-sdk) == 1 && ! -e /job/label-tree ]]
labeler=/builder/build-tools/ext4-labels
mkdir /job/label-tree
printf 'label control\n' > /job/label-tree/file
ln -s /file /job/label-tree/link
printf '/.* system_u:object_r:default_t:s0\n' > /job/label-contexts
for path in /job/label-tree /job/label-tree/file /job/label-tree/link; do
    setfattr -h -n security.selinux -v system_u:object_r:default_t:s0 "$path"
done
"$labeler" verify-tree /job/label-tree /job/label-contexts
setfattr -h -n security.selinux -v system_u:object_r:lib_t:s0 /job/label-tree/link
if "$labeler" verify-tree /job/label-tree /job/label-contexts > /job/label-negative.log 2>&1; then exit 1; fi
grep -F 'Context differs at /link' /job/label-negative.log
setfattr -h -n security.selinux -v system_u:object_r:default_t:s0 /job/label-tree/link
setfattr -x security.selinux /job/label-tree/file
if "$labeler" verify-tree /job/label-tree /job/label-contexts > /job/label-negative.log 2>&1; then exit 1; fi
grep -F 'Context differs at /file' /job/label-negative.log
setfattr -n security.selinux -v system_u:object_r:default_t:s0 /job/label-tree/file
"$labeler" verify-tree /job/label-tree /job/label-contexts
ln -s /job/label-tree /job/label-link
if "$labeler" verify-tree /job/label-link /job/label-contexts > /job/label-negative.log 2>&1; then exit 1; fi
grep -F 'Tree must be a directory' /job/label-negative.log
printf '%s\n' 'All-path SELinux tree verification rejects missing/wrong symlink labels and symlink roots; restored metadata passes.'
