#!/usr/bin/env bash
# Schema/refusal checks only; no VM, target RPM, mount or native helper runs.
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../src/public/copr-root-inputs.sh
# shellcheck disable=SC1091
source "$root/src/public/copr-root-inputs.sh"
# shellcheck source=../src/public/guest-runtime.sh
# shellcheck disable=SC1091
source "$root/src/public/guest-runtime.sh"
# shellcheck source=../src/public/copr-sdk.sh
# shellcheck disable=SC1091
source "$root/src/public/copr-sdk.sh"
# shellcheck source=../src/public/root-repository.sh
# shellcheck disable=SC1091
source "$root/src/public/root-repository.sh"
# shellcheck source=../src/public/filesystem-commands.sh
# shellcheck disable=SC1091
source "$root/src/public/filesystem-commands.sh"
# shellcheck source=../src/public/copr-filesystem.sh
# shellcheck disable=SC1091
source "$root/src/public/copr-filesystem.sh"
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
mkdir "$work/target" "$work/audit"
jq -n '{device:"uke",architecture:"aarch64",distribution:"fedora",fedora_release:"rawhide",
    channel:"unstable",target:"image",kernel_profile:"normal",desktop:"kde",default_shell:"bash",
    mode:"multiboot",partition:"linux",filesystem:"ext4",size_mib:16384,jobs:2,
    kernel_rpm_request:"7.3.1-3.fc46",kernel_version:"7.3.1",kernel_commit:("a"*40),
    firmware_review_sha256:("b"*64)}' > "$work/request.json"
public_copr_root_request "$work/request.json"
jq '.kernel_rpm_request="7.3.0-60.fc46"|.kernel_version="7.3.0"' "$work/request.json" > "$work/previous-request.json"
public_copr_root_request "$work/previous-request.json"
for mutation in '.channel="testing"' '.fedora_release="45"' '.kernel_rpm_request="latest"' \
    '.partition="userdata"' '.size_mib=65537' '.size_mib=8192.5' '.jobs=0' '.kernel_commit="unknown"' \
    '.touch_reference="private"' '.kernel_bundle="local"' '.kernel_version="7.3.2"'; do
    jq "$mutation" "$work/request.json" > "$work/invalid.json"
    if public_copr_root_request "$work/invalid.json" > "$work/refusal.log" 2>&1; then exit 1; fi
done
cat > "$work/target/firmware-review.json" <<'JSON'
{"redistribution_review_complete":false,"firmware_blob_package_ready":false,"payload_files":217,"notice_mapped_files":[],"missing_original_notice_paths":74,"unmatched_named_notice_paths":136}
JSON
jq --arg hash "$(sha256sum "$work/target/firmware-review.json" | cut -d ' ' -f1)" \
    '.firmware_review_sha256=$hash' "$work/request.json" > "$work/target/request.json"
: > "$work/target/uke-key.asc"
jq -n --arg hash "$(sha256sum "$work/target/request.json" | cut -d ' ' -f1)" \
    '{schema_version:1,purpose:"full-public-uke-root",metadata_only:false,request_sha256:$hash,
      rpms:[{path:"rpms/uke/never-downloaded.rpm",nevra:"never-installed"}],root_nevras:["never-installed"]}' > "$work/target/manifest.json"
