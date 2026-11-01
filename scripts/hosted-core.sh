#!/usr/bin/env bash
# Resolve and install the common signed core once. No filesystem or Release upload.
set -Eeuo pipefail
root=$(git rev-parse --show-toplevel)
[[ $(uname -m) == aarch64 && -n ${RUNNER_TEMP:-} && -n ${GITHUB_OUTPUT:-} ]]
case ${IMAGE_SHELL:-bash} in bash|fish|zsh) ;; *) exit 2;; esac
case ${IMAGE_SIZE_MIB:-8192} in 8192|16384) ;; *) exit 2;; esac
export UKE_CONTAINER_ENGINE=docker UKE_SHARED_CORE_PHASE=export
"$root/ukelinux.sh" --build image --mode singleboot --filesystem ext4 \
    --release rawhide --desktop kde --shell "${IMAGE_SHELL:-bash}" --channel unstable \
    --kernel-rpm "${IMAGE_KERNEL_RPM:-latest}" --linux-size "${IMAGE_SIZE_MIB:-8192}" \
    --out "$RUNNER_TEMP/uke-build" --yes
shopt -s nullglob
archives=("$RUNNER_TEMP"/uke-build/image-*/core.tar.zst)
[[ ${#archives[@]} == 1 && -s ${archives[0]} ]]
sha256sum "${archives[0]}" > "$RUNNER_TEMP/core.sha256"
receipts=$RUNNER_TEMP/core-receipts
mkdir -p "$receipts"
job=${archives[0]%/core.tar.zst}
cp "$job/request.json" "$receipts/request.json"
cp "$job/artifacts/core-installed-rpms.tsv" "$receipts/core-installed-rpms.tsv"
producer=$(git -C "$root/uke-fedora-builder" rev-parse HEAD)
workspace=$(git -C "$root" rev-parse HEAD)
jq -n --arg workspace "$workspace" --arg producer "$producer" --arg run "$GITHUB_RUN_ID" \
    --arg sha "$(sha256sum "${archives[0]}" | cut -d ' ' -f1)" '{producer_workspace_commit:$workspace,producer_builder_commit:$producer,
    producer_run_id:$run,core_archive_sha256:$sha,desktop_sessions_in_core:false,core_rebuilt:true}' > "$receipts/core-origin.json"
printf 'core_archive=%s\nbuild_date=%s\nproducer_builder=%s\nproducer_workspace=%s\nproducer_run_id=%s\ncore_receipts=%s\n' \
    "${archives[0]}" "$(TZ=Europe/Istanbul date +%d%m%y)" "$producer" "$workspace" "$GITHUB_RUN_ID" "$receipts" >> "$GITHUB_OUTPUT"
