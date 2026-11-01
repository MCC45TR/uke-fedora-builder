#!/usr/bin/env bash
# The full producer and integration check use identical verified SDK bytes.
# shellcheck source=guest-appliance.sh
# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/guest-appliance.sh"
# shellcheck disable=SC2034
public_copr_sdk() {
    local recipe=$1 inputs=$2 work=$3 archive name
    [[ ${UKE_COPR_WORKER_AUDIT:-0} == 1 && -d $recipe && -d $inputs && -d $work ]] || return 1
    [[ $recipe =~ ^/[A-Za-z0-9_./+-]+$ && $inputs =~ ^/[A-Za-z0-9_./+-]+$ && $work =~ ^/[A-Za-z0-9_./+-]+$ ]] || return 1
    export LIBGUESTFS_BACKEND=direct LIBGUESTFS_BACKEND_SETTINGS=force_tcg
    export LIBGUESTFS_CACHEDIR=$work/cache LIBGUESTFS_TMPDIR=$work/tmp
    mkdir "$work/cache" "$work/tmp" "$work/keydb" "$work/job" || return
    (cd "$inputs" && sha256sum -c SHA256SUMS > "$work/input-hashes.log") || return
    rpmkeys --dbpath "$work/keydb" --import "$recipe/configs/keys/fedora-46.asc" || return
    local archives=("$inputs/rpms/"*.rpm)
    [[ -f ${archives[0]} ]] || return 1
    PUBLIC_COPR_SDK_RPMS=${#archives[@]}
    for archive in "${archives[@]}"; do
        [[ $(rpm -qp --qf '%{VENDOR}' "$archive") == 'Fedora Project' ]] || return 1
        case $(rpm -qp --qf '%{ARCH}' "$archive") in aarch64|noarch) ;; *) return 1;; esac
        rpmkeys --dbpath "$work/keydb" --checksig "$archive" | grep -F 'signatures OK' || return
        if [[ $(rpm -qp --qf '%{NAME}' "$archive") == e2fsprogs ]]; then
            rpm -qp --qf '[%{FILENAMES}\t%{FILEDIGESTS}\n]' "$archive" \
                | awk -F '\t' '$1=="/usr/bin/mke2fs" {print $2 "  " $1}' > "$work/mke2fs.sha256" || return
        fi
    done
    [[ -s $work/mke2fs.sha256 ]] || return 1
    tar -cf "$work/sdk.tar" --files-from /dev/null || return
    local sdk_names=()
    mapfile -t sdk_names < "$inputs/closures/sdk-rpms.list" || return
    (( ${#sdk_names[@]} > 0 )) || return 1
    for name in "${sdk_names[@]}"; do
        [[ $name =~ ^[A-Za-z0-9+_.:-]+[.]rpm$ && -f $inputs/rpms/$name && ! -L $inputs/rpms/$name ]] || return 1
        rpm2cpio "$inputs/rpms/$name" > "$work/payload.cpio" || return
        bsdtar -tf "$work/payload.cpio" > "$work/payload.paths" || return
        awk '/^\// || /(^|\/)\.\.(\/|$)/ {bad=1} END {exit bad}' "$work/payload.paths" || return
        if [[ -e $work/payload.tar ]]; then unlink "$work/payload.tar" || return; fi
        "$recipe/build-fixtures/cpio-sdk-tar" "$work/payload.cpio" "$work/payload.tar" || return
        tar --concatenate -f "$work/sdk.tar" "$work/payload.tar" || return
    done
}

public_copr_guest_run() {
    [[ $# == 5 || $# == 6 ]] || return 1
    local mode=$1 disk=$2 commands=$3 log=$4 seconds=$5 status=0 extra=${6:-}
    [[ ${UKE_COPR_WORKER_AUDIT:-0} == 1 && -f $disk && ! -L $disk && -f $commands && ! -L $commands ]] || return 1
    [[ $mode == ro || $mode == rw ]] || return 1
    [[ $seconds =~ ^[1-9][0-9]{0,4}$ && ! -e $log && ! -L $log ]] || return 1
    local disks=(--format=raw -a "$disk")
    if [[ -n $extra ]]; then
        [[ $mode == ro && -f $extra && ! -L $extra ]] || return 1
        disks+=(--format=raw -a "$extra")
    fi
    public_guest_appliance "$log.appliance" || return
    LIBGUESTFS_BACKEND=direct LIBGUESTFS_BACKEND_SETTINGS=force_tcg \
    timeout --kill-after=20 "$seconds" guestfish "--$mode" "${disks[@]}" \
        -f "$commands" 2>&1 | tee "$log" || status=$?
    if [[ $status != 0 ]]; then cat "$log" >&2; fi
    return "$status"
}
