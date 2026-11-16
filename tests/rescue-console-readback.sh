#!/usr/bin/bash
# Thin owned filesystem fixture only; no operating system, compiler or device.
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
root=$work/root
mkdir -p "$root/usr/libexec/uke-rescue" "$root/etc/systemd/system/rescue.target.wants" "$root/etc/modprobe.d"
install -m755 "$repo/src/image/rescue-console-login.sh" "$root/usr/libexec/uke-rescue/console-login"
install -m644 "$repo/src/image/"{rescue-admin-policy,select-uke-userdata}.sh "$root/usr/libexec/uke-rescue/"
install -m644 "$repo/src/image/"uke-rescue-{usb,console}.service "$root/etc/systemd/system/"
install -m644 "$repo/src/image/40-uke-rescue-serial.conf" "$root/etc/modprobe.d/"
for unit in uke-rescue-usb.service uke-rescue-console.service;do
 ln -s "../$unit" "$root/etc/systemd/system/rescue.target.wants/$unit"
done
printf 'root:x:0:0:root:/root:/bin/bash\n' > "$root/etc/passwd"
printf 'root:!:20000:0:99999:7:::\n' > "$root/etc/shadow"
chmod 600 "$root/etc/shadow"
truncate -s512M "$work/rescue.ext4"
mke2fs -q -F -t ext4 -b4096 -L FEDORA_RESCUE -E root_owner=0:0,lazy_itable_init=1 -d "$root" "$work/rescue.ext4"
# mke2fs preserves source ownership. Set only this synthetic file's metadata to
# model a root-built image without requiring host root privileges.
while IFS= read -r path;do
 printf 'set_inode_field /%s uid 0\nset_inode_field /%s gid 0\n' "$path" "$path"
done < <(find "$root" -mindepth 1 -printf '%P\n') > "$work/owners"
debugfs -w -f "$work/owners" "$work/rescue.ext4" > "$work/edit.log" 2>&1
composition(){
 jq -n --arg hash "$(sha256sum "$work/rescue.ext4" | cut -d' ' -f1)" '
 {artifact_kind:"unqualified-fedora-rescue-root",filesystem:"ext4",root_password_locked:true,
 signatures_verified:true,python_payload_audited:true,ext4_readback_verified:true,
 selinux_labels_verified:true,raw_bytes:536870912,sha256:$hash,synthetic_fixture:true}' > "$work/composition.json"
}
verify(){ bash "$repo/scripts/verify-rescue-console.sh" "$work/rescue.ext4" "$work/composition.json" "$1"; }
reject(){
 composition
 if verify "$work/refused.json" > "$work/refused.log" 2>&1;then cat "$work/refused.log";exit 1;fi
 [[ ! -e $work/refused.json ]]
}
composition
verify "$work/valid.json"
jq -e '.source_scripts_verified and .unit_files_verified and .locked_root_verified and (.operating_system_boot_tested|not)' "$work/valid.json" >/dev/null
# Seed assembly grows EXT4 before embedding it. Verify that distinct payload
# against its independently decoded native hash while retaining source identity.
# shellcheck source=../src/image/fastboot-singleboot-layout.sh
# shellcheck disable=SC1091
source "$repo/src/image/fastboot-singleboot-layout.sh"
layout=$(fastboot_super_layout 4294967296 seed)
expanded=$(jq -er '.partitions[]|select(.role=="fedora-live-rescue")|.bytes' <<< "$layout")
cp --sparse=always "$work/rescue.ext4" "$work/grown.ext4"
truncate -s "$expanded" "$work/grown.ext4"
resize2fs "$work/grown.ext4" > "$work/resize.log" 2>&1
jq -n --arg hash "$(sha256sum "$work/grown.ext4" | cut -d' ' -f1)" --argjson layout "$layout" '
 {liblp_three_slot_readback:true,independent_aosp_decode:true,both_logical_payloads_byte_matched:true,
 rescue_full_capacity:true,layout:$layout,rescue_raw_sha256:$hash,
 super_sparse_sha256:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' > "$work/super-composition.json"
bash "$repo/scripts/verify-rescue-console.sh" "$work/grown.ext4" "$work/composition.json" "$work/expanded.json" "$work/super-composition.json"
jq -e --arg source_hash "$(jq -er .sha256 "$work/composition.json")" '.source_rescue_raw_sha256==$source_hash and .rescue_raw_sha256!=$source_hash' "$work/expanded.json" >/dev/null
jq '.rescue_raw_sha256="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' "$work/super-composition.json" > "$work/wrong-expanded.json"
if bash "$repo/scripts/verify-rescue-console.sh" "$work/grown.ext4" "$work/composition.json" "$work/wrong-receipt.json" "$work/wrong-expanded.json" > "$work/refused.log" 2>&1;then exit 1;fi
[[ ! -e $work/wrong-receipt.json ]]
unlink "$work/grown.ext4"
debugfs -w -R 'set_inode_field /etc/systemd/system/uke-rescue-usb.service mode 0100600' "$work/rescue.ext4" > "$work/edit.log" 2>&1
composition
verify "$work/private-unit.json"
debugfs -w -R 'set_inode_field /etc/systemd/system/uke-rescue-usb.service mode 0100644' "$work/rescue.ext4" > "$work/edit.log" 2>&1
debugfs -w -R 'set_inode_field /usr/libexec/uke-rescue/console-login mode 0100644' "$work/rescue.ext4" > "$work/edit.log" 2>&1
reject
debugfs -w -R 'set_inode_field /usr/libexec/uke-rescue/console-login mode 0100755' "$work/rescue.ext4" > "$work/edit.log" 2>&1
printf 'root::20000:0:99999:7:::\n' > "$work/unlocked"
printf 'rm /etc/shadow\nwrite %s /etc/shadow\nset_inode_field /etc/shadow uid 0\nset_inode_field /etc/shadow gid 0\n' "$work/unlocked" > "$work/edit"
debugfs -w -f "$work/edit" "$work/rescue.ext4" > "$work/edit.log" 2>&1
reject
printf 'rm /etc/shadow\nwrite %s /etc/shadow\nset_inode_field /etc/shadow uid 0\nset_inode_field /etc/shadow gid 0\n' "$root/etc/shadow" > "$work/edit"
debugfs -w -f "$work/edit" "$work/rescue.ext4" > "$work/edit.log" 2>&1
printf '[Unit]\nDescription=Wrong fixture unit\n' > "$work/changed"
printf 'rm /etc/systemd/system/uke-rescue-usb.service\nwrite %s /etc/systemd/system/uke-rescue-usb.service\nset_inode_field /etc/systemd/system/uke-rescue-usb.service uid 0\nset_inode_field /etc/systemd/system/uke-rescue-usb.service gid 0\n' "$work/changed" > "$work/edit"
debugfs -w -f "$work/edit" "$work/rescue.ext4" > "$work/edit.log" 2>&1
reject
echo 'Rescue filesystem readback: exact sources, locked account and native-hash-bound EXT4 growth accepted; wrong expanded hash, executable mode, unlocked root and changed unit refused. Synthetic files only; no USB/authentication/OS boot claim.'
