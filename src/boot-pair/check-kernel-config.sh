#!/usr/bin/env bash
# Host-only ARM64 comparison; all module bytes and exports are checked separately.
set -Eeuo pipefail
[[ $# == 2 && -s $1 && -s $2 ]]
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
for index in 1 2; do
    file=${!index}
    # Early TTY must survive either firmware scanout implementation.
    grep -Fx CONFIG_FRAMEBUFFER_CONSOLE=y "$file" >/dev/null
    grep -Fx '# CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER is not set' "$file" >/dev/null
    if grep -Fx CONFIG_FB_SIMPLE=y "$file" >/dev/null; then
        if grep -Eq '^CONFIG_DRM_SIMPLEDRM=[ym]$' "$file"; then exit 1; fi
    else
        if grep -Eq '^CONFIG_FB_SIMPLE=[ym]$' "$file"; then exit 1; fi
        for required in CONFIG_DRM=y CONFIG_DRM_SIMPLEDRM=y CONFIG_DRM_FBDEV_EMULATION=y CONFIG_DRM_CLIENT_DEFAULT_FBDEV=y; do
            grep -Fx "$required" "$file" >/dev/null
        done
    fi
    # These host probes are inert only in this C-only, debug-info-free ARM64 profile.
    for required in CONFIG_ARM64=y CONFIG_DEBUG_INFO_NONE=y CONFIG_RUSTC_VERSION=0 '# CONFIG_SAMPLES is not set'; do
        grep -Fx "$required" "$file" >/dev/null
    done
    if grep -Eq '^CONFIG_(RUST|DEBUG_INFO|DEBUG_INFO_BTF|DEBUG_INFO_BTF_MODULES|SAMPLES)=[ym]$' "$file"; then exit 1; fi
    grep '^CONFIG_' "$file" | grep -Ev '^CONFIG_(QCOM_UKE_ABL_DT|GUNYAH_WATCHDOG|INITRAMFS_(SOURCE|FORCE|ROOT_UID|ROOT_GID|COMPRESSION_[A-Z0-9_]+)|CMDLINE|CMDLINE_FORCE|CMDLINE_FROM_BOOTLOADER|CC_CAN_LINK|PAHOLE_VERSION)=' | sort > "$scratch/$index"
done
cmp "$scratch/1" "$scratch/2"
echo 'Module configuration matches within the guarded ARM64 boot profile'
