#!/usr/bin/env bash
# Host-only EL1/EL2 fixtures; no Uke firmware or device writes.
set -Eeuo pipefail
[[ $# == 1 && -f $1/probe.disk && -f $1/Image && -f $1/SHA256SUMS &&
   ! -e $1/result.json ]] || exit 64
out=$(realpath "$1")
(cd "$out" && sha256sum --check SHA256SUMS)
image_hash=$(sha256sum "$out/Image" | cut -d ' ' -f1)
qemu-system-aarch64 --version > "$out/qemu-version.txt"
vm_pid=''
trap '[[ -z $vm_pid ]] || kill "$vm_pid" 2>/dev/null || true' EXIT
for mode in el1 el2; do
    virt=off expected='{"status":"blocked-no-kvm","guest_ran":false}'
    [[ $mode != el2 ]] || { virt=on; expected='{"status":"kvm-guest-pass","guest_ran":true,"api_version":12}'; }
    qemu-system-aarch64 -machine "virt,gic-version=3,virtualization=$virt,dumpdtb=$out/$mode.dtb" \
        -cpu max -m 1536 -smp 1 -display none -kernel "$out/Image" > "$out/$mode.dtb.log" 2>&1
    fdtput -t s "$out/$mode.dtb" / compatible linux,dummy-virt xiaomi,uke qcom,sm7675
    timeout --signal=TERM --kill-after=5s 180 qemu-system-aarch64 \
        -machine "virt,gic-version=3,virtualization=$virt" -cpu max -accel tcg,thread=single \
        -m 1536 -smp 1 -display none -nic none -monitor none -serial "file:$out/$mode.serial.log" \
        -drive "if=none,file=$out/probe.disk,format=raw,id=root,snapshot=on" \
        -device virtio-blk-pci,drive=root -kernel "$out/Image" -dtb "$out/$mode.dtb" \
        > "$out/$mode.qemu.log" 2>&1 &
    vm_pid=$!
    observed=0
    for ((attempt=0;attempt<170;++attempt)); do
        if grep -F "$expected" "$out/$mode.serial.log" >/dev/null 2>&1; then observed=1; break; fi
        kill -0 "$vm_pid" 2>/dev/null || break
        sleep 1
    done
    kill "$vm_pid" 2>/dev/null || true
    wait "$vm_pid" || true
    vm_pid=''
    ((observed)) || { echo "KVM result missing in $mode fixture; inspect serial log" >&2; exit 1; }
    grep -F "All CPU(s) started at EL${mode#el}" "$out/$mode.serial.log" >/dev/null
    grep -F UKE_FEDORA_EXT4_ROOT_READY "$out/$mode.serial.log" >/dev/null
    grep -F selinux=1 "$out/$mode.serial.log" >/dev/null
done
cat > "$out/result.json" <<JSON
{"schema_version":1,"evidence_class":"generic-arm64-qemu-el1-el2",
 "kernel_sha256":"$image_hash",
 "probe_sha256":"$(sha256sum "$out/uke-kvm-probe" | cut -d ' ' -f1)",
 "test_sha256":"$(sha256sum "$0" | cut -d ' ' -f1)",
 "el1_rejected":true,"el2_guest_ran":true,
 "uke_el2_boot_tested":false,"hardware_tested":false}
JSON
echo 'Emulated EL1 rejection and EL2 KVM guest execution passed; Uke EL2 remains untested'
