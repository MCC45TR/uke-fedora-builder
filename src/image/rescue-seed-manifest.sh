#!/usr/bin/bash
# Host assembly only: record the original seed geometry inside the rescue root.
set -Eeuo pipefail
[[ $# == 4 && -d $1 && ! -L $1 && -f $3 && ! -L $3 ]]
root=$(realpath "$1");bytes=$2;info=$(realpath "$3");minimum=$4
[[ $root != / && $bytes =~ ^[1-9][0-9]{0,10}$ ]]
here=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=fastboot-singleboot-layout.sh
# shellcheck disable=SC1091
source "$here/fastboot-singleboot-layout.sh"
jq -e '.kernel_profile=="normal" and .kernel_rpm_signature=="verified COPR signature" and
 ((.kernel_repository=="mcc45tr/uke-linux" and (.kernel_release |
   .=="7.4.5-senemos" or test("^7[.]3[.]5-([2-9][0-9]|[1-9][0-9]{2,})$"))) or
  (.kernel_repository=="mcc45tr/uke-linux-unstable" and
   ((.kernel_release|test("^7[.]4[.][1-9][0-9]+-senemos$")) or
    ((.kernel_release|test("^7[.]3[.]5-([2-9][0-9]|[1-9][0-9]{2,})$")) and
     .kernel_release==.rpm_version_release)))) and
 (.kernel_source_commit|test("^[a-f0-9]{40}$"))' "$info" >/dev/null
layout=$(fastboot_seed_layout "$bytes" "$minimum")
for path in usr usr/share usr/share/uke-rescue;do
 [[ ! -L $root/$path && ( ! -e $root/$path || -d $root/$path ) ]]
done
target=$root/usr/share/uke-rescue/seed-layout.json
[[ ! -e $target && ! -L $target ]]
install -d -m0755 "$root/usr/share/uke-rescue"
umask 022
jq -n --argjson layout "$layout" --argjson bytes "$bytes" --slurpfile kernel "$info" \
 '{schema_version:1,kind:"uke-rescue-seed-layout",seed_layout:$layout,
   source_filesystem_bytes:$bytes,kernel_release:$kernel[0].kernel_release,
   kernel_source_commit:$kernel[0].kernel_source_commit,
   layout_is_public_data:true,authorizes_key_release:false,authorizes_resume:false}' > "$target"
chmod 0644 "$target"
