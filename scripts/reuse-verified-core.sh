#!/usr/bin/env bash
# Explicit recovery of a frozen core from this repository's manual series only.
# No root payload is executed or modified by this script.
set -Eeuo pipefail
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
: "${GITHUB_REPOSITORY:?}" "${GITHUB_OUTPUT:?}" "${RUNNER_TEMP:?}" "${CORE_RUN_ID:?}"
[[ $GITHUB_REPOSITORY =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $CORE_RUN_ID =~ ^[1-9][0-9]+$ ]]
work=$RUNNER_TEMP/verified-core-reuse
[[ ! -e $work ]]
mkdir -p "$work"
gh api "repos/$GITHUB_REPOSITORY/actions/runs/$CORE_RUN_ID" > "$work/run.json"
jq -e --arg repo "$GITHUB_REPOSITORY" '.repository.full_name==$repo and .event=="workflow_dispatch" and
    .head_branch=="Fedora" and .path==".github/workflows/desktop-images.yml" and .status=="completed" and
    (.head_sha|test("^[0-9a-f]{40}$"))' "$work/run.json" >/dev/null
source=$(jq -er .head_sha "$work/run.json")
gh api "repos/$GITHUB_REPOSITORY/actions/runs/$CORE_RUN_ID/jobs?filter=latest&per_page=100" --paginate --slurp > "$work/jobs.json"
jq -e '[.[].jobs[]|select(.name=="core" and .conclusion=="success")]|length==1' "$work/jobs.json" >/dev/null
gh api "repos/$GITHUB_REPOSITORY/git/trees/$source" > "$work/tree.json"
producer=$(jq -er '.tree[]|select(.path=="uke-fedora-builder" and .mode=="160000")|.sha' "$work/tree.json")
[[ $producer =~ ^[0-9a-f]{40}$ ]]
gh api "repos/$GITHUB_REPOSITORY/actions/runs/$CORE_RUN_ID/artifacts?per_page=100" --paginate --slurp > "$work/artifacts.json"
jq '[.[].artifacts[]|select(.name=="shared-core-internal" and .expired==false)]' "$work/artifacts.json" > "$work/matches.json"
jq -e 'length==1 and (.[0].digest|test("^sha256:[0-9a-f]{64}$"))' "$work/matches.json" >/dev/null
artifact=$(jq -er '.[0].id' "$work/matches.json")
digest=$(jq -er '.[0].digest|sub("^sha256:";"")' "$work/matches.json")
[[ $artifact =~ ^[1-9][0-9]+$ ]]
gh api "repos/$GITHUB_REPOSITORY/actions/artifacts/$artifact/zip" > "$work/core.zip"
[[ $(sha256sum "$work/core.zip" | cut -d ' ' -f1) == "$digest" ]]
[[ $(unzip -Z -1 "$work/core.zip") == core.tar.zst ]]
unzip -p "$work/core.zip" core.tar.zst > "$work/core.tar.zst"
rm "$work/core.zip"
tar --zstd -xOf "$work/core.tar.zst" request.json > "$work/request.json"
tar --zstd -xOf "$work/core.tar.zst" artifacts/core-installed-rpms.tsv > "$work/core-installed-rpms.tsv"
jq -e --arg producer "$producer" --arg kernel "${IMAGE_KERNEL_RPM:-latest}" --argjson size "${IMAGE_SIZE_MIB:-8192}" '
    .builder_commit==$producer and .desktop=="core" and .shared_core_phase=="export" and .target=="image" and
    .architecture=="aarch64" and .distribution=="fedora" and .fedora_release=="rawhide" and .channel=="unstable" and
    .default_shell=="bash" and .mode=="singleboot" and .partition=="userdata" and .filesystem=="ext4" and
    .kernel_profile=="normal" and .kernel_rpm_request==$kernel and .size_mib==$size' "$work/request.json" >/dev/null
# shellcheck source=../src/public/shared-core.sh
# shellcheck disable=SC1091
source "$builder/src/public/shared-core.sh"
public_core_desktop_free "$work/core-installed-rpms.tsv"
core_sha=$(sha256sum "$work/core.tar.zst" | cut -d ' ' -f1)
jq -n --arg source "$source" --arg producer "$producer" --arg run "$CORE_RUN_ID" --arg artifact "$artifact" \
    --arg zip "$digest" --arg core "$core_sha" '{producer_workspace_commit:$source,producer_builder_commit:$producer,
    producer_run_id:$run,artifact_id:$artifact,github_artifact_sha256:$zip,core_archive_sha256:$core,
    desktop_sessions_in_core:false,core_rebuilt:false}' > "$work/core-origin.json"
printf 'Verified frozen core from run %s, workspace %s, builder %s; %s RPM records.\n' \
    "$CORE_RUN_ID" "$source" "$producer" "$(wc -l < "$work/core-installed-rpms.tsv")"
cat "$work/core-installed-rpms.tsv"
printf 'core_archive=%s\nbuild_date=%s\nproducer_builder=%s\nproducer_workspace=%s\nproducer_run_id=%s\ncore_receipts=%s\n' "$work/core.tar.zst" \
    "$(TZ=Europe/Istanbul date +%d%m%y)" "$producer" "$source" "$CORE_RUN_ID" "$work" >> "$GITHUB_OUTPUT"
