#!/usr/bin/env bash
# Readback comparison and negative metadata controls, inside the COPR SDK only.
set -Eeuo pipefail
[[ $(id -u) == 0 && -f /job/root-readback.tar && -f /job/rootfs.tar ]]
source /builder/src/public/root-metadata.sh
exec 3>&2 4>&1
exec > /job/metadata-compare.log 2>&1
mount -t proc -o nosuid,nodev,noexec proc /proc
cleanup() {
    local status=$?
    umount /proc || status=1
    if [[ $status == 0 ]]; then cat /job/metadata-compare.log >&4
    else tail -120 /job/metadata-compare.log >&3; fi
    exit "$status"
}
trap cleanup EXIT
auditor=/builder/build-tools/compare-root-metadata
public_root_compare /job/root /job/rootfs.tar /job/root-readback.tar /job "$auditor"
mkdir /job/control-readback
tar --extract --numeric-owner --acls --xattrs --xattrs-include=security.capability \
    -f /job/root-readback.tar -C /job/control-readback
uid=$(jq -er .chrony_uid /job/report.json)
gid=$(jq -er .chrony_gid /job/report.json)
reject() {
    local expected=$1
    if "$auditor" /job/root /job/control-readback > /job/negative.log 2>&1; then
        echo 'Metadata mismatch accepted' >&2; exit 1
    fi
    grep -F "$expected" /job/negative.log
}
chown 0:0 /job/root/var/lib/chrony
reject 'Mode or owner differs: var/lib/chrony'
chown "$uid:$gid" /job/root/var/lib/chrony
setfacl -n -m "u:$uid:---" /job/root/opt/uke-image-fixture/data
reject 'system.posix_acl_access'
setfacl -n -m "u:$uid:r--" /job/root/opt/uke-image-fixture/data
setcap -r /job/root/opt/uke-image-fixture/capability-probe
reject 'security.capability'
setcap cap_net_bind_service=ep /job/root/opt/uke-image-fixture/capability-probe
"$auditor" /job/root /job/control-readback
printf '%s\n' 'UKE_COPR_EXT4_METADATA content=true inventory=true owners=true modes=true acl=true capabilities=true mismatch_controls=3 full_os_composition=false hardware_tested=false'
