#!/usr/bin/bash
# Read-only inspection of one public rescue file. No root, mount or device access.
set -Eeuo pipefail
export LC_ALL=C
umask 077
fail(){ printf 'UKE_RESCUE_READBACK_REJECTED: %s\n' "$*" >&2;exit 1; }
[[ $# == 3 ]] || fail 'usage: verify-rescue-console.sh RESCUE_EXT4 COMPOSITION_JSON NEW_RECEIPT'
image=$(realpath "$1");composition=$(realpath "$2");receipt=$(realpath -m "$3")
[[ -f $image && ! -L $1 && -f $composition && ! -L $2 &&
   ! -e $receipt && ! -L $3 && -d ${receipt%/*} ]] || fail 'regular inputs and new receipt required'
source_dir=$(cd -- "$(dirname -- "$0")/../src/image" && pwd)
jq -e '.artifact_kind=="unqualified-fedora-rescue-root" and .filesystem=="ext4" and
 .root_password_locked and .signatures_verified and .python_payload_audited and
 .ext4_readback_verified and .selinux_labels_verified and
 (.raw_bytes|type=="number" and .>=536870912 and .<=1073741824) and
 (.sha256|test("^[a-f0-9]{64}$"))' "$composition" >/dev/null || fail 'unqualified rescue composition input differs'
hash=$(sha256sum "$image" | cut -d' ' -f1)
[[ $hash == "$(jq -er .sha256 "$composition")" && $(stat -c %s "$image") == "$(jq -er .raw_bytes "$composition")" ]] || fail 'rescue file differs from the composition receipt'
work=$(mktemp -d /tmp/uke-rescue-readback.XXXXXXXX)
trap 'find "$work" -depth -delete' EXIT
dump(){
 local path=$1 destination=$2 bytes
 debugfs -R "stat $path" "$image" > "$work/stat.txt" 2>&1
 grep -Eq 'Type: regular[[:space:]]+Mode:[[:space:]]+0?[0-7]{3}' "$work/stat.txt" || fail "not a regular rescue file: $path"
 grep -Eq '^User:[[:space:]]+0[[:space:]]+Group:[[:space:]]+0[[:space:]]' "$work/stat.txt" || fail "foreign-owned rescue file: $path"
 bytes=$(awk '/^User:/{for(i=1;i<NF;i++)if($i=="Size:"){n++;value=$(i+1)}}END{if(n!=1)exit 1;print value}' "$work/stat.txt")
 [[ $bytes =~ ^[0-9]+$ && $bytes -le 1048576 ]] || fail "oversized rescue file: $path"
 debugfs -R "dump $path $destination" "$image" > "$work/debugfs.log" 2>&1 || fail 'cannot read rescue filesystem'
 [[ -f $destination && ! -L $destination && $(stat -c %s "$destination") -le 1048576 ]] || fail "missing or oversized rescue file: $path"
}
: > "$work/files.jsonl"
for name in rescue-console-login.sh rescue-admin-policy.sh select-uke-userdata.sh uke-rescue-usb.service uke-rescue-console.service 40-uke-rescue-serial.conf;do
 case $name in
  rescue-console-login.sh) path=/usr/libexec/uke-rescue/console-login;;
  *.sh) path=/usr/libexec/uke-rescue/$name;;
  *.service) path=/etc/systemd/system/$name;;
  *.conf) path=/etc/modprobe.d/$name;;
 esac
 dump "$path" "$work/file"
 mode=644
 [[ $name != rescue-console-login.sh ]] || mode=755
 grep -Eq "Type: regular[[:space:]]+Mode:[[:space:]]+0?$mode([[:space:]]|$)" "$work/stat.txt" || fail "rescue file permissions differ: $path"
 cmp "$source_dir/$name" "$work/file" || fail "rescue differs from the reviewed source: $name"
 jq -n --arg path "$path" --arg sha "$(sha256sum "$work/file" | cut -d' ' -f1)" '{path:$path,sha256:$sha}' >> "$work/files.jsonl"
 unlink "$work/file"
done
dump /etc/shadow "$work/shadow"
awk -F: '$1=="root"{n++;if(NF!=9||$2!~/^[!*]/)bad=1} END{exit n!=1||bad}' "$work/shadow" || fail 'rescue root account is not locked'
dump /etc/passwd "$work/passwd"
awk -F: '$3>=1000&&$3<65534{exit 1}' "$work/passwd" || fail 'rescue includes a human account'
for unit in uke-rescue-usb.service uke-rescue-console.service;do
 debugfs -R "stat /etc/systemd/system/rescue.target.wants/$unit" "$image" > "$work/stat.txt" 2>&1
 grep -Fxq "Fast link dest: \"../$unit\"" "$work/stat.txt" || fail 'rescue activation link differs'
done
# A full pass remains read-only; checking it again also catches accidental writes
# by inspection tools. No debugfs write mode is used anywhere above.
[[ $(sha256sum "$image" | cut -d' ' -f1) == "$hash" ]] || fail 'inspection changed the rescue image'
jq -n --arg hash "$hash" --slurpfile files "$work/files.jsonl" '
 {schema_version:1,artifact_kind:"uke-rescue-console-source-readback",rescue_raw_sha256:$hash,
 source_scripts_verified:true,unit_files_verified:true,locked_root_verified:true,
 human_account_absent:true,activation_links_verified:true,inspection_read_only:true,
 files:$files,password_authentication_tested:false,usb_carrier_tested:false,
 operating_system_boot_tested:false,chroot_repair_tested:false}' > "$receipt"
printf 'Rescue source files, locked root, activation and unchanged image verified; USB boot/authentication remain separate.\n'
