#!/usr/bin/env bash
# Host-only inspection of installed kernel bytes. Never executes target code.
set -Eeuo pipefail
[[ $# == 2 && -d $1 ]] || { echo 'Usage: audit-kernel-inputs.sh EXTRACTED_ROOT REPORT_JSON' >&2; exit 1; }
for tool in jq fdtget grep sha256sum; do command -v "$tool" >/dev/null || exit 1; done
root=$(realpath "$1") report=$2 release=7.2.9-senemos-uke
base=$root/usr/lib/modules/$release
dtb=$base/dtb/qcom/sm7675-xiaomi-uke.dtb
[[ -s $dtb && -s $base/vmlinuz && -s $base/config ]] || { echo 'Matching kernel/config/Uke DTB is missing' >&2; exit 1; }
compatible=$(fdtget -t s "$dtb" / compatible)
[[ " $compatible " == *' xiaomi,uke '* && " $compatible " == *' qcom,sm7675 '* ]] || { echo 'Foreign device tree rejected' >&2; exit 1; }
efi=false ufs_config=false memory=false memory_present=false ufs_node=false usb_node=false cdc_config=false
# A stock memory placeholder with reg=<0 0 0 0> is not a usable RAM bank.
# Inspect cells without overflowing signed Bash arithmetic on 64-bit addresses.
usable_memory_reg() {
    local node=$1 parent=${1%/*} addresses sizes stride offset cell nonzero
    local -a cells
    [[ -n $parent ]] || parent=/
    addresses=$(fdtget -t u "$dtb" "$parent" '#address-cells' 2>/dev/null || printf 2)
    sizes=$(fdtget -t u "$dtb" "$parent" '#size-cells' 2>/dev/null || printf 1)
    [[ $addresses =~ ^[12]$ && $sizes =~ ^[12]$ ]] || return 1
    read -r -a cells < <(fdtget -t x "$dtb" "$node" reg 2>/dev/null) || return 1
    stride=$((addresses + sizes))
    ((${#cells[@]} >= stride && ${#cells[@]} % stride == 0)) || return 1
    for cell in "${cells[@]}"; do [[ $cell =~ ^[a-fA-F0-9]{1,8}$ ]] || return 1; done
    for ((offset=0; offset<${#cells[@]}; offset+=stride)); do
        nonzero=0
        for ((cell=offset+addresses; cell<offset+stride; cell++)); do
            [[ ${cells[cell]} =~ ^0+$ ]] || nonzero=1
        done
        ((nonzero)) || return 1
    done
}
if grep -Fx 'CONFIG_EFI=y' "$base/config" >/dev/null && grep -Fx 'CONFIG_EFI_STUB=y' "$base/config" >/dev/null; then efi=true; fi
if grep -Eq '^CONFIG_SCSI_UFS_QCOM=[ym]$' "$base/config" && grep -Eq '^CONFIG_PHY_QCOM_QMP_UFS=[ym]$' "$base/config"; then ufs_config=true; fi
if grep -Eq '^CONFIG_USB_G_SERIAL=[ym]$' "$base/config" && grep -Eq '^CONFIG_USB_F_ACM=[ym]$' "$base/config"; then cdc_config=true; fi
nodes=(/)
requests='[]'
for ((index=0; index<${#nodes[@]}; index++)); do
    ((${#nodes[@]}<=8192)) || { echo 'Device tree exceeds inspection node limit' >&2; exit 1; }
    node=${nodes[index]}
    status=$(fdtget -t s "$dtb" "$node" status 2>/dev/null || true)
    [[ -z $status || $status == okay || $status == ok ]] || continue
    type=$(fdtget -t s "$dtb" "$node" device_type 2>/dev/null || true)
    if [[ $type == memory ]]; then
        memory_present=true
        if usable_memory_reg "$node"; then memory=true; fi
    fi
    compat=$(fdtget -t s "$dtb" "$node" compatible 2>/dev/null || true)
    if [[ " $compat " == *' qcom,ufshc '* || $compat == *'-ufshc'* || $compat == *'jedec,ufs-'* ]]; then ufs_node=true; fi
    if [[ " $compat " == *' snps,dwc3 '* || " $compat " == *' qcom,sm7675-dwc3 '* ]]; then usb_node=true; fi
    firmware=$(fdtget -t s "$dtb" "$node" firmware-name 2>/dev/null || true)
    if [[ -n $firmware ]]; then
        read -r -a firmware_files <<< "$firmware"
        for path in "${firmware_files[@]}"; do
            requests=$(jq -c --arg path "$path" --arg driver "$compat" --arg node "$node" '.+[{path:$path,driver_compatible:$driver,node:$node,source_profile:"linux-7.2.9"}]' <<< "$requests")
        done
    fi
    while IFS= read -r child; do
        [[ -n $child ]] || continue
        nodes+=("${node%/}/$child")
    done < <(fdtget -l "$dtb" "$node")
done
jq -n --arg image "$(sha256sum "$base/vmlinuz" | cut -d ' ' -f1)" --arg dtb "$(sha256sum "$dtb" | cut -d ' ' -f1)" \
    --arg release "$release" --argjson efi "$efi" --argjson ufscfg "$ufs_config" --argjson memory "$memory" --argjson memory_present "$memory_present" --argjson ufs "$ufs_node" --argjson usb "$usb_node" --argjson cdc "$cdc_config" --argjson requests "$requests" \
    '{schema_version:1,device:"uke",soc:"SM7675",kernel_release:$release,kernel_image_sha256:$image,dtb_sha256:$dtb,efi_configuration:$efi,ufs_configuration:$ufscfg,memory_node_present:$memory_present,static_memory_node:$memory,enabled_ufs_node:$ufs,enabled_usb_dwc3_node:$usb,cdc_acm_configuration:$cdc,requests:$requests,uefi_firmware_accepted:false,geometry_verified:false,boot_tested:false,hardware_tested:false}' > "$report"
[[ $efi == true && $ufs_config == true && $memory == true && $ufs_node == true ]] || { echo 'Uke kernel/DTB boot prerequisites remain incomplete; inspect the report' >&2; exit 2; }
printf '%s\n' 'Kernel/static-DTB inspection passed; independent firmware/geometry acceptance is still required'
