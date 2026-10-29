#!/usr/bin/env bash
# Host-only cohort checks. Sources only functions; never activates a boot image.
cohort_identity() {
    local request=$1 info=$2 manifest=$3
    jq -e --slurpfile r "$request" --slurpfile k "$info" '
      ($r[0]) as $r | ($k[0]) as $k |
      ($r.builder_commit | type == "string" and test("^[0-9a-f]{40}$")) and
      ($r.kernel_commit | type == "string" and test("^[0-9a-f]{40}$")) and
      ($r.kernel_version | type == "string" and test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$")) and
      ($k.kernel_release | type == "string" and test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?-[0-9A-Za-z._+]+$")) and
      ($k.kernel_release | startswith($r.kernel_version + "-")) and
      ($k.payload_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
      $k.kernel_source_commit == $r.kernel_commit and $k.kernel_version == $r.kernel_version and
      .builder_commit == $r.builder_commit and .kernel_commit == $r.kernel_commit and
      .kernel_source_commit == $k.kernel_source_commit and .kernel_version == $k.kernel_version and
      .kernel_release == $k.kernel_release and .payload_sha256 == $k.payload_sha256 and
      .partition == $r.partition and .filesystem == $r.filesystem and .mode == $r.mode and
      .target == "image" and $r.target == "image" and
      (.filesystem | IN("ext4", "f2fs", "xfs", "btrfs")) and
      ((.mode == "singleboot" and .partition == "userdata") or
       (.mode == "multiboot" and .partition == "linux"))
    ' "$manifest" >/dev/null
}

# Canonical producer/root byte inventory. Do not parse filenames supplied by a receipt.
cohort_payload_inventory() (
    set -Eeuo pipefail
    local modules=$1
    [[ -d $modules && ! -L $modules ]]
    cd -- "$modules"
    for path in vmlinuz config dtb/qcom/sm7675-xiaomi-uke.dtb; do
        [[ -f $path && ! -L $path ]]
    done
    [[ -d kernel && -d dtb ]]
    [[ -z $(find kernel dtb -type l -print -quit) ]]
    [[ -n $(find kernel -type f -name '*.ko*' -print -quit) ]]
    [[ -z $(find kernel dtb ! -type d ! -type f -print -quit) ]]
    { printf 'vmlinuz\0config\0'; find kernel dtb -type f -print0; } |
        LC_ALL=C sort -z | xargs -0 sha256sum
)

cohort_root_check() {
    # A fresh shell preserves fail-fast behavior even when a caller tests status
    # with if/!; Bash otherwise disables errexit throughout a called function.
    bash "${BASH_SOURCE[0]}" root "$@"
}

cohort_root_check_main() (
    set -Eeuo pipefail
    [[ $# == 6 ]]
    local request=$1 artifacts=$2 root=$3 codec=$4 expected_packages=$5 installed_packages=$6
    local info=$artifacts/kernel/kernel-info.json manifest=$artifacts/manifest.json
    cohort_identity "$request" "$info" "$manifest"
    local release partition filesystem modules bundle scratch hash component nevra expected actual
    release=$(jq -er .kernel_release "$info")
    partition=$(jq -er .partition "$request")
    filesystem=$(jq -er .filesystem "$request")
    modules=$root/usr/lib/modules/$release
    bundle=$root/usr/lib/senemos/kernel-updates/$release
    # This gate is for a fresh image root, not a live system retaining rollback releases.
    [[ $(find "$root/usr/lib/modules" -mindepth 1 -maxdepth 1 -printf '%f\n') == "$release" ]]
    [[ -d $bundle && ! -L $bundle ]]
    [[ -f $artifacts/kernel/payload.sha256 && ! -L $artifacts/kernel/payload.sha256 ]]
    hash=$(sha256sum "$artifacts/kernel/payload.sha256"); hash=${hash%% *}
    [[ $hash == "$(jq -er .payload_sha256 "$info")" ]]
    scratch=$(mktemp -d)
    trap 'rm -rf -- "$scratch"' EXIT
    cohort_payload_inventory "$modules" > "$scratch/payload.sha256"
    cmp "$artifacts/kernel/payload.sha256" "$scratch/payload.sha256"
    # Compare installed package identity to the independently queried producer RPM set.
    for component in '' -core -modules -dtbs -boot; do
        nevra=senemos-uke-linux-kernel-mainline$component-$release.fc46.aarch64
        expected=$(awk -F '\t' -v name="$nevra" '$1==name {print $1 "\t" $2}' "$expected_packages")
        actual=$(awk -F '\t' -v name="$nevra" '$1==name {print $1 "\t" $2}' "$installed_packages")
        [[ -n $expected && $expected != *$'\n'* && $expected == "$actual" && $expected != *$'\t' ]]
        printf '%s\n' "$expected" >> "$scratch/expected-packages"
    done
    if [[ $partition == userdata ]]; then
        nevra=senemos-uke-linux-kernel-mainline-singleboot-$release.fc46.aarch64
        expected=$(awk -F '\t' -v name="$nevra" '$1==name {print $1 "\t" $2}' "$expected_packages")
        actual=$(awk -F '\t' -v name="$nevra" '$1==name {print $1 "\t" $2}' "$installed_packages")
        [[ -n $expected && $expected != *$'\n'* && $expected == "$actual" && $expected != *$'\t' ]]
        printf '%s\n' "$expected" >> "$scratch/expected-packages"
    fi
    LC_ALL=C sort "$scratch/expected-packages" > "$scratch/expected-sorted"
    awk -F '\t' '$1 ~ /^senemos-uke-linux-kernel-mainline-/ {print $1 "\t" $2}' "$installed_packages" |
        LC_ALL=C sort > "$scratch/installed-sorted"
    cmp "$scratch/expected-sorted" "$scratch/installed-sorted"
    [[ $(awk '$1 !~ /^#/ && $2=="/" {print $1 " " $3}' "$root/etc/fstab") == "PARTLABEL=$partition $filesystem" ]]
    for path in "$artifacts/boot.img" "$artifacts/boot-$partition.img" "$bundle/$partition.img"; do
        [[ -f $path && ! -L $path ]]
    done
    cmp "$artifacts/boot.img" "$artifacts/boot-$partition.img"
    cmp "$artifacts/boot.img" "$bundle/$partition.img"
    "$codec" check-root "$artifacts/boot.img" "$partition"
    "$codec" extract "$artifacts/boot.img" "$scratch/Image"
    cmp "$modules/vmlinuz" "$scratch/Image"
    jq -n '{source:"matched-request-and-producer",packages:"matched-producer-rpm-identities",
      kernel_modules_config_dt:"matched-producer-payload-bytes",boot_kernel:"extracted-and-matched",
      root_selector:"matched-fstab",final_filesystem_hashes_verified:false,
      runtime_firmware_compatibility:"unverified",physical_boot_tested:false,rollback_tested:false}'
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -Eeuo pipefail
    [[ $# == 7 && $1 == root ]]
    shift
    cohort_root_check_main "$@"
fi
