#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# COPR only: public synthetic overlays, never installed board data.
set -Eeuo pipefail
export LC_ALL=C
umask 077
[[ $# == 3 ]] || exit 2
merger=$(realpath "$1")
formatter=$(realpath "$2")
receipt=$(realpath -m "$3")
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
cd "$work"
cat > base.dts <<'DTS'
/dts-v1/;
/ {
    model = "Synthetic base with bootloader-like memory data";
    #address-cells = <1>;
    #size-cells = <1>;
    memory@80000000 { device_type = "memory"; reg = <0x80000000 0x10000000>; };
    reserved-memory {
        #address-cells = <1>;
        #size-cells = <1>;
        ranges;
        region@81000000 { reg = <0x81000000 0x1000>; no-map; };
    };
    soc_root: soc { fixture-base = <1>; };
};
DTS
cat > board.dts <<'DTS'
/dts-v1/;
/plugin/;
/ {
    model = "Synthetic board admission model";
    compatible = "uke,merge-fixture";
    qcom,msm-id = <643 65536>;
    qcom,board-id = <8 0>;
    xiaomi,miboard-id = <11 0>;
    fragment@0 {
        target = <&soc_root>;
        __overlay__ {
            board_node: board {
                board-marker = <1>;
                board-peer = <&board_provider>;
                board_provider: provider { fixture-provider = <11>; };
            };
        };
    };
};
DTS
cat > camera.dts <<'DTS'
/dts-v1/;
/plugin/;
/ {
    model = "Synthetic camera layer";
    qcom,msm-id = <643 65536>;
    qcom,board-id = <8 0>;
    fragment@0 {
        target = <&board_node>;
        __overlay__ {
            camera_node: camera {
                camera-marker = <2>;
                provider = <&camera_provider>;
                board-provider = <&board_provider>;
            };
            camera_provider: camera-provider { fixture-provider = <22>; };
        };
    };
};
DTS
cat > display.dts <<'DTS'
/dts-v1/;
/plugin/;
/ {
    model = "Synthetic display layer";
    qcom,msm-id = <643 65536>;
    qcom,board-id = <8 0>;
    fragment@0 {
        target = <&soc_root>;
        __overlay__ {
            display_node: display { camera-peer = <&camera_node>; display-marker = <3>; };
        };
    };
    fragment@1 { target = <&camera_provider>; __overlay__ { display-vote = <33>; }; };
};
DTS
for name in base board camera display; do
    dtc -@ -I dts -O dtb -o "$name.dtbo" "$name.dts"
done
for output in merged.dtbo repeated.dtbo; do
    # Bound the original producer's retry/allocation behavior independently.
    ( ulimit -Sv 262144; ulimit -Sf 65536; timeout 15s "$merger" -i board.dtbo camera.dtbo display.dtbo -o "$output" )
done
cmp merged.dtbo repeated.dtbo
[[ $(fdtget -t s merged.dtbo / model) == 'Synthetic board admission model' ]]
[[ $(fdtget -t u merged.dtbo / qcom,board-id) == '8 0' ]]
[[ $(fdtget -t u merged.dtbo / qcom,msm-id) == '643 65536' ]]
[[ $(fdtget -t u merged.dtbo / xiaomi,miboard-id) == '11 0' ]]
# An unresolved base symbol must remain for the real bootloader/application.
fdtget -t s merged.dtbo /__fixups__ soc_root > external-fixups.txt
[[ -s external-fixups.txt ]]
fdtoverlay -i base.dtbo -o final-merged.dtb merged.dtbo
fdtoverlay -i base.dtbo -o final-sequential.dtb board.dtbo camera.dtbo display.dtbo
for tree in final-merged.dtb final-sequential.dtb; do
    [[ $(fdtget -t u "$tree" /soc/board board-marker) == 1 ]]
    [[ $(fdtget -t u "$tree" /soc/board/camera camera-marker) == 2 ]]
    [[ $(fdtget -t u "$tree" /soc/display display-marker) == 3 ]]
    [[ $(fdtget -t u "$tree" /soc/board/camera-provider display-vote) == 33 ]]
    [[ $(fdtget -t x "$tree" /soc/board/camera provider) == "$(fdtget -t x "$tree" /soc/board/camera-provider phandle)" ]]
    [[ $(fdtget -t x "$tree" /soc/board/camera board-provider) == "$(fdtget -t x "$tree" /soc/board/provider phandle)" ]]
    [[ $(fdtget -t x "$tree" /soc/board board-peer) == "$(fdtget -t x "$tree" /soc/board/provider phandle)" ]]
    [[ $(fdtget -t x "$tree" /soc/display camera-peer) == "$(fdtget -t x "$tree" /soc/board/camera phandle)" ]]
    [[ $(fdtget -t x "$tree" /memory@80000000 reg) == "$(fdtget -t x base.dtbo /memory@80000000 reg)" ]]
    [[ $(fdtget -t x "$tree" /reserved-memory/region@81000000 reg) == "$(fdtget -t x base.dtbo /reserved-memory/region@81000000 reg)" ]]
done
"$formatter" create merged.img --page_size=4096 --version=0 --id=0 --rev=0 merged.dtbo
[[ $(stat -c %s merged.img) == $(( $(stat -c %s merged.dtbo)+64 )) ]]
# Omitting a required layer must not silently create an applicable image.
status=0
( ulimit -Sv 262144; timeout 15s "$merger" -i board.dtbo display.dtbo -o incomplete.dtbo ) > incomplete.log 2>&1 || status=$?
if [[ $status == 0 ]]; then
    fdtoverlay -i base.dtbo -o incomplete.dtb incomplete.dtbo >> incomplete.log 2>&1 || status=$?
fi
[[ $status != 0 ]]
jq -n --arg arch "$(uname -m)" --arg sha "$(sha256sum "$merger" | cut -d ' ' -f1)" \
    '{schema_version:1,native_architecture:$arch,original_qualcomm_merger:true,merger_sha256:$sha,public_synthetic_inputs_only:true,overlay_layers:3,board_root_metadata_preserved:true,unresolved_base_fixups_preserved:true,cross_layer_phandles_resolved:true,local_phandles_resolved:true,merged_and_sequential_graphs_match:true,synthetic_memory_and_reserved_regions_preserved:true,repeated_merge_identical:true,merged_payload_packed_as_v0:true,missing_layer_application_refused:true,python_executed:false,new_uke_image_produced:false,boot_or_hardware_qualified:false,role_or_key_admitted:false}' > "$receipt"
