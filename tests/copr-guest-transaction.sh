#!/usr/bin/env bash
# Executes inside the offline COPR appliance, never on the tablet or worker host.
set -Eeuo pipefail
[[ $(id -u) == 0 && -f /inputs/SHA256SUMS && ! -e /job/root ]]
export HOME=/root LANG=C.UTF-8 PATH=/usr/sbin:/usr/bin:/sbin:/bin
source /builder/src/public/root-proc.sh
source /builder/src/public/root-transaction.sh
source /builder/src/public/ext4-filesystem.sh
source /builder/src/public/root-metadata.sh
source /builder/src/public/guest-runtime.sh
mkdir -p /job/root/proc /etc/yum.repos.d /var/cache/dnf /var/lib/rpm /proc /sys /dev /run
# guestfish command chroots into the SDK without preparing virtual filesystems.
# These mounts exist only inside the appliance; no host mount is exposed.
PUBLIC_GUEST_MOUNTS=()
target_proc_mounted=0
guest_cleanup() {
    local status=$?
    if [[ $target_proc_mounted == 1 ]]; then public_root_proc_unmount /job/root || status=1; fi
    public_guest_unmounts || status=1
    if [[ $status != 0 && -f /job/root-install.log ]]; then
        tail -80 /job/root-install.log >&2
    fi
    return "$status"
}
trap guest_cleanup EXIT
public_guest_mounts
bash /builder/tests/copr-guest-runtime.sh
bash /builder/tests/copr-label-tree.sh
if grep -q '^chrony:' /etc/passwd; then echo 'SDK identity contaminated the target proof' >&2; exit 1; fi
sha256sum -c /job/mke2fs.sha256 >&2
[[ $(stat -c '%i' /usr/bin/mke2fs) == "$(stat -c '%i' /usr/bin/mkfs.ext4)" ]]
rpm --initdb
cat > /etc/yum.repos.d/copr-public-fedora.repo <<'REPO'
[copr-public-fedora]
name=Signature-verified public Fedora inputs
baseurl=file:///inputs/rpms
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file:///builder/configs/keys/fedora-46.asc
skip_if_unavailable=False
REPO
# The actual full-image transaction helper runs unmodified. This deliberately
# bounded selection exercises native RPM scriptlets and persistent system IDs.
dnf=(dnf5 --use-host-config --installroot=/job/root --releasever=rawhide
    --disable-repo='*' --enable-repo=copr-public-fedora
    --setopt=install_weak_deps=False --setopt=gpgcheck=True
    --setopt=keepcache=True --setopt=installonly_limit=0 --setopt=tsflags=nodocs)
rpms=()
mapfile -t packages < <(jq -er '.[]' /builder/configs/copr-image-fixture-packages.json)
public_root_proc_mount /job/root
target_proc_mounted=1
public_root_transaction /job/root /job/root-install.log dnf rpms packages
rpm --root /job/root -qa --qf '%{NEVRA}\t%{SOURCERPM}\t%{VENDOR}\n' | LC_ALL=C sort > /job/installed-rpms.tsv
uid=$(awk -F: '$1=="chrony" {print $3}' /job/root/etc/passwd)
gid=$(awk -F: '$1=="chrony" {print $4}' /job/root/etc/passwd)
[[ $uid =~ ^[0-9]+$ && $gid =~ ^[0-9]+$ && $uid != 0 && $gid != 0 ]]
# Fedora declares these directories as ghost entries. Its shipped tmpfiles rule,
# rather than RPM payload extraction, creates them using the installed identities.
/usr/bin/systemd-tmpfiles --root=/job/root --create \
    --prefix=/var/lib/chrony --prefix=/var/log/chrony
[[ $(stat -c '%u:%g' /job/root/var/lib/chrony) == "$uid:$gid" ]]
chroot /job/root /usr/bin/true
jq -n --argjson uid "$uid" --argjson gid "$gid" --argjson count "$(wc -l < /job/installed-rpms.tsv)" \
    '{native_dnf:true,scriptlets:true,dependency_check:true,numeric_owner:true,tmpfiles:true,
      chrony_uid:$uid,chrony_gid:$gid,installed_packages:$count,
      full_os_composition:false,hardware_tested:false}' > /job/report.json
public_root_proc_unmount /job/root
target_proc_mounted=0
for tree in dev proc sys run; do
    if findmnt --mountpoint "/job/root/$tree" --noheadings >/dev/null; then exit 1; fi
    find "/job/root/$tree" -xdev -mindepth 1 -depth -delete
done
# Explicit software fixture metadata; these files are never a product payload.
install -d -m755 /job/root/opt/uke-image-fixture
printf 'UKE_METADATA_READBACK_PROOF\n' > /job/root/opt/uke-image-fixture/data
cp /usr/bin/true /job/root/opt/uke-image-fixture/capability-probe
setcap cap_net_bind_service=ep /job/root/opt/uke-image-fixture/capability-probe
setfacl -m "u:$uid:r--" /job/root/opt/uke-image-fixture/data
setfacl -d -m "u:$uid:r-x" /job/root/opt/uke-image-fixture
archive_metadata() {
    stat -c '%n:%a:%u:%g:%y' /job/root /job/root/var/lib/chrony \
        /job/root/opt/uke-image-fixture{,/data,/capability-probe}
    getfacl -n -p /job/root/opt/uke-image-fixture{,/data}
    getcap -n /job/root/opt/uke-image-fixture/capability-probe
    sha256sum /job/root/opt/uke-image-fixture/{data,capability-probe}
}
archive_metadata > /job/archive-metadata-before.txt
public_root_archive /job/root /job/rootfs.tar /builder/build-tools/ext4-labels
archive_metadata > /job/archive-metadata-after.txt
cmp /job/archive-metadata-before.txt /job/archive-metadata-after.txt
printf '%s\n' 'UKE_COPR_ARCHIVE target_policy_labels=true virtual_roots_included=true metadata_unchanged=true hardware_tested=false'
public_ext4_populate /job/root.raw /job/root 1024 /builder/build-tools/ext4-labels
printf 'KEEP_EXISTING_IMAGE\n' > /job/kept.raw
if public_ext4_populate /job/kept.raw /job/root 1024 /builder/build-tools/ext4-labels; then exit 1; fi
grep -Fxq KEEP_EXISTING_IMAGE /job/kept.raw
ln -s /job/absent-target.raw /job/dangling.raw
if public_ext4_populate /job/dangling.raw /job/root 1024 /builder/build-tools/ext4-labels; then exit 1; fi
[[ ! -e /job/absent-target.raw ]]
if public_ext4_populate /job/oversize.raw /job/root 65537 /builder/build-tools/ext4-labels; then exit 1; fi
[[ ! -e /job/oversize.raw ]]
jq '. + {ext4_populated:true,ext4_policy_labels_verified:true,metadata_fixture:true}' /job/report.json > /job/report.next
mv /job/report.next /job/report.json
