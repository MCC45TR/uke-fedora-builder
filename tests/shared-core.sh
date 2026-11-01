#!/usr/bin/env bash
# Real archive restoration and immutable package checks; no target or container.
set -Eeuo pipefail
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/public/shared-core.sh
# shellcheck disable=SC1091
source "$builder/src/public/shared-core.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/export/artifacts/kernel" "$work/export/original-fedora"
jq -n '{desktop:"core",shared_core_phase:"export",target:"image",fedora_release:"rawhide",channel:"unstable",
    filesystem:"ext4",architecture:"aarch64",mode:"singleboot",partition:"userdata",size_mib:8192,
    default_shell:"bash",builder_commit:("a"*40),kernel_profile:"normal",kernel_rpm_request:"latest",kernel_commit:("b"*40),jobs:2}' > "$work/export/request.json"
jq '. + {credentials_included:false,image_built:false}' "$work/export/request.json" > "$work/export/artifacts/manifest.json"
printf 'owned-root-archive\n' > "$work/export/rootfs.tar"
printf 'signed-original-fedora-bytes\n' > "$work/export/original-fedora/fixture"
printf 'shared-kernel\n' > "$work/export/artifacts/kernel/fixture"
printf 'bash-0:1-1.fc46.aarch64\nlibplasma-0:6-1.fc46.aarch64\nplasma-workspace-common-0:6-1.fc46.aarch64\n' > "$work/export/artifacts/core-installed-rpms.tsv"
public_core_desktop_free "$work/export/artifacts/core-installed-rpms.tsv"
printf 'bash-1\ncommon-1\n' > "$work/baseline"
printf 'bash-1\ncommon-1\ndesktop-1\n' > "$work/installed"
public_core_packages_check "$work/baseline" "$work/installed"
reject() { if (set -Eeuo pipefail; "$@") > "$work/rejected" 2>&1; then echo "Invalid shared core accepted: $*" >&2; exit 1; fi; }
printf 'bash-2\ncommon-1\ndesktop-1\n' > "$work/changed"
reject public_core_packages_check "$work/baseline" "$work/changed"
printf 'bash-1\ndesktop-1\n' > "$work/removed"
reject public_core_packages_check "$work/baseline" "$work/removed"
seal() {
    (cd "$work/export"; find . -type f ! -name core-SHA256SUMS -print0 | sort -z | xargs -0 sha256sum) > "$work/checksums"
    mv "$work/checksums" "$work/export/core-SHA256SUMS"
    # An unprivileged producer cannot read a mode-000 input. Write that mode
    # into this one tar header while retaining readable source fixture bytes.
    tar -cf "$work/core.tar" --mode=000 -C "$work/export" original-fedora/fixture
    tar -rf "$work/core.tar" --exclude='./original-fedora/fixture' -C "$work/export" .
    zstd -q -f "$work/core.tar" -o "$work/core.tar.zst"
}
candidate() {
    mkdir -p "$work/$1/artifacts"
    jq '.desktop="nextkde"|.kernel_commit=("c"*40)|.jobs=4|del(.shared_core_phase)' "$work/export/request.json" > "$work/$1/request.json"
}
seal; candidate good
public_core_restore "$work/core.tar.zst" "$work/good"
jq -e '.desktop=="nextkde" and .shared_core_phase=="import" and .kernel_commit==("b"*40) and .jobs==4' "$work/good/request.json" >/dev/null
jq -e '.desktop=="nextkde" and .image_built==false and (.shared_core_sha256|test("^[0-9a-f]{64}$"))' "$work/good/artifacts/manifest.json" >/dev/null
cmp "$work/export/artifacts/kernel/fixture" "$work/good/artifacts/kernel/fixture"
cmp "$work/export/rootfs.tar" "$work/good/shared-core/rootfs.tar"
cmp "$work/export/original-fedora/fixture" "$work/good/shared-core/original-fedora/fixture"
for desktop in kde gnome cutefish nextkde; do
    candidate "clean-$desktop"
    jq --arg desktop "$desktop" '.desktop=$desktop' "$work/clean-$desktop/request.json" > "$work/next"
    mv "$work/next" "$work/clean-$desktop/request.json"
    public_core_restore "$work/core.tar.zst" "$work/clean-$desktop"
    cmp "$work/export/rootfs.tar" "$work/clean-$desktop/shared-core/rootfs.tar"
done
# A previous desktop work directory cannot alter another clone or the producer.
printf 'KDE-only-mutated-state' > "$work/clean-kde/shared-core/rootfs.tar"
cmp "$work/export/rootfs.tar" "$work/clean-gnome/shared-core/rootfs.tar"
candidate explicit-producer
jq '.builder_commit=("d"*40)' "$work/explicit-producer/request.json" > "$work/next"
mv "$work/next" "$work/explicit-producer/request.json"
public_core_restore "$work/core.tar.zst" "$work/explicit-producer" "$(printf 'a%.0s' {1..40})"
jq -e '.builder_commit==("d"*40) and .shared_core_producer_builder_commit==("a"*40)' "$work/explicit-producer/artifacts/manifest.json" >/dev/null
for desktop in plasma-workspace gnome-shell gnome-initial-setup gdm sddm cutefish-desktop nextkde quickshell uke-kde-plasma-meta; do
    printf '%s-0:1-1.fc46.aarch64\n' "$desktop" > "$work/contaminated"
    reject public_core_desktop_free "$work/contaminated"
done
for key in builder_commit default_shell size_mib mode partition kernel_rpm_request; do
    candidate "$key"
    jq --arg key "$key" '.[$key]="different"' "$work/$key/request.json" > "$work/next"
    mv "$work/next" "$work/$key/request.json"
    reject public_core_restore "$work/core.tar.zst" "$work/$key"
done
printf tampered > "$work/export/rootfs.tar"
tar --zstd -cf "$work/core.tar.zst" -C "$work/export" .
candidate corrupt
reject public_core_restore "$work/core.tar.zst" "$work/corrupt"
echo 'Shared core preserves source identity, rejects corrupt/profile-mismatched archives and forbids package replacement/removal; no target ran.'
