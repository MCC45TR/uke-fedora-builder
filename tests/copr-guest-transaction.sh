#!/usr/bin/env bash
# Executes inside the offline COPR appliance, never on the tablet or worker host.
set -Eeuo pipefail
[[ $(id -u) == 0 && -f /inputs/SHA256SUMS && ! -e /job/root ]]
export HOME=/root LANG=C.UTF-8 PATH=/usr/sbin:/usr/bin:/sbin:/bin
source /builder/src/public/root-proc.sh
source /builder/src/public/root-transaction.sh
mkdir -p /job/root/proc /etc/yum.repos.d /var/cache/dnf /var/lib/rpm
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
packages=(bash coreutils systemd chrony)
trap 'public_root_proc_unmount /job/root' EXIT
public_root_proc_mount /job/root
public_root_transaction /job/root /job/root-install.log dnf rpms packages
rpm --root /job/root -qa --qf '%{NEVRA}\t%{SOURCERPM}\t%{VENDOR}\n' | LC_ALL=C sort > /job/installed-rpms.tsv
uid=$(awk -F: '$1=="chrony" {print $3}' /job/root/etc/passwd)
gid=$(awk -F: '$1=="chrony" {print $4}' /job/root/etc/passwd)
[[ $uid =~ ^[0-9]+$ && $gid =~ ^[0-9]+$ && $uid != 0 && $gid != 0 ]]
[[ $(stat -c '%u:%g' /job/root/var/lib/chrony) == "$uid:$gid" ]]
chroot /job/root /usr/bin/true
jq -n --argjson uid "$uid" --argjson gid "$gid" --argjson count "$(wc -l < /job/installed-rpms.tsv)" \
    '{native_dnf:true,scriptlets:true,dependency_check:true,numeric_owner:true,
      chrony_uid:$uid,chrony_gid:$gid,installed_packages:$count,
      full_os_composition:false,hardware_tested:false}' > /job/report.json
public_root_proc_unmount /job/root
trap - EXIT
