#!/usr/bin/env bash
# Root ownership is used only inside the disposable offline SDK.
set -Eeuo pipefail
failure_status=0
trap 'failure_status=$?; printf "UKE_COPR_FS_ENTRY_ERROR line=%s status=%s command=%q\n" "$LINENO" "$failure_status" "$BASH_COMMAND" >&2' ERR
[[ $# == 1 && $(id -u) == 0 && -f /.uke-copr-sdk && $(< /.uke-copr-sdk) == 1 ]]
export LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH=/usr/sbin:/usr/bin:/sbin:/bin
case $1 in populate|compare) ;; *) exit 1;; esac
mode=$1
tools=$(jq -er .tools /job/filesystem-request.json)
case $tools in /builder/build-tools|/job/tools-payload/usr/libexec/uke-image-tools) ;; *) exit 1;; esac
size=$(jq -er .size_mib /job/filesystem-request.json)
[[ $size =~ ^[1-9][0-9]{3,4}$ && $size -le 65536 ]]
printf 'UKE_COPR_FS_ENTRY operation=%s tools=%s size_mib=%s\n' "$mode" "$tools" "$size" >&2
# shellcheck source=guest-runtime.sh
# shellcheck disable=SC1091
source /builder/src/public/guest-runtime.sh
# shellcheck source=ext4-filesystem.sh
# shellcheck disable=SC1091
source /builder/src/public/ext4-filesystem.sh
# shellcheck source=root-metadata.sh
# shellcheck disable=SC1091
source /builder/src/public/root-metadata.sh
exec 3>&2 4>&1
exec > /job/filesystem-entry.log 2>&1
# shellcheck disable=SC2034
PUBLIC_GUEST_MOUNTS=()
cleanup() {
    local status=$?
    public_guest_unmounts || status=1
    if [[ $status == 0 ]]; then cat /job/filesystem-entry.log >&4
    else tail -120 /job/filesystem-entry.log >&3; fi
    exit "$status"
}
trap cleanup EXIT
public_guest_mounts
if [[ $mode == populate ]]; then
    [[ $(jq -er .filesystem /job/filesystem-request.json) == ext4 ]]
    sha256sum -c /job/mke2fs.sha256
    public_ext4_populate /job/composed.raw /job/root "$size" "$tools/ext4-labels"
else
    public_root_compare /job/root /job/rootfs.tar /job/filesystem-readback.tar /job "$tools/compare-root-metadata"
    unlink /job/filesystem-readback.tar
fi