# A refusal must happen before any trust-store, RPM or guest operation.
gpg() { : > "$work/forbidden-operation"; return 97; }
rpmkeys() { : > "$work/forbidden-operation"; return 97; }
mount() { : > "$work/forbidden-operation"; return 97; }
timeout() { : > "$work/forbidden-operation"; return 97; }
if public_copr_root_inputs "$root" "$work/target" "$work/audit" > "$work/refusal.log" 2>&1; then exit 1; fi
grep -Fq 'Complete firmware redistribution evidence is required' "$work/refusal.log"
[[ ! -e $work/forbidden-operation ]]
jq '.rpms += [(.rpms[0]|.path="rpms/uke/different-name.rpm")]' "$work/target/manifest.json" > "$work/duplicate.json"
cp "$work/target/manifest.json" "$work/original-manifest.json"
mv "$work/duplicate.json" "$work/target/manifest.json"
if public_copr_root_inputs "$root" "$work/target" "$work/audit" > "$work/refusal.log" 2>&1; then exit 1; fi
grep -Fq 'duplicate RPM NEVRA' "$work/refusal.log"
[[ ! -e $work/forbidden-operation ]]
cp "$work/original-manifest.json" "$work/target/manifest.json"
jq '.metadata_only=true' "$work/target/manifest.json" > "$work/metadata.json"
mv "$work/metadata.json" "$work/target/manifest.json"
if public_copr_root_inputs "$root" "$work/target" "$work/audit" > "$work/refusal.log" 2>&1; then exit 1; fi
[[ ! -e $work/forbidden-operation ]]
if public_guest_mounts > "$work/host-mount.log" 2>&1; then echo 'Host accepted as a disposable SDK' >&2; exit 1; fi
grep -Fq 'Disposable SDK marker and root are required' "$work/host-mount.log"
[[ ! -e $work/forbidden-operation ]]
printf 'ordinary mock file, not a disk image\n' > "$work/mock-disk"
printf 'unexecuted commands\n' > "$work/mock-commands"
printf 'KEEP_LOG\n' > "$work/existing.log"
if UKE_COPR_WORKER_AUDIT=1 public_copr_guest_run rw "$work/mock-disk" "$work/mock-commands" "$work/existing.log" 60; then exit 1; fi
grep -Fxq KEEP_LOG "$work/existing.log"
if UKE_COPR_WORKER_AUDIT=1 public_copr_guest_run invalid "$work/mock-disk" "$work/mock-commands" "$work/new.log" 60; then exit 1; fi
[[ ! -e $work/forbidden-operation && ! -e $work/new.log ]]
if UKE_COPR_WORKER_AUDIT=1 public_copr_guest_run rw "$work/mock-disk" "$work/mock-commands" "$work/new.log" 60 "$work/mock-disk"; then exit 1; fi
mkdir "$work/mock-tools"
printf '#!/bin/sh\nexit 97\n' > "$work/mock-tools/android-sparse"
chmod +x "$work/mock-tools/android-sparse"
for invalid_request in invalid:1024 ext4:65537; do
    IFS=: read -r filesystem size <<< "$invalid_request"
    # All other inputs satisfy admission. Even a regressed guard cannot start a VM.
    (
        mkdir() { : > "$work/forbidden-operation"; return 97; }
        if UKE_COPR_WORKER_AUDIT=1 public_copr_filesystem "$work/mock-disk" "$work/mock-disk" "$filesystem" "$size" \
            "$work/refused-filesystem" /builder/build-tools "$work/mock-tools"; then exit 1; fi
    )
done
[[ ! -e $work/forbidden-operation && ! -e $work/new.log && ! -e $work/refused-filesystem ]]
mkdir "$work/kept-appliance"
printf 'KEEP_APPLIANCE\n' > "$work/kept-appliance/proof"
(
    export LIBGUESTFS_PATH=KEEP_SEARCH_PATH
    if public_guest_appliance "$work/kept-appliance"; then exit 1; fi
    [[ $LIBGUESTFS_PATH == KEEP_SEARCH_PATH ]]
)
grep -Fxq KEEP_APPLIANCE "$work/kept-appliance/proof"
for project in uke-linux uke-linux-test uke-linux-unstable; do
    public_root_repository "$work/runtime.repo" "$project" rawhide
    grep -Fxq "baseurl=https://download.copr.fedorainfracloud.org/results/mcc45tr/$project/fedora-rawhide-\$basearch/" "$work/runtime.repo"
    grep -Fxq 'gpgcheck=1' "$work/runtime.repo"
done
public_root_repository "$work/worker.repo" uke-linux-unstable rawhide copr-frozen
grep -Fxq 'baseurl=file:///inputs/target/rpms/uke' "$work/worker.repo"
public_root_repository "$work/runtime.repo" uke-linux-unstable rawhide
if grep -Fq '/inputs/' "$work/runtime.repo"; then echo 'Worker repository escaped into runtime' >&2; exit 1; fi
if public_root_repository "$work/invalid.repo" uke-linux-unstable 45; then exit 1; fi
if public_root_repository "$work/invalid.repo" uke-linux-test rawhide copr-frozen; then exit 1; fi
[[ ! -e $work/invalid.repo ]]
echo 'Frozen full-root schema, private/foreign/unpinned request and incomplete-rights/metadata-only/host-mount refusals passed; no guest or target RPM ran.'
