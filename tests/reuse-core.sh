#!/usr/bin/env bash
# Real ZIP/tar/digest fixtures and a fake read-only Actions API.
set -Eeuo pipefail
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/state/payload/artifacts"
state=$work/state
jq -n '{repository:{full_name:"MCC45TR/fixture"},event:"workflow_dispatch",head_branch:"Fedora",
    path:".github/workflows/desktop-images.yml",status:"completed",head_sha:("a"*40)}' > "$state/run.json"
printf '[{"jobs":[{"name":"core","conclusion":"success"}]}]\n' > "$state/jobs.json"
jq -n '{tree:[{path:"uke-fedora-builder",mode:"160000",sha:("b"*40)}]}' > "$state/tree.json"
jq -n '{builder_commit:("b"*40),desktop:"core",shared_core_phase:"export",target:"image",architecture:"aarch64",
    distribution:"fedora",fedora_release:"rawhide",channel:"unstable",default_shell:"bash",mode:"singleboot",
    partition:"userdata",filesystem:"ext4",kernel_profile:"normal",kernel_rpm_request:"latest",size_mib:8192}' > "$state/payload/request.json"
printf 'bash-0:1-1.fc46.aarch64\nplasma-workspace-common-0:6-1.fc46.aarch64\n' > "$state/payload/artifacts/core-installed-rpms.tsv"
seal() {
    tar --zstd -cf "$state/core.tar.zst" -C "$state/payload" request.json artifacts
    rm -f "$state/core.zip"
    (cd "$state"; zip -q core.zip core.tar.zst)
    jq -n --arg sha "sha256:$(sha256sum "$state/core.zip" | cut -d ' ' -f1)" \
        '[{artifacts:[{id:456,name:"shared-core-internal",expired:false,digest:$sha}]}]' > "$state/artifacts.json"
}
seal
cat > "$work/bin/gh" <<'SH'
#!/bin/bash
set -euo pipefail
[[ $1 == api ]]
case $2 in
 */actions/runs/123) cat "$UKE_CORE_TEST_STATE/run.json";;
 */actions/runs/123/jobs*) cat "$UKE_CORE_TEST_STATE/jobs.json";;
 */git/trees/*) cat "$UKE_CORE_TEST_STATE/tree.json";;
 */actions/runs/123/artifacts*) cat "$UKE_CORE_TEST_STATE/artifacts.json";;
 */actions/artifacts/456/zip) cat "$UKE_CORE_TEST_STATE/core.zip";;
 *) exit 99;;
esac
SH
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" UKE_CORE_TEST_STATE=$state GITHUB_REPOSITORY=MCC45TR/fixture CORE_RUN_ID=123
export GITHUB_OUTPUT=$work/outputs
export RUNNER_TEMP=$work/positive
bash "$builder/scripts/reuse-verified-core.sh" > "$work/positive.log"
cmp "$state/core.tar.zst" "$RUNNER_TEMP/verified-core-reuse/core.tar.zst"
jq -e '.core_rebuilt==false and .producer_builder_commit==("b"*40) and .producer_run_id=="123"' \
    "$RUNNER_TEMP/verified-core-reuse/core-origin.json" >/dev/null
reject() {
    export RUNNER_TEMP=$work/$1
    if bash "$builder/scripts/reuse-verified-core.sh" > "$work/rejected" 2>&1; then echo "Invalid core reuse accepted: $1" >&2; exit 1; fi
}
cp "$state/run.json" "$work/run.valid"
jq '.head_branch="Ubuntu"' "$work/run.valid" > "$state/run.json"
reject wrong-branch
cp "$work/run.valid" "$state/run.json"
printf '[{"jobs":[{"name":"core","conclusion":"failure"}]}]\n' > "$state/jobs.json"
reject failed-producer
printf '[{"jobs":[{"name":"core","conclusion":"success"}]}]\n' > "$state/jobs.json"
cp "$state/artifacts.json" "$work/artifacts.valid"
jq '.[0].artifacts[0].digest="sha256:0000000000000000000000000000000000000000000000000000000000000000"' "$work/artifacts.valid" > "$state/artifacts.json"
reject corrupt-zip
cp "$work/artifacts.valid" "$state/artifacts.json"
jq '.[0].artifacts[0].expired=true' "$work/artifacts.valid" > "$state/artifacts.json"
reject expired-artifact
cp "$work/artifacts.valid" "$state/artifacts.json"
cp "$state/tree.json" "$work/tree.valid"
jq '.tree[0].sha=("c"*40)' "$work/tree.valid" > "$state/tree.json"
reject different-gitlink
cp "$work/tree.valid" "$state/tree.json"
printf 'gnome-shell-0:1-1.fc46.aarch64\n' >> "$state/payload/artifacts/core-installed-rpms.tsv"
seal
reject desktop-contamination
echo 'Frozen-core reuse requires the correct source/job/gitlink/profile/digest and rejects expired, corrupt and desktop-contaminated inputs.'
