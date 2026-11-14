#!/usr/bin/env bash
# Host-only, native ARM64 original-Fedora tool closure; no source compilation.
# This is a nonbootable userspace archive, not a kernel/initramfs release.
set -Eeuo pipefail
trap 'printf "UKE_SUPER_RUNTIME_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
[[ $# == 2 && $(id -u) == 0 && $(uname -m) == aarch64 && -f /.uke-super-runtime-worker ]]
[[ -d $1 && ! -L $1 && ! -e $2 && ! -L $2 ]]
repo=$(realpath "$1")
output=$(realpath -m "$2")
(( $(df -Pm "$(dirname "$output")" | awk 'NR==2{print $4}') >= 8192 ))
mkdir -m700 "$output"
work=$(mktemp -d /job/super-runtime.XXXXXXXX)
stage=$work/root
mounted=()
cleanup() {
    local status=$? index
    trap - EXIT
    for ((index=${#mounted[@]}-1; index>=0; index--)); do
        umount "${mounted[$index]}" || status=1
    done
    # Never recurse into a retained mount if cleanup failed.
    if findmnt -rn -o TARGET > "$work/mounts" && ! grep -F "$work/" "$work/mounts" >/dev/null; then
        find "$work" -depth -delete
    else
        echo 'Runtime fixture cleanup retained work with an unresolved mount inventory' >&2
        status=1
    fi
    exit "$status"
}
trap cleanup EXIT
mkdir "$work/dracut" "$work/config" "$stage" "$work/fixtures"
mkdir -p "$work/probes/tests" "$work/probes/src"
cp "$repo/tests/"{fastboot-super-runtime,fastboot-super-inspection,fastboot-super-provision-plan}.sh "$work/probes/tests/"
# The fixture's source-shaped path resolves to the installed helper bytes
# inside chroot. It does not lend the worker's tools or full source tree.
ln -s /usr/libexec/uke-super "$work/probes/src/image"
cp -a /usr/lib/dracut/. "$work/dracut/"
module=$work/dracut/modules.d/95uke-super-tools
mkdir "$module"
cp "$repo/src/image/dracut/95uke-super-tools/module-setup.sh" "$module/"
for script in fastboot-singleboot-layout inspect-fastboot-super plan-super-provision provision-fastboot-super map-fastboot-rescue; do
    cp "$repo/src/image/$script.sh" "$module/"
done
chmod 755 "$module/"*.sh
# Only this explicit tools module is selected. No /init or boot services are
# needed for a chroot execution test. A real kernel must supply its own policy.
dracutbasedir="$work/dracut" dracut --conf /dev/null --confdir "$work/config" \
    --tmpdir "$work" --no-hostonly --no-hostonly-cmdline --no-kernel \
    --no-early-microcode --nostrip --gzip --modules uke-super-tools \
    "$work/tools.cpio.gz" 0.0.0-uke-closure > "$output/dracut.log" 2>&1
[[ $(stat -c %s "$work/tools.cpio.gz") -le 67108864 ]]
(cd "$stage"; gzip -cd "$work/tools.cpio.gz" | cpio -idm --quiet --no-absolute-filenames)
[[ ! -e $stage/init && ! -e $stage/usr/bin/python3 ]]
for script in fastboot-singleboot-layout inspect-fastboot-super plan-super-provision provision-fastboot-super map-fastboot-rescue; do
    cmp "$repo/src/image/$script.sh" "$stage/usr/libexec/uke-super/$script.sh"
done
bash "$repo/src/audit/check-target-payload.sh" "$stage" > "$output/python-audit.txt"
bytes=$(du -sb "$stage" | cut -f1)
((bytes <= 268435456))
elf_count=0
find "$stage" -type f -print0 > "$work/regular-files"
while IFS= read -r -d '' file; do
    magic=$(od -An -tx1 -N4 "$file" | tr -d '[:space:]')
    [[ $magic == 7f454c46 ]] || continue
    readelf -h "$file" | grep -E 'Machine:.*AArch64' >/dev/null
    original=/${file#"$stage/"}
    [[ -f $original ]]
    cmp "$original" "$file"
    owner=$(rpm -qf --qf '%{NEVRA}' "$original")
    printf '%s\t%s\t%s\n' "${file#"$stage/"}" "$(sha256sum "$file" | cut -d ' ' -f1)" "$owner" >> "$output/elf-provenance.tsv"
    elf_count=$((elf_count+1))
done < "$work/regular-files"
((elf_count >= 20))
rpm -q dracut android-tools device-mapper e2fsprogs util-linux jq bash coreutils > "$output/original-tools.txt"
sha256sum "$repo/src/image/dracut/95uke-super-tools/module-setup.sh" "$repo/src/image/qualify-super-runtime.sh" \
    "$repo/tests/fastboot-super-runtime.sh" "$repo/tests/fastboot-super-inspection.sh" \
    "$repo/tests/fastboot-super-provision-plan.sh" "$repo/src/audit/check-target-payload.sh" \
    "$repo/src/image/"{fastboot-singleboot-layout,inspect-fastboot-super,plan-super-provision,provision-fastboot-super,map-fastboot-rescue}.sh \
    > "$output/source-sha256.txt"
mkdir -p "$stage/proc" "$stage/dev" "$stage/source" "$stage/work"
[[ -e $stage/dev/null ]] || mknod -m666 "$stage/dev/null" c 1 3
[[ -e $stage/dev/zero ]] || mknod -m666 "$stage/dev/zero" c 1 5
[[ -c $stage/dev/null && -c $stage/dev/zero ]]
mount --bind /proc "$stage/proc"
mounted+=("$stage/proc")
mount -o remount,bind,ro "$stage/proc"
mount --bind "$work/probes" "$stage/source"
mounted+=("$stage/source")
mount -o remount,bind,ro "$stage/source"
mount --bind "$work/fixtures" "$stage/work"
mounted+=("$stage/work")
truncate -s 16M "$work/fixtures/check.ext4"
mke2fs -q -F -t ext4 -b 4096 -L FEDORA_RESCUE "$work/fixtures/check.ext4"
env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C TMPDIR=/work \
    chroot "$stage" /usr/bin/bash /source/tests/fastboot-super-runtime.sh > "$output/native-execution.txt" 2>&1
# Prove that chroot execution really requires the copied library closure.
library=$(find "$stage" -type f -name 'libprotobuf.so.*' -print -quit)
[[ -n $library ]]
mv "$library" "$work/withheld-library"
status=0
env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C chroot "$stage" /usr/bin/lpdump --help \
    > "$output/missing-library.txt" 2>&1 || status=$?
[[ $status != 0 ]] && grep -E 'error while loading shared libraries:.*libprotobuf' "$output/missing-library.txt" >/dev/null
mv "$work/withheld-library" "$library"
jq -n --argjson bytes "$bytes" --argjson elf "$elf_count" --arg hash "$(sha256sum "$work/tools.cpio.gz" | cut -d ' ' -f1)" \
    '{schema_version:1,artifact_kind:"unqualified-native-super-tools-closure",architecture:"aarch64",
      original_fedora_elf_count:$elf,uncompressed_bytes:$bytes,cpio_gzip_sha256:$hash,
      all_elf_bytes_match_rpm_owned_originals:true,no_python_payload:true,
      native_chroot_metadata_fault_and_provision_plan_tests:true,native_ext4_growth_and_swap_file_tools:true,
      missing_library_failure_tested:true,archive_bootable:false,boot_hooks_installed:false,
      physical_device_access_tested:false,kernel_module_closure_tested:false,
      trusted_root_role_integrated:false,crypto_or_resume_integrated:false,
      operating_system_booted:false,final_installable_archive_created:false}' > "$output/runtime-closure.json"
find "$output" -type f -printf '%f\n' | LC_ALL=C sort > "$work/receipt-files"
while IFS= read -r name; do (cd "$output"; sha256sum "$name"); done < "$work/receipt-files" > "$output/SHA256SUMS"
printf 'Native original-Fedora super tool closure passed. No bootable archive or tablet operation.\n'
