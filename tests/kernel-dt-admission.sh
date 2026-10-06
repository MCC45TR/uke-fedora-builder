#!/usr/bin/env bash
# Host-only synthetic DT admission fixtures; no kernel or firmware execution.
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
release=7.2.9-senemos-uke
base=$fixture/root/usr/lib/modules/$release
mkdir -p "$base/dtb/qcom"
printf fixture > "$base/vmlinuz"
cat > "$base/config" <<'CONFIG'
CONFIG_EFI=y
CONFIG_EFI_STUB=y
CONFIG_SCSI_UFS_QCOM=m
CONFIG_PHY_QCOM_QMP_UFS=m
CONFIG_USB_G_SERIAL=m
CONFIG_USB_F_ACM=m
CONFIG
run_case() {
    local name=$1 memory_node=$2 expected=$3 code=0
    cat > "$fixture/$name.dts" <<DTS
/dts-v1/;
/ {
    compatible = "xiaomi,uke", "qcom,sm7675";
    #address-cells = <2>;
    #size-cells = <2>;
    $memory_node
    ufs { compatible = "qcom,ufshc"; };
    usb { compatible = "qcom,sm7675-dwc3"; };
};
DTS
    dtc -q -I dts -O dtb -o "$base/dtb/qcom/sm7675-xiaomi-uke.dtb" "$fixture/$name.dts"
    bash "$root/src/image/audit-kernel-inputs.sh" "$fixture/root" "$fixture/$name.json" > "$fixture/$name.log" 2>&1 || code=$?
    [[ $code == "$expected" ]]
    jq -e '.enabled_ufs_node==true and .enabled_usb_dwc3_node==true and .boot_tested==false and .hardware_tested==false and .uefi_firmware_accepted==false' "$fixture/$name.json" >/dev/null
}
run_case zero 'memory@0 { device_type = "memory"; reg = <0 0 0 0>; };' 2
jq -e '.memory_node_present==true and .static_memory_node==false' "$fixture/zero.json" >/dev/null
run_case missing '' 2
jq -e '.memory_node_present==false and .static_memory_node==false' "$fixture/missing.json" >/dev/null
run_case truncated 'memory@80000000 { device_type = "memory"; reg = <0 0x80000000 0>; };' 2
run_case mixed 'memory@80000000 { device_type = "memory"; reg = <0 0x80000000 0 0x10000000 1 0 0 0>; };' 2
run_case positive 'memory@80000000 { device_type = "memory"; reg = <0 0x80000000 0 0x10000000>; };' 0
jq -e '.static_memory_node==true' "$fixture/positive.json" >/dev/null
run_case high_address 'memory@f000000000000000 { device_type = "memory"; reg = <0xf0000000 0 0 0x10000000>; };' 0
printf '%s\n' 'Zero/missing/truncated RAM rejection and generic UFS/v7 USB inspection fixtures passed; no hardware acceptance'
