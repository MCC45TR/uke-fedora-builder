#!/usr/bin/env bash
# Preserve a completed image when changing only workflow scheduling/publication.
set -Eeuo pipefail
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
: "${GITHUB_REPOSITORY:?}" "${GITHUB_OUTPUT:?}" "${RUNNER_TEMP:?}" "${REUSE_DESKTOP_RUN_ID:?}" "${IMAGE_DESKTOP:?}" "${IMAGE_CORE_SHA:?}" "${IMAGE_BUILD_DATE:?}" "${IMAGE_REVISION:?}"
[[ $GITHUB_REPOSITORY =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $REUSE_DESKTOP_RUN_ID =~ ^[1-9][0-9]+$ && $IMAGE_CORE_SHA =~ ^[0-9a-f]{64}$ ]]
case $IMAGE_DESKTOP in kde|gnome|cutefish|nextkde) ;; *) exit 2;; esac
work=$RUNNER_TEMP/verified-desktop-reuse
[[ ! -e $work ]]
mkdir -p "$work/delivery"
gh api "repos/$GITHUB_REPOSITORY/actions/runs/$REUSE_DESKTOP_RUN_ID" > "$work/run.json"
jq -e --arg repo "$GITHUB_REPOSITORY" '.repository.full_name==$repo and .event=="workflow_dispatch" and
    .head_branch=="Fedora" and .path==".github/workflows/desktop-images.yml" and .status=="completed" and
    (.head_sha|test("^[0-9a-f]{40}$"))' "$work/run.json" >/dev/null
workspace=$(jq -er .head_sha "$work/run.json")
gh api "repos/$GITHUB_REPOSITORY/actions/runs/$REUSE_DESKTOP_RUN_ID/jobs?filter=latest&per_page=100" --paginate --slurp > "$work/jobs.json"
jq -e --arg name "$IMAGE_DESKTOP / compose" '[.[].jobs[]|select(.name==$name and .conclusion=="success")]|length==1' "$work/jobs.json" >/dev/null
gh api "repos/$GITHUB_REPOSITORY/git/trees/$workspace" > "$work/tree.json"
producer=$(jq -er '.tree[]|select(.path=="uke-fedora-builder" and .mode=="160000")|.sha' "$work/tree.json")
[[ $producer =~ ^[0-9a-f]{40}$ ]]
gh api "repos/$GITHUB_REPOSITORY/actions/runs/$REUSE_DESKTOP_RUN_ID/artifacts?per_page=100" --paginate --slurp > "$work/artifacts.json"
jq --arg name "desktop-delivery-$IMAGE_DESKTOP" '[.[].artifacts[]|select(.name==$name and .expired==false)]' "$work/artifacts.json" > "$work/matches.json"
jq -e 'length==1 and (.[0].digest|test("^sha256:[0-9a-f]{64}$"))' "$work/matches.json" >/dev/null
artifact=$(jq -er '.[0].id' "$work/matches.json")
digest=$(jq -er '.[0].digest|sub("^sha256:";"")' "$work/matches.json")
[[ $artifact =~ ^[1-9][0-9]+$ ]]
gh api "repos/$GITHUB_REPOSITORY/actions/artifacts/$artifact/zip" > "$work/delivery.zip"
[[ $(sha256sum "$work/delivery.zip" | cut -d ' ' -f1) == "$digest" ]]
while IFS= read -r path; do
    [[ $path == assets/* || $path == receipts/* ]]
    [[ $path != /* && $path != ../* && $path != *'/../'* && $path != *'/..' ]]
done < <(unzip -Z -1 "$work/delivery.zip")
unzip -q "$work/delivery.zip" -d "$work/delivery"
rm "$work/delivery.zip"
layout=$builder/src/public/release-layout.sh
bash "$layout" verify "$work/delivery"
manifests=("$work/delivery/receipts/images/"*.json)
[[ ${#manifests[@]} == 1 && $(head -n1 "$work/delivery/receipts/SOURCE.txt") == "workspace $workspace" ]]
jq -e --arg desktop "$IMAGE_DESKTOP" --arg producer "$producer" --arg core "$IMAGE_CORE_SHA" \
    '.desktop==$desktop and .builder_commit==$producer and .shared_core_sha256==$core and
    .desktop_isolation_audited==true and .previous_desktop_image_input==false and .fedora_release=="rawhide" and
    .channel=="unstable" and .default_shell=="bash"' "${manifests[0]}" >/dev/null
jq -e --arg date "$IMAGE_BUILD_DATE" --arg revision "$IMAGE_REVISION" '.date==$date and .revision==$revision' "$work/delivery/receipts/layout.json" >/dev/null
jq -n --arg run "$REUSE_DESKTOP_RUN_ID" --arg workspace "$workspace" --arg producer "$producer" \
    --arg artifact "$artifact" --arg sha "$digest" '{producer_run_id:$run,producer_workspace_commit:$workspace,
    producer_builder_commit:$producer,artifact_id:$artifact,github_artifact_sha256:$sha,image_rebuilt:false}' > "$work/delivery/receipts/REUSED-DESKTOP.json"
printf 'Preserved validated %s image from run %s, source %s, builder %s.\n' "$IMAGE_DESKTOP" "$REUSE_DESKTOP_RUN_ID" "$workspace" "$producer"
printf 'release_dir=%s\n' "$work/delivery" >> "$GITHUB_OUTPUT"
