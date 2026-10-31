#!/usr/bin/env bash
# Full COPR producer: complete root admission precedes all filesystem operations.
set -Eeuo pipefail
[[ ${UKE_COPR_WORKER_AUDIT:-0} == 1 && $# == 4 && -d $1 && -d $2 && -d $3 && ! -e $4 && ! -L $4 ]]
recipe=$(realpath "$1") inputs=$(realpath "$2") target=$(realpath "$3") output=$(realpath -m "$4")
for path in "$recipe" "$inputs" "$target" "$output"; do [[ $path =~ ^/[A-Za-z0-9_./+-]+$ ]]; done
tools=$(jq -er .build_tools.nevra "$recipe/configs/public-build.json")
[[ $tools =~ ^uke-image-tools-1[.]0[.]0-([1-9][0-9]*)[.]fc46[.]aarch64$ && ${BASH_REMATCH[1]} -ge 18 ]]
mkdir -m700 "$output"
bash "$recipe/src/public/copr-root-stage.sh" "$recipe" "$inputs" "$target" "$output/root-stage"
(cd "$output/root-stage" && sha256sum -c root-stage.sha256)
# The SDK remains owned and mutable for the next stage; this receipt is historical.
mv "$output/root-stage/root-stage.sha256" "$output/root-stage/root-stage-before-filesystem.sha256"
mkdir "$output/tools" "$output/artifacts"
# Consume the checked guest outputs, not a caller directory that may have changed.
tar -xf "$output/root-stage/artifacts.tar" -C "$output/artifacts" ./boot.img ./manifest.json ./tools
rpm2cpio "$output/artifacts/tools/$tools.rpm" | (cd "$output/tools" && cpio -idm --quiet --no-absolute-filenames)
host_tools=$output/tools/usr/libexec/uke-image-tools
# shellcheck source=copr-sdk.sh
# shellcheck disable=SC1091
source "$recipe/src/public/copr-sdk.sh"
# shellcheck source=filesystem-commands.sh
# shellcheck disable=SC1091
source "$recipe/src/public/filesystem-commands.sh"
# shellcheck source=copr-filesystem.sh
# shellcheck disable=SC1091
source "$recipe/src/public/copr-filesystem.sh"
filesystem=$(jq -er .filesystem "$output/artifacts/manifest.json")
size=$(jq -er .size_mib "$output/artifacts/manifest.json")
partition=$(jq -er .partition "$output/artifacts/manifest.json")
public_copr_filesystem "$output/root-stage/sdk.raw" "$output/root-stage/rootfs.tar" \
    "$filesystem" "$size" "$output/filesystem" /job/tools-payload/usr/libexec/uke-image-tools "$host_tools"
ln "$output/filesystem/root.img" "$output/artifacts/$partition.img"
jq --slurpfile fs "$output/filesystem/report.json" \
    --arg raw "$(sha256sum "$output/filesystem/root.raw" | cut -d ' ' -f1)" \
    --arg sparse "$(sha256sum "$output/artifacts/$partition.img" | cut -d ' ' -f1)" \
    --arg boot "$(sha256sum "$output/artifacts/boot.img" | cut -d ' ' -f1)" \
    --argjson boot_bytes "$(stat -c %s "$output/artifacts/boot.img")" \
    --argjson bytes "$(stat -c %s "$output/filesystem/root.raw")" \
    '. + {filesystem_verification:$fs[0],root_raw_bytes:$bytes,root_raw_sha256:$raw,
      root_sparse_sha256:$sparse,boot_sha256:$boot,boot_bytes:$boot_bytes,image_built:true,full_os_composition:true,
      filesystem_contents_readback:true,filesystem_metadata_readback:true,
      selinux_relabel_performed:true,selinux_policy_contexts_verified:true,sparse_roundtrip_verified:true,
      independent_aosp_decoder_verified:true,physical_boot_tested:false,hardware_tested:false}' \
    "$output/artifacts/manifest.json" > "$output/manifest.next.json"
mv "$output/manifest.next.json" "$output/artifacts/manifest.json"
(cd "$output/artifacts" && sha256sum boot.img "$partition.img" manifest.json > SHA256SUMS)
sha256sum "$output/root-stage/sdk.raw" "$output/filesystem/root.raw" > "$output/image-stage.sha256"
printf '%s\n' 'Complete declared image composed and independently read back in COPR; physical boot and recovery remain unverified.'
