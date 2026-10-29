#!/usr/bin/env bash
# Called from the immutable uke-linux checkout selected by workflow_dispatch.
set -Eeuo pipefail
root=$(git rev-parse --show-toplevel)
[[ -x $root/ukelinux.sh && $(uname -m) == aarch64 ]]
case ${IMAGE_DESKTOP:-kde} in kde|gnome) ;; *) exit 2;; esac
case ${IMAGE_SHELL:-bash} in bash|fish|zsh) ;; *) exit 2;; esac
case ${IMAGE_SIZE_MIB:-16384} in 8192|16384) ;; *) exit 2;; esac
[[ -n ${RUNNER_TEMP:-} && -n ${GITHUB_OUTPUT:-} && -n ${GITHUB_RUN_ID:-} ]]
output=$RUNNER_TEMP/uke-build
release=$RUNNER_TEMP/uke-release
mkdir -p "$output" "$release"
# Docker is provisioned on the hosted runner. Do not select an unrelated Podman store.
export UKE_CONTAINER_ENGINE=docker
"$root/ukelinux.sh" --build image --mode singleboot --filesystem ext4 \
    --release rawhide --desktop "${IMAGE_DESKTOP:-kde}" --shell "${IMAGE_SHELL:-bash}" \
    --channel testing --kernel-rpm "${IMAGE_KERNEL_RPM:-latest}" \
    --linux-size "${IMAGE_SIZE_MIB:-16384}" --out "$output" --yes
mapfile -t manifests < <(find "$output" -path '*/artifacts/manifest.json' -type f)
[[ ${#manifests[@]} == 1 ]]
artifacts=${manifests[0]%/manifest.json}
(cd "$artifacts"; sha256sum --check --strict SHA256SUMS)
jq -e '.image_built == true and .mode == "singleboot" and .partition == "userdata" and .filesystem == "ext4" and
    .device_private_data_included == false and .credentials_included == false and .ssh_enabled == false and
    .kernel_rpm_signature == "verified COPR signature" and .kernel_rpms_locally_built == false and
    .filesystem_contents_readback == true and .filesystem_metadata_readback == true and
    .selinux_policy_contexts_verified == true and .independent_aosp_decoder_verified == true and
    .sparse_roundtrip_verified == true and .rpm_transaction_validated == true and .automatic_kernel_activation == false' \
    "$artifacts/manifest.json" >/dev/null
install -m644 "$artifacts/boot.img" "$release/boot.img"
zstd -T0 -10 --check "$artifacts/userdata.img" -o "$release/system.img.zst"
zstd --test "$release/system.img.zst"
actual=$(zstd -dc "$release/system.img.zst" | sha256sum); actual=${actual%% *}
[[ $actual == "$(jq -er .root_sparse_sha256 "$artifacts/manifest.json")" ]]
install -m644 "$artifacts/manifest.json" "$release/manifest.json"
install -m644 "$artifacts/FLASHING.txt" "$release/FLASHING.txt"
install -m644 "$artifacts/installed-rpms.tsv" "$release/installed-rpms.tsv"
install -m644 "$artifacts/kernel/packages.tsv" "$release/kernel-packages.tsv"
install -m644 "$artifacts/kernel/RPM-SHA256SUMS" "$release/kernel-RPM-SHA256SUMS"
{
    printf 'workspace %s\n' "$(git -C "$root" rev-parse HEAD)"
    git -C "$root" submodule status --recursive
} > "$release/SOURCE.txt"
# Hash only the final downloadable files. The sparse image hash is retained in manifest.json.
(cd "$release"; sha256sum boot.img system.img.zst manifest.json FLASHING.txt installed-rpms.tsv kernel-packages.tsv kernel-RPM-SHA256SUMS SOURCE.txt > SHA256SUMS; sha256sum --check --strict SHA256SUMS)
cat > "$release/RELEASE.md" <<TEXT
Fedora Rawhide AArch64 ${IMAGE_DESKTOP:-kde} EXT4 singleboot testing image for Xiaomi Pad 7 / POCO Pad X1.

Built natively on GitHub's ubuntu-24.04-arm runner. Linux $(jq -r .kernel_release "$release/manifest.json") comes from the signature-verified Uke testing repository. Exact sources, RPM identities and host readback results are included in the receipts. No private touch reference or login credentials are included. SSH and automatic kernel activation are disabled.

This is an experimental pre-release. Host checks do not establish tablet boot, charging, first-account setup or recovery acceptance. Provide your own qualified touch reference before touch-based account setup. Firmware redistribution notices and component licenses remain separate from kernel source licensing.

Verify SHA256SUMS, then decompress system.img.zst to userdata.img using zstd -d system.img.zst -o userdata.img. Follow FLASHING.txt only after verifying product=uke, partition capacities, matching firmware and a working recovery route. Flashing userdata deletes Android apps, files and encryption metadata. Preserve stock early firmware and your backups.

Build: https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}
TEXT
tag=prebuild-fedora-${IMAGE_DESKTOP:-kde}-singleboot-ext4-$(date -u +%Y%m%d)-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT:-1}
printf 'release_dir=%s\ntag=%s\n' "$release" "$tag" >> "$GITHUB_OUTPUT"
printf 'Validated release files: %s\n' "$tag" >> "$GITHUB_STEP_SUMMARY"
