#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/base" <<'CONFIG'
CONFIG_ARM64=y
CONFIG_DEBUG_INFO_NONE=y
CONFIG_RUSTC_VERSION=0
# CONFIG_SAMPLES is not set
CONFIG_CC_CAN_LINK=y
CONFIG_PAHOLE_VERSION=0
CONFIG_CLANG_VERSION=230102
CONFIG_UFS=m
CONFIG_FB_SIMPLE=y
CONFIG_FRAMEBUFFER_CONSOLE=y
# CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER is not set
CONFIG_INITRAMFS_SOURCE=""
CONFIG_CMDLINE=""
CONFIG
check() { bash "$root/src/boot-pair/check-kernel-config.sh" "$fixture/base" "$fixture/boot"; }
reject() { if check >/dev/null 2>&1; then echo 'Unsafe configuration difference accepted' >&2; exit 1; fi; }
sed '/CONFIG_CC_CAN_LINK=/d; s/CONFIG_PAHOLE_VERSION=0/CONFIG_PAHOLE_VERSION=130/; s/CONFIG_INITRAMFS_SOURCE=""/CONFIG_INITRAMFS_SOURCE="fixture.cpio.gz"/; s/CONFIG_CMDLINE=""/CONFIG_CMDLINE="root=PARTLABEL=linux"/' "$fixture/base" > "$fixture/good"
printf 'CONFIG_QCOM_UKE_ABL_DT=y\nCONFIG_GUNYAH_WATCHDOG=y\nCONFIG_INITRAMFS_FORCE=y\nCONFIG_CMDLINE_FORCE=y\n' >> "$fixture/good"
cp "$fixture/good" "$fixture/boot"
check
for change in 'CONFIG_UFS=m/CONFIG_UFS=y' 'CONFIG_CLANG_VERSION=230102/CONFIG_CLANG_VERSION=230103' 'CONFIG_RUSTC_VERSION=0/CONFIG_RUSTC_VERSION=109000' 'CONFIG_DEBUG_INFO_NONE=y/CONFIG_DEBUG_INFO_NONE=n' 'CONFIG_ARM64=y/CONFIG_ARM64=n'; do
    sed "s/$change/" "$fixture/good" > "$fixture/boot"
    reject
done
for enabled in CONFIG_RUST=y CONFIG_DEBUG_INFO=y CONFIG_DEBUG_INFO_BTF=y CONFIG_DEBUG_INFO_BTF_MODULES=y CONFIG_SAMPLES=y; do
    cp "$fixture/good" "$fixture/boot"
    printf '%s\n' "$enabled" >> "$fixture/boot"
    reject
done
grep -v '^CONFIG_DEBUG_INFO_NONE=' "$fixture/good" > "$fixture/boot"
reject
cp "$fixture/base" "$fixture/legacy-base"
cp "$fixture/good" "$fixture/legacy-boot"
sed '/^CONFIG_FB_SIMPLE=/d' "$fixture/legacy-base" > "$fixture/base"
sed '/^CONFIG_FB_SIMPLE=/d' "$fixture/legacy-boot" > "$fixture/boot"
for required in CONFIG_DRM=y CONFIG_DRM_SIMPLEDRM=y CONFIG_DRM_FBDEV_EMULATION=y CONFIG_DRM_CLIENT_DEFAULT_FBDEV=y '# CONFIG_FB_SIMPLE is not set'; do
    printf '%s\n' "$required" | tee -a "$fixture/base" >> "$fixture/boot"
done
check
cp "$fixture/boot" "$fixture/drm-good"
for required in DRM DRM_SIMPLEDRM DRM_FBDEV_EMULATION DRM_CLIENT_DEFAULT_FBDEV FRAMEBUFFER_CONSOLE; do
    sed "s/^CONFIG_$required=y/CONFIG_$required=m/" "$fixture/drm-good" > "$fixture/boot"
    reject
done
cp "$fixture/legacy-base" "$fixture/base"
cp "$fixture/legacy-boot" "$fixture/boot"
printf 'CONFIG_DRM_SIMPLEDRM=m\n' >> "$fixture/base"
printf 'CONFIG_DRM_SIMPLEDRM=m\n' >> "$fixture/boot"
reject
echo 'Tool-probe acceptance and module/compiler/architecture/Rust/BTF refusal: passed'
