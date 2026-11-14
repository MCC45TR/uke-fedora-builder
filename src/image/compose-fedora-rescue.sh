#!/usr/bin/env bash
# Isolated native AArch64 host assembly from signed RPMs. Never a tablet tool.
set -Eeuo pipefail
trap 'printf "UKE_RESCUE_COMPOSE_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
fail() { printf 'UKE_RESCUE_REJECTED: %s\n' "$*" >&2; exit 1; }
[[ $# == 0 && $(id -u) == 0 && $(uname -m) == aarch64 && -f /job/request.json && -d /cache && -f /.uke-rescue-worker ]] || fail 'expected an isolated native AArch64 root worker'
if [[ -r /proc/device-tree/compatible ]] && grep -aq 'xiaomi,uke' /proc/device-tree/compatible; then fail 'assembly on the tablet is forbidden'; fi
repo=/builder
policy=$repo/configs/images/rescue-rawhide.json
out=/job/artifacts/rescue
root=/job/rescue-root
work=/job/rescue-work
for path in "$out" "$root" "$work"; do [[ ! -e $path && ! -L $path ]] || fail 'owned output must be new'; done
for tool in dnf5 rpm rpmkeys gpg curl jq readelf mke2fs e2fsck debugfs dumpe2fs cpio mount umount; do command -v "$tool" >/dev/null; done
jq -e '.channel=="unstable" and .kernel_profile=="unstable" and .fedora_release=="rawhide" and
  (.kernel_commit|test("^[a-f0-9]{40}$")) and
  (.kernel_rpm_request|test("^7[.]3[.][0-9]+-[1-9][0-9]*[.]fc46$"))' /job/request.json >/dev/null
(( $(df -Pk /job | awk 'NR==2{print $4}') >= 8*1024*1024 )) || fail '8GiB free required, including the operating reserve'
mkdir -p /job/artifacts
mkdir -m700 "$out" "$root" "$work"
mkdir -m0555 "$root/proc"
expected_source=$(jq -er .kernel_commit /job/request.json)
mounted=false
cleanup() {
    local status=$?
    trap - EXIT
    if [[ $mounted == true ]]; then umount "$root/proc" || status=1; fi
    if ((status)); then
        for log in "$work/"*.log; do [[ ! -f $log ]] || tail -n 12 "$log" >&2; done
        for log in "$out/"{units,python,filesystem,selinux}-audit.txt; do
            [[ ! -f $log ]] || { printf '%s\n' "${log##*/}" >&2; tail -n 12 "$log" >&2; }
        done
    fi
    exit "$status"
}
trap cleanup EXIT
# Signature-verified COPR assembly tools and the existing six-RPM cohort gate.
# shellcheck source=../public/repository-tools.sh
# shellcheck disable=SC1091
source "$repo/src/public/repository-tools.sh"
bash "$repo/src/public/repository-kernel.sh"
info=/job/artifacts/kernel/kernel-info.json
jq -e '.kernel_profile=="unstable" and .kernel_rpm_signature=="verified COPR signature" and
  (.kernel_release|endswith("-unstable"))' "$info" >/dev/null
[[ $(jq -er .kernel_source_commit "$info") == "$expected_source" ]] || fail 'kernel source differs from the qualified request'
release=$(jq -er .kernel_release "$info")
evr=$(jq -er '.rpm_version_release+.rpm_dist' "$info")
family=$(jq -er .kernel_family "$info")
fedora_key=$repo/configs/keys/fedora-46.asc
[[ $(gpg --show-keys --with-colons "$fedora_key" | awk -F: '$1=="fpr"{print $10;exit}') == D924B10D3E810DABDD8B56B596E7E91491211FCE ]]
mkdir "$work/repos" "$work/keydb-fedora" "$work/keydb-uke"
rpmkeys --dbpath "$work/keydb-fedora" --import "$fedora_key"
rpmkeys --dbpath "$work/keydb-uke" --import /cache/uke-linux-unstable.asc
cat > "$work/repos/rescue.repo" <<REPO
[rescue-fedora]
name=Original Fedora Rawhide rescue inputs
baseurl=https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Everything/aarch64/os/
enabled=1
gpgcheck=1
gpgkey=file://$fedora_key
skip_if_unavailable=False
[rescue-uke]
name=Signed Uke firmware dependency
baseurl=https://download.copr.fedorainfracloud.org/results/mcc45tr/uke-linux-unstable/fedora-rawhide-aarch64/
enabled=1
gpgcheck=1
gpgkey=file:///cache/uke-linux-unstable.asc
includepkgs=uke-firmware
skip_if_unavailable=False
REPO
packages=()
mapfile -t packages < <(jq -er '.packages[]' "$policy")
kernel_rpms=()
for component in core modules dtbs; do kernel_rpms+=("/job/artifacts/kernel/$family-$component-$evr.aarch64.rpm"); done
dnf=(dnf5 --use-host-config --installroot="$root" --releasever=rawhide
    --setopt="reposdir=$work/repos" --setopt="cachedir=$work/cache" --setopt=keepcache=True
    --setopt=install_weak_deps=False --setopt=tsflags=nodocs --setopt=installonly_limit=0
    --setopt=optional_metadata_types=filelists --setopt=max_parallel_downloads=3
    --setopt=gpgcheck=True --setopt=localpkg_gpgcheck=True
    --setopt='excludepkgs=python*,pypy*,*-debuginfo,*-debugsource,kernel,kernel-core,kernel-modules*')
"${dnf[@]}" -y install --downloadonly "${kernel_rpms[@]}" "${packages[@]}" > "$work/download.log" 2>&1
# Freeze, independently verify and budget the entire solved closure before any
# RPM scriptlet executes in the new root. No repository drift during replay.
find "$work/cache" -type f -name '*.rpm' -print0 > "$work/rpms.list"
rpms=("${kernel_rpms[@]}")
while IFS= read -r -d '' rpm_file; do rpms+=("$rpm_file"); done < "$work/rpms.list"
(( ${#rpms[@]} >= ${#packages[@]} && ${#rpms[@]} <= 256 )) || fail 'unexpected closure size'
installed_bytes=0
: > "$out/packages.tsv"
for archive in "${rpms[@]}"; do
    [[ -f $archive && ! -L $archive ]]
    IFS=$'\t' read -r name arch vendor size nevra < <(rpm -qp --qf $'%{NAME}\t%{ARCH}\t%{VENDOR}\t%{SIZE}\t%{NEVRA}\n' "$archive")
    [[ $arch == aarch64 || $arch == noarch ]]
    [[ $size =~ ^[0-9]+$ ]]
    installed_bytes=$((installed_bytes + size))
    case $name in
        "$family-core"|"$family-modules"|"$family-dtbs"|uke-firmware) keydb=$work/keydb-uke;;
        python*|pypy*|kernel*) fail 'forbidden rescue provider';;
        *) [[ $vendor == 'Fedora Project' ]] || fail 'non-Fedora userspace'; keydb=$work/keydb-fedora;;
    esac
    rpmkeys --dbpath "$keydb" --checksig "$archive" | grep -F 'signatures OK' >/dev/null
    rpm -qpl "$archive" > "$work/files.list"
    if grep -E '(^|/)(python[0-9.]*|pypy[^/]*|libpython[^/]*)(/|$)|[.](py|pyc|pyo|pyz)$' "$work/files.list"; then fail 'Python file in rescue closure'; fi
    printf '%s\t%s\t%s\n' "$nevra" "$(sha256sum "$archive" | cut -d ' ' -f1)" "$size" >> "$out/packages.tsv"
done
((installed_bytes <= 1024*1024*1024)) || fail 'rescue RPM closure exceeds1GiB'
(( $(df -Pk /job | awk 'NR==2{print $4}') >= (installed_bytes*3+2147483648+1023)/1024 )) || fail 'closure exceeds the remaining storage budget'
rpm --root "$root" --initdb
rpm --root "$root" --import "$fedora_key" /cache/uke-linux-unstable.asc
# A fresh proc belongs to this container PID namespace, read-only. No host /dev,
# physical disk, userdata or firmware partition is made available to scriptlets.
mount -t proc -o ro,nosuid,nodev,noexec proc "$root/proc"
mounted=true
# Passed by name to the shared transaction helper.
# shellcheck disable=SC2034
offline_dnf=("${dnf[@]}" --disable-repo='*')
# shellcheck source=../public/root-transaction.sh
# shellcheck disable=SC1091
source "$repo/src/public/root-transaction.sh"
# All resolved local RPMs are exact inputs; the explicit selection remains the
# reviewed package goals, resolved against those local inputs with no repositories.
# shellcheck disable=SC2034
selection=("${packages[@]}")
public_root_transaction "$root" "$work/install.log" offline_dnf rpms selection
umount "$root/proc"
mounted=false
bash "$repo/src/image/configure-fedora-rescue.sh" "$root"
# Documentation is deliberately omitted; required units and executable paths
# remain a strict recursive admission check.
systemd-analyze --root="$root" --man=no --recursive-errors=yes verify rescue.target > "$out/units-audit.txt" 2>&1
bash "$repo/src/audit/check-target-payload.sh" "$root" > "$out/python-audit.txt"
[[ $(find "$root/usr/lib/modules" -mindepth 1 -maxdepth 1 -printf '%f\n') == "$release" ]]
(cd "$root/usr/lib/modules/$release"; sha256sum -c "/job/artifacts/kernel/payload.sha256") > "$out/kernel-payload-audit.txt"
rpm --root "$root" -qa --qf $'%{NEVRA}\n' | LC_ALL=C sort > "$out/installed-nevras.txt"
cut -f1 "$out/packages.tsv" | LC_ALL=C sort -u > "$work/expected-nevras"
grep -v '^gpg-pubkey-' "$out/installed-nevras.txt" > "$work/actual-nevras"
cmp "$work/expected-nevras" "$work/actual-nevras"
# Remove only this fresh root's assembly cache/logs; keep normal RPM ownership.
for path in "$root/var/cache" "$root/var/log"; do find "$path" -mindepth 1 -depth -delete; done
used=$(du -sb "$root" | awk '{print $1}')
image_mib=$((((used + used/4 + 100663296 + 1048575) / 1048576 + 63) / 64 * 64))
minimum=$(jq -er .minimum_image_mib "$policy")
maximum=$(jq -er .maximum_image_mib "$policy")
((image_mib >= minimum)) || image_mib=$minimum
((image_mib <= maximum)) || fail 'populated rescue exceeds its bounded image policy'
image=$out/rescue.ext4
chmod 0755 "$root"
truncate -s "${image_mib}M" "$image"
mke2fs -q -F -t ext4 -b4096 -m1 -L FEDORA_RESCUE \
    -E root_owner=0:0,root_perms=0755,lazy_itable_init=0,lazy_journal_init=0 -d "$root" "$image"
contexts=$root/etc/selinux/targeted/contexts/files/file_contexts
"$UKE_IMAGE_TOOLS/ext4-labels" apply "$image" "$root" "$contexts"
"$UKE_IMAGE_TOOLS/ext4-labels" verify "$image" "$root" "$contexts" > "$out/selinux-audit.txt"
e2fsck -fn "$image" > "$out/filesystem-audit.txt" 2>&1
debugfs -R "dump /etc/fstab $work/readback-fstab" "$image" >/dev/null 2>&1
cmp "$root/etc/fstab" "$work/readback-fstab"
debugfs -R "dump /usr/lib/systemd/systemd $work/readback-systemd" "$image" >/dev/null 2>&1
cmp "$root/usr/lib/systemd/systemd" "$work/readback-systemd"
cp "$info" "$out/kernel-info.json"
sha256sum "$repo/src/image/"{compose-fedora-rescue,configure-fedora-rescue}.sh \
    "$repo/src/public/"{repository-tools,repository-kernel,cohort,root-transaction}.sh \
    "$repo/src/audit/check-target-payload.sh" "$policy" > "$out/source-sha256.txt"
jq -n --slurpfile kernel "$info" --argjson bytes "$((image_mib*1048576))" --arg hash "$(sha256sum "$image" | cut -d ' ' -f1)" \
    --argjson installed "$installed_bytes" --argjson packages "${#rpms[@]}" \
    '{schema_version:1,artifact_kind:"unqualified-fedora-rescue-root",architecture:"aarch64",filesystem:"ext4",
      label:"FEDORA_RESCUE",raw_bytes:$bytes,sha256:$hash,kernel:$kernel[0],rpm_count:$packages,
      installed_rpm_bytes:$installed,original_fedora_userspace:true,signatures_verified:true,
      python_payload_audited:true,matching_kernel_payload_verified:true,ext4_readback_verified:true,
      selinux_labels_verified:true,root_read_only:true,userdata_automount:false,network_enabled:false,
      root_password_locked:true,automatic_repair:false,source_compiled_here:false,
      firmware_or_gpt_written:false,operating_system_boot_tested:false,physical_ufs_tested:false,
      secure_boot_qualified:false,encryption_qualified:false}' > "$out/rescue-composition.json"
printf 'Original Fedora rescue filesystem composed; protected boot, authenticated repair and physical acceptance remain open.\n'
