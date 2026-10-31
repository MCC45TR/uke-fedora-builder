#!/usr/bin/env bash
# Complete production root stage, inside the disposable offline SDK only.
set -Eeuo pipefail
[[ $(id -u) == 0 && -f /.uke-copr-sdk && $(< /.uke-copr-sdk) == 1 && ! -e /job/root ]]
export LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH=/usr/sbin:/usr/bin:/sbin:/bin
export UKE_OFFLINE=1 UKE_OUTPUT_OWNER=none UKE_COPR_ROOT_INPUTS=/inputs/target
# shellcheck source=guest-runtime.sh
# shellcheck disable=SC1091
source /builder/src/public/guest-runtime.sh
# shellcheck source=copr-root-inputs.sh
# shellcheck disable=SC1091
source /builder/src/public/copr-root-inputs.sh
exec 3>&2 4>&1
exec > /job/production-root.log 2>&1
# Shared with guest-runtime.sh for cleanup after partial mount failure.
# shellcheck disable=SC2034
PUBLIC_GUEST_MOUNTS=()
cleanup() {
    local status=$?
    public_guest_unmounts || status=1
    if [[ $status == 0 ]]; then cat /job/production-root.log >&4
    else tail -120 /job/production-root.log >&3; fi
    exit "$status"
}
trap cleanup EXIT
mkdir -p /proc /dev /sys /run /cache /etc/yum.repos.d /etc/pki/rpm-gpg /job/artifacts /job/inputs /job/input-audit /job/filesystem-mount
public_guest_mounts
sha256sum -c /job/mke2fs.sha256
rpm --initdb
public_copr_root_inputs /builder /inputs/target /job/input-audit
cp /inputs/target/request.json /job/request.json
cp /inputs/target/uke-key.asc /cache/uke-linux-unstable.asc
mkdir -p /job/artifacts/tools
tools=$(jq -er .build_tools.nevra /builder/configs/public-build.json)
[[ $tools =~ ^uke-image-tools-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.fc46\.aarch64$ ]]
cp "/inputs/target/rpms/uke/$tools.rpm" /job/artifacts/tools/
cat > /etc/yum.repos.d/copr-frozen-fedora.repo <<'REPO'
[copr-frozen-fedora]
name=Frozen signature-verified Fedora image inputs
baseurl=file:///inputs/target/rpms/fedora
enabled=0
gpgcheck=1
gpgkey=file:///builder/configs/keys/fedora-46.asc
skip_if_unavailable=False
REPO
# Reuse all signed kernel/source/module/boot admission and full desktop checks.
bash /builder/src/public/stage.sh repository-kernel
bash /builder/src/public/stage.sh root
awk -F '\t' '$1 !~ /^gpg-pubkey-/ {print $1}' /job/artifacts/installed-rpms.tsv | LC_ALL=C sort > /job/root-installed-nevras.txt
cmp /job/input-audit/target-root-nevras.txt /job/root-installed-nevras.txt
[[ -s /job/rootfs.tar && ! -L /job/rootfs.tar ]]
tar --create --numeric-owner --sort=name -f /job/artifacts.tar -C /job/artifacts .
printf '%s\n' 'UKE_COPR_PRODUCTION_ROOT full_declared_selection=true installed_tuple_matches=true private_inputs=false filesystem_image=false hardware_tested=false'
