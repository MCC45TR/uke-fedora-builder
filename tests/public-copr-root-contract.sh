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
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
mkdir "$work/target" "$work/audit"
jq -n '{device:"uke",architecture:"aarch64",distribution:"fedora",fedora_release:"rawhide",
    channel:"unstable",target:"image",kernel_profile:"normal",desktop:"kde",default_shell:"bash",
    mode:"multiboot",partition:"linux",filesystem:"ext4",size_mib:16384,jobs:2,
    kernel_rpm_request:"7.3.0-60.fc46",kernel_version:"7.3.0",kernel_commit:("a"*40),
    firmware_review_sha256:("b"*64)}' > "$work/request.json"
public_copr_root_request "$work/request.json"
for mutation in '.channel="testing"' '.fedora_release="45"' '.kernel_rpm_request="latest"' \
    '.partition="userdata"' '.size_mib=65537' '.size_mib=8192.5' '.jobs=0' '.kernel_commit="unknown"' \
    '.touch_reference="private"' '.kernel_bundle="local"'; do
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
      rpms:[{path:"rpms/uke/never-downloaded.rpm"}],root_nevras:["never-installed"]}' > "$work/target/manifest.json"
# A refusal must happen before any trust-store, RPM or guest operation.
gpg() { : > "$work/forbidden-operation"; return 97; }
rpmkeys() { : > "$work/forbidden-operation"; return 97; }
mount() { : > "$work/forbidden-operation"; return 97; }
timeout() { : > "$work/forbidden-operation"; return 97; }
if public_copr_root_inputs "$root" "$work/target" "$work/audit" > "$work/refusal.log" 2>&1; then exit 1; fi
grep -Fq 'Complete firmware redistribution evidence is required' "$work/refusal.log"
[[ ! -e $work/forbidden-operation ]]
jq '.metadata_only=true' "$work/target/manifest.json" > "$work/metadata.json"
mv "$work/metadata.json" "$work/target/manifest.json"
if public_copr_root_inputs "$root" "$work/target" "$work/audit" > "$work/refusal.log" 2>&1; then exit 1; fi
[[ ! -e $work/forbidden-operation ]]
if public_guest_mounts; then echo 'Host accepted as a disposable SDK' >&2; exit 1; fi
[[ ! -e $work/forbidden-operation ]]
printf 'ordinary mock file, not a disk image\n' > "$work/mock-disk"
printf 'unexecuted commands\n' > "$work/mock-commands"
printf 'KEEP_LOG\n' > "$work/existing.log"
if UKE_COPR_WORKER_AUDIT=1 public_copr_guest_run rw "$work/mock-disk" "$work/mock-commands" "$work/existing.log" 60; then exit 1; fi
grep -Fxq KEEP_LOG "$work/existing.log"
if UKE_COPR_WORKER_AUDIT=1 public_copr_guest_run invalid "$work/mock-disk" "$work/mock-commands" "$work/new.log" 60; then exit 1; fi
[[ ! -e $work/forbidden-operation && ! -e $work/new.log ]]
echo 'Frozen full-root schema, private/foreign/unpinned request and incomplete-rights/metadata-only/host-mount refusals passed; no guest or target RPM ran.'
