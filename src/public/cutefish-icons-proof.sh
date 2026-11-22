#!/usr/bin/env bash
# Establish icon ownership from the exact installed, independently signed RPM.
public_cutefish_icons_proof() {
    local root=$1 cache=$2 proof=$3 receipt=$4 key=$5 fingerprint=$6 installed archive nevra found=0
    [[ ! -e $proof && ! -L $proof && -d $cache && $fingerprint =~ ^[0-9A-F]{40}$ ]] || return 1
    [[ $(gpg --show-keys --with-colons "$key" | awk -F: '$1=="fpr" {print $10;exit}') == "$fingerprint" ]] || return 1
    installed=$(rpm --root "$root" -q cutefish-icon-theme --qf '%{NEVRA}') || return
    mkdir -p "$proof" "$proof.keydb" || return
    rpmkeys --dbpath "$proof.keydb" --import "$key" || return
    find "$cache" -type f -name 'cutefish-icon-theme-*.rpm' -print0 > "$proof.archives" || return
    while IFS= read -r -d '' archive; do
        [[ $(rpm -qp --qf '%{NAME}' "$archive") == cutefish-icon-theme ]] || continue
        nevra=$(rpm -qp --qf '%{NEVRA}' "$archive")
        [[ $nevra == "$installed" ]] || continue
        rpmkeys --dbpath "$proof.keydb" --checksig "$archive" | grep -F 'signatures OK' || return
        found=$((found + 1))
        [[ $found == 1 ]] || return 1
        rpm --root "$root" -ql cutefish-icon-theme | LC_ALL=C sort > "$proof.owned" || return
        rpm -qpl "$archive" | LC_ALL=C sort > "$proof.packaged" || return
        cmp "$proof.owned" "$proof.packaged" || return
        rpm2cpio "$archive" > "$proof.cpio" || return
        (cd "$proof"; cpio -idmu --quiet --no-absolute-filenames < "$proof.cpio") || return
        printf '%s\t%s\t%s\n' "$nevra" "$(sha256sum "$archive" | cut -d ' ' -f1)" "$fingerprint" > "$receipt"
    done < "$proof.archives"
    [[ $found == 1 && -d $proof/usr/share/icons/Cutefish ]] || return 1
    printf 'Verified Cutefish icon RPM ownership, exact installed NEVRA and independent signature.\n'
}
