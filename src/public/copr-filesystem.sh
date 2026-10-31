#!/usr/bin/env bash
# Complete filesystem operations use the owned SDK; no root tree is host-extracted.
public_copr_filesystem() {
    local sdk=$1 archive=$2 filesystem=$3 size=$4 output=$5 guest_tools=$6 host_tools=$7
    [[ ${UKE_COPR_WORKER_AUDIT:-0} == 1 && -f $sdk && ! -L $sdk && -f $archive && ! -L $archive &&
       ! -e $output && ! -L $output && $size =~ ^[1-9][0-9]{3,4}$ && $size -le 65536 ]] || return 1
    local path
    for path in "$sdk" "$archive" "$output" "$host_tools"; do [[ $path =~ ^/[A-Za-z0-9_./+-]+$ ]] || return 1; done
    case $guest_tools in /builder/build-tools|/job/tools-payload/usr/libexec/uke-image-tools) ;; *) return 1;; esac
    local format read_options
    format=$(public_filesystem_format "$filesystem") || return
    read_options=$(public_filesystem_ro_options "$filesystem") || return
    [[ -x $host_tools/android-sparse && ! -L $host_tools/android-sparse ]] || return 1
    mkdir -m700 "$output" || return
    mkdir "$output/cache" "$output/tmp" || return
    export LIBGUESTFS_CACHEDIR=$output/cache LIBGUESTFS_TMPDIR=$output/tmp
    jq -n --arg fs "$filesystem" --arg tools "$guest_tools" --argjson size "$size" \
        '{filesystem:$fs,tools:$tools,size_mib:$size}' > "$output/request.json" || return
    if [[ $filesystem == ext4 ]]; then
        cat > "$output/populate.commands" <<GUEST || return
set-smp 2
set-memsize 2048
set-network false
run
mount /dev/sda /
upload $output/request.json /job/filesystem-request.json
command-out "/usr/bin/bash /builder/src/public/copr-filesystem-entry.sh populate" -
download /job/composed.raw $output/root.raw
rm /job/composed.raw
sync
umount-all
GUEST
        public_copr_guest_run rw "$sdk" "$output/populate.commands" "$output/populate.log" 3600 || return
    else
        truncate -s "${size}M" "$output/root.raw" || return
        cat > "$output/populate.commands" <<GUEST || return
set-smp 2
set-memsize 2048
set-network false
run
$format
mount /dev/sda /
tar-in $archive / xattrs:true selinux:true acls:true
sync
umount-all
GUEST
        public_copr_guest_run rw "$output/root.raw" "$output/populate.commands" "$output/populate.log" 3600 || return
    fi
    [[ $(stat -c %s "$output/root.raw") == "$((size*1024*1024))" ]] || return 1
    sha256sum "$sdk" "$output/root.raw" > "$output/readback-before.sha256" || return
    cat > "$output/read.commands" <<GUEST || return
set-smp 2
set-memsize 2048
set-network false
run
mount-options ro,noload /dev/sda /
mount-options $read_options /dev/sdb /job/filesystem-mount
vfs-type /dev/sdb
vfs-label /dev/sdb
getxattr /job/filesystem-mount/etc/passwd security.selinux
command-out "$guest_tools/ext4-labels verify-tree /job/filesystem-mount /job/filesystem-mount/etc/selinux/targeted/contexts/files/file_contexts" -
tar-out /job/filesystem-mount $output/readback.tar numericowner:true xattrs:true acls:true excludes:lost+found
umount-all
GUEST
    public_copr_guest_run ro "$sdk" "$output/read.commands" "$output/readback.log" 1800 "$output/root.raw" || return
    sha256sum -c "$output/readback-before.sha256" > "$output/readback-hashes.log" || return
    grep -Fxq "$filesystem" "$output/readback.log" || return
    grep -Fxq UKE_LINUX "$output/readback.log" || return
    grep -Eq '^Verified [1-9][0-9]* SELinux tree contexts;' "$output/readback.log" || return
    cat > "$output/compare.commands" <<GUEST || return
set-smp 2
set-memsize 2048
set-network false
run
mount /dev/sda /
upload $output/request.json /job/filesystem-request.json
upload $output/readback.tar /job/filesystem-readback.tar
command-out "/usr/bin/bash /builder/src/public/copr-filesystem-entry.sh compare" -
sync
umount-all
GUEST
    public_copr_guest_run rw "$sdk" "$output/compare.commands" "$output/compare.log" 1800 || return
    "$host_tools/android-sparse" encode "$output/root.raw" "$output/root.img" || return
    "$host_tools/android-sparse" decode "$output/root.img" "$output/decoded.raw" || return
    cmp "$output/root.raw" "$output/decoded.raw" || return
    unlink "$output/decoded.raw" || return
    simg2img "$output/root.img" "$output/aosp.raw" || return
    cmp "$output/root.raw" "$output/aosp.raw" || return
    unlink "$output/aosp.raw" || return
    jq -n --arg fs "$filesystem" --argjson size "$size" \
        '{filesystem:$fs,size_mib:$size,content_readback:true,metadata_readback:true,
          policy_contexts_verified:true,readback_unchanged:true,sparse_roundtrip:true,
          independent_aosp_decoder:true,hardware_tested:false}' > "$output/report.json" || return
    sha256sum "$sdk" "$output/root.raw" "$output/root.img" > "$output/final.sha256" || return
    printf 'UKE_COPR_FILESYSTEM filesystem=%s full_contents=true metadata=true policy_contexts=true readback_unchanged=true sparse_roundtrip=true independent_aosp_decoder=true hardware_tested=false\n' "$filesystem"
}
