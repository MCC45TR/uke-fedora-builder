#!/usr/bin/env bash
# Native host QEMU fixture: no Uke emulation or physical acceptance.
# Run in the pinned QEMU image with candidate read-only and output writable.
set -Eeuo pipefail
[[ $# == 2 && -s $1/Image && -s $1/fedora_boot.img && -s $1/manifest.json && ! -e $2 ]]
candidate=$(realpath "$1") out=$2
mkdir -p "$out/poison/usr/lib/systemd"
cat > "$out/poison/usr/lib/systemd/systemd" <<'SH'
#!/bin/sh
echo EXTERNAL_INITRAMFS_WAS_USED > /dev/console
while :; do sleep 10; done
SH
chmod 755 "$out/poison/usr/lib/systemd/systemd"
(cd "$out/poison"; find . -print0 | sort -z | cpio --null --quiet --reproducible --owner=0:0 -o -H newc) | gzip -n > "$out/external-poison.img"
qemu-system-aarch64 --version > "$out/qemu-version.txt"
qemu-system-aarch64 -machine "virt,gic-version=3,dumpdtb=$out/virt-dump.dtb" -cpu max -m 1536 -smp 1 -display none -kernel "$candidate/Image"
dtc -q -I dtb -O dtb -o "$out/virt.dtb" "$out/virt-dump.dtb"
cp "$out/virt.dtb" "$out/synthetic-identity.dtb"
fdtput -t s "$out/synthetic-identity.dtb" / compatible linux,dummy-virt xiaomi,uke qcom,sm7675
vm_pid=''
trap '[[ -z $vm_pid ]] || kill "$vm_pid" 2>/dev/null || true' EXIT
qmp() {
    printf '%s\n' "$1" >&3
    local response
    IFS= read -r -t 5 response <&3
    # QMP events can precede the response.
    while [[ $response == *'"event"'* ]]; do IFS= read -r -t 5 response <&3; done
    [[ $response == *'"return"'* ]]
}
normalize_serial() {
    local escape=$'\033'
    # systemd's console progress can prefix a shell result with erase-line CSI.
    tr -d '\r' < "$1" | sed -E "s/${escape}\\[[0-?]*[ -/]*[@-~]//g;s/${escape}M//g"
}
for profile in foreign synthetic-identity; do
    dtb=$out/virt.dtb
    [[ $profile != synthetic-identity ]] || dtb=$out/synthetic-identity.dtb
    log=$out/$profile.serial.log
    timeout --signal=TERM --kill-after=5s 180 qemu-system-aarch64 \
        -machine virt,gic-version=3 -cpu max -accel tcg,thread=single -m 1536 -smp 1 \
        -display none -nic none -monitor none -serial "file:$log" \
        -qmp tcp:127.0.0.1:4444,server=on,wait=off \
        -device qemu-xhci,id=xhci -device usb-kbd,bus=xhci.0 \
        -kernel "$candidate/Image" -dtb "$dtb" -initrd "$out/external-poison.img" \
        -append 'rdinit=/usr/lib/systemd/systemd rd.systemd.unit=emergency.target EXTERNAL_CMDLINE_WAS_USED=1' \
        > "$out/$profile.qemu.log" 2>&1 &
    vm_pid=$!
    ready=0
    for ((i=0;i<120;++i)); do
        if [[ -f $log ]] && grep -F debug_mounts_end "$log" >/dev/null; then ready=1; break; fi
        kill -0 "$vm_pid" 2>/dev/null || break
        sleep 1
    done
    ((ready)) || { echo "Built-in debug target did not start: $profile" >&2; exit 1; }
    normalize_serial "$log" > "$out/$profile.status.txt"
    grep -F UKE_BUILTIN_FEDORA_DEBUG_READY "$out/$profile.status.txt" >/dev/null
    grep -F 7.2.9-senemos-uke "$out/$profile.status.txt" >/dev/null
    grep -F rd.systemd.unit=uke-boot-debug.target "$out/$profile.status.txt" >/dev/null
    if grep -E 'EXTERNAL_(INITRAMFS|CMDLINE)_WAS_USED| /sysroot ' "$out/$profile.status.txt"; then exit 1; fi
    exec 3<>/dev/tcp/127.0.0.1/4444
    IFS= read -r -t 5 greeting <&3
    [[ $greeting == *'"QMP"'* ]]
    qmp '{"execute":"qmp_capabilities"}'
    if [[ $profile == foreign ]]; then
        grep -F identity_exit=2 "$out/$profile.status.txt" >/dev/null
        grep -E '(^|: )ActiveState=inactive$' "$out/$profile.status.txt" >/dev/null
        grep -E '(^|: )NRestarts=0$' "$out/$profile.status.txt" >/dev/null
    else
        grep -F identity_exit=0 "$out/$profile.status.txt" >/dev/null
        grep -E '(^|: )ActiveState=active$' "$out/$profile.status.txt" >/dev/null
        qmp '{"execute":"human-monitor-command","arguments":{"command-line":"sendkey ctrl-alt-f2"}}'
        sleep 2
        # echo vmttyok > /dev/ttyAMA0, through the actual VM USB keyboard.
        for key in e c h o spc v m t t y o k spc shift-dot spc slash d e v slash t t y shift-a shift-m shift-a 0 ret; do
            qmp "{\"execute\":\"human-monitor-command\",\"arguments\":{\"command-line\":\"sendkey $key\"}}"
            sleep 0.15
        done
        entered=0
        for ((i=0;i<15;++i)); do
            if normalize_serial "$log" | grep -Fx vmttyok >/dev/null; then entered=1; break; fi
            sleep 1
        done
        ((entered)) || { echo 'Built-in VT2 keyboard command was not observed' >&2; exit 1; }
    fi
    normalize_serial "$log" > "$out/$profile.status.txt"
    # QEMU can close the socket after SHUTDOWN without a final QMP response.
    # Its exit status, checked below, is the shutdown acknowledgement.
    printf '%s\n' '{"execute":"quit"}' >&3
    exec 3>&-
    wait "$vm_pid"; vm_pid=''
    echo "QEMU $profile built-in initramfs, forced command line and debug scope passed"
done
(cd "$out"; sha256sum external-poison.img virt.dtb synthetic-identity.dtb > SHA256SUMS)
# All interpolated values are hexadecimal hashes. Keep the pinned QEMU image
# usable without adding a JSON runtime dependency to this native host fixture.
cat > "$out/result.json" <<JSON
{
  "schema_version": 1,
  "evidence_class": "qemu-virt-fixture",
  "kernel_sha256": "$(sha256sum "$candidate/Image" | cut -d ' ' -f1)",
  "boot_image_sha256": "$(sha256sum "$candidate/fedora_boot.img" | cut -d ' ' -f1)",
  "test_script_sha256": "$(sha256sum "$0" | cut -d ' ' -f1)",
  "external_initramfs_ignored": true,
  "command_line_forced": true,
  "debug_target_started": true,
  "no_sysroot_mount": true,
  "foreign_identity_shell_skipped": true,
  "synthetic_identity_vt2_keyboard_command": true,
  "boot_tested": false,
  "hardware_tested": false
}
JSON
