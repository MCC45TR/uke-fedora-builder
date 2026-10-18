#!/usr/bin/env bash
# Host-only readback of installed signed RPM bytes; no target program is run.
set -Eeuo pipefail
[[ $# == 3 && -d $1 && -x $2 && ! -e $3 ]]
root=$(realpath "$1") codec=$(realpath "$2") output=$3
release=7.2.10-31
modules=$root/usr/lib/modules/$release
bundle=$root/usr/lib/senemos/kernel-updates/$release
[[ -f $modules/vmlinuz && -f $modules/System.map && -f $bundle/userdata.img ]]
mkdir -p "$output"
"$codec" inspect "$bundle/linux.img" > "$output/linux-header.json"
"$codec" inspect "$bundle/userdata.img" > "$output/userdata-header.json"
"$codec" extract "$bundle/linux.img" "$output/linux.Image"
"$codec" extract "$bundle/userdata.img" "$output/userdata.Image"
cmp "$output/linux.Image" "$modules/vmlinuz"
cmp "$output/userdata.Image" "$modules/vmlinuz"
(cd "$modules"; sha256sum -c "$bundle/modules.sha256") > "$output/modules-readback.log"
symbol() {
    local value
    value=$(awk -v wanted="$1" '$3==wanted {print $1}' "$modules/System.map")
    [[ $value =~ ^[0-9a-f]{16}$ ]]
    printf '%s' "$value"
}
text=$(symbol _text) start=$(symbol __irf_start) end=$(symbol __irf_end)
offset=$((16#$start-16#$text)) length=$((16#$end-16#$start))
[[ $offset -gt 0 && $length -gt 1048576 && $length -lt 67108864 ]]
dd if="$modules/vmlinuz" of="$output/initramfs.cpio.gz" bs=1M iflag=skip_bytes,count_bytes \
    skip="$offset" count="$length" status=none
gzip -t "$output/initramfs.cpio.gz"
gzip -dc "$output/initramfs.cpio.gz" > "$output/initramfs.cpio"
mkdir "$output/initramfs"
(cd "$output/initramfs"; cpio -idm --quiet --no-absolute-filenames < ../initramfs.cpio)
here=$(cd "$(dirname "$0")/.." && pwd)
bash "$here/audit/check-target-payload.sh" "$output/initramfs"
bash "$here/audit/check-target-privacy.sh" "$output/initramfs"
[[ ! -e $output/initramfs/usr/lib/systemd/system/uke-cdc-shell.service ]]
[[ ! -e $output/initramfs/usr/libexec/senemos-local-shell ]]
grep -Fq 'f2fs' "$output/initramfs/usr/libexec/uke-root-guard"
grep -Fxq CONFIG_F2FS_FS=y "$modules/config"
grep -Fxq CONFIG_F2FS_FS_SECURITY=y "$modules/config"
for flag in DEBUG_INFO DEBUG_FS DYNAMIC_DEBUG FTRACE FUNCTION_TRACER KPROBES KASAN UBSAN; do
    if grep -Eq "^CONFIG_$flag=[ym]$" "$modules/config"; then exit 1; fi
done
grep -Fxq CONFIG_DEBUG_INFO_NONE=y "$modules/config"
echo 'Installed Image, both boot containers, every module and extracted early userspace passed host readback.'
