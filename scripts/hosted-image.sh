#!/usr/bin/env bash
# Called from the immutable uke-linux checkout selected by workflow_dispatch.
set -Eeuo pipefail
root=$(git rev-parse --show-toplevel)
[[ -x $root/ukelinux.sh && $(uname -m) == aarch64 ]]
case ${IMAGE_DESKTOP:-kde} in kde|gnome) ;; *) exit 2;; esac
case ${IMAGE_SHELL:-bash} in bash|fish|zsh) ;; *) exit 2;; esac
case ${IMAGE_CHANNEL:-unstable} in stable|testing|unstable) ;; *) exit 2;; esac
case ${IMAGE_SIZE_MIB:-16384} in 8192|16384) ;; *) exit 2;; esac
build_date=${IMAGE_BUILD_DATE:-$(TZ=Europe/Istanbul date +%d%m%y)}
revision=${IMAGE_REVISION:-0}
[[ $revision =~ ^(0|[1-9][0-9]{0,3})$ && $build_date =~ ^[0-9]{6}$ ]] || exit 2
[[ -n ${RUNNER_TEMP:-} && -n ${GITHUB_OUTPUT:-} && -n ${GITHUB_RUN_ID:-} ]]
output=$RUNNER_TEMP/uke-build
release=$RUNNER_TEMP/uke-release
mkdir -p "$output" "$release"
# Docker is provisioned on the hosted runner. Do not select an unrelated Podman store.
export UKE_CONTAINER_ENGINE=docker
"$root/ukelinux.sh" --build image --mode singleboot --filesystem ext4 \
    --release rawhide --desktop "${IMAGE_DESKTOP:-kde}" --shell "${IMAGE_SHELL:-bash}" \
    --channel "${IMAGE_CHANNEL:-unstable}" --kernel-rpm "${IMAGE_KERNEL_RPM:-latest}" \
    --linux-size "${IMAGE_SIZE_MIB:-16384}" --out "$output" --yes
mapfile -t manifests < <(printf '%s\n' "$output"/image-*/artifacts/manifest.json)
[[ ${#manifests[@]} == 1 && -f ${manifests[0]} ]]
artifacts=${manifests[0]%/manifest.json}
(cd "$artifacts"; sha256sum --check --strict SHA256SUMS)
builder=$root/uke-fedora-builder
bash "$builder/src/public/release-layout.sh" stage "$artifacts" "$release" "$build_date" "$revision"
{
    printf 'workspace %s\n' "$(git -C "$root" rev-parse HEAD)"
    git -C "$root" submodule status --recursive
} > "$release/receipts/SOURCE.txt"
bash "$builder/src/public/release-layout.sh" body "$release" "$release/receipts/images.tsv" > "$release/receipts/RELEASE.md"
tag=$(jq -er .tag "$release/receipts/layout.json")
printf 'release_dir=%s\ntag=%s\n' "$release" "$tag" >> "$GITHUB_OUTPUT"
printf 'Validated image-only release layout: %s\n' "$tag" >> "$GITHUB_STEP_SUMMARY"
