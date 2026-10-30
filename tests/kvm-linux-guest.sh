#!/usr/bin/env bash
# ARM64 host acceptance only: RAM guest, no disk/network/passthrough or TCG fallback.
set -Eeuo pipefail
[[ $# == 4 && $(uname -m) == aarch64 && -c /dev/kvm &&
   -f $1 && -f $2 && -x $3 && ! -e $4 ]] || exit 64
kernel=$(realpath "$1") initrd=$(realpath "$2")
probe=$(realpath "$3") out=$(realpath -m "$4")
mkdir -p "$out"
"$probe" > "$out/probe.json" 2> "$out/probe.stderr"
jq -e '.status == "kvm-guest-pass" and .guest_ran == true and .api_version == 12' "$out/probe.json" >/dev/null
qemu-system-aarch64 --version > "$out/qemu-version.txt"
for cpus in 1 2; do
    timeout --signal=TERM --kill-after=5s 90s qemu-system-aarch64 \
        -machine virt,gic-version=3 -accel kvm -cpu host -smp "$cpus" -m 512 \
        -display none -monitor none -nic none -no-reboot \
        -serial "file:$out/guest-$cpus.serial.log" \
        -kernel "$kernel" -initrd "$initrd" \
        -append "console=ttyAMA0 rdinit=/init panic=1 -- $cpus" \
        > "$out/guest-$cpus.qemu.log" 2>&1
    tr -d '\r' < "$out/guest-$cpus.serial.log" > "$out/guest-$cpus.serial.txt"
    grep -Fx "UKE_KVM_LINUX_PASS cpus=$cpus timer=pass migration=pass" "$out/guest-$cpus.serial.txt"
    if grep -F UKE_KVM_LINUX_FAIL "$out/guest-$cpus.serial.txt"; then exit 1; fi
done
jq -n --arg host_kernel "$(uname -r)" \
    --arg kernel_sha256 "$(sha256sum "$kernel" | cut -d ' ' -f1)" \
    --arg initramfs_sha256 "$(sha256sum "$initrd" | cut -d ' ' -f1)" \
    --arg probe_sha256 "$(sha256sum "$probe" | cut -d ' ' -f1)" \
    '{schema_version:1,evidence_class:"arm64-host-kvm-linux-guest",accelerator:"kvm",tcg_fallback:false,
      host_kernel:$host_kernel,kernel_sha256:$kernel_sha256,initramfs_sha256:$initramfs_sha256,
      probe_sha256:$probe_sha256,single_vcpu:true,two_vcpu:true,timer:true,migration:true,
      firmware_ownership_qualified:false,host_peripheral_regressions_qualified:false}' > "$out/result.json"
