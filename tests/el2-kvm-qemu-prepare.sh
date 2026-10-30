#!/usr/bin/env bash
# Host-only disposable root fixture; never accepts devices or existing outputs.
set -Eeuo pipefail
[[ $# == 3 && -f $1/system.raw.img && -f $1/Image && -f $1/manifest.json &&
   -f $2 && ! -e $3 ]] || exit 64
candidate=$(realpath "$1") probe=$(realpath "$2") out=$(realpath -m "$3")
[[ $out != *\"* && $out != *$'\n'* && $out != *$'\r'* && $out != *\\* ]]
[[ $(od -An -tx1 -N6 "$probe" | tr -d ' \n') == 7f454c460201 &&
   $(od -An -tx1 -j18 -N2 "$probe" | tr -d ' \n') == b700 ]]
grep -Fx CONFIG_KVM=y "$candidate/boot.config" >/dev/null
grep -Fx CONFIG_VIRTUALIZATION=y "$candidate/boot.config" >/dev/null
[[ $(sha256sum "$candidate/Image" | cut -d ' ' -f1) == \
   "$(jq -er .qemu_evidence.result.kernel_sha256 "$candidate/manifest.json")" ]]
[[ $(sha256sum "$candidate/system.raw.img" | cut -d ' ' -f1) == \
   "$(jq -er .sha256.decoded_ext4 "$candidate/manifest.json")" ]]
mkdir -p "$out"
cp --reflink=auto "$candidate/system.raw.img" "$out/probe.ext4"
cp "$candidate/Image" "$out/Image"
cp "$probe" "$out/uke-kvm-probe"
cat > "$out/uke-kvm-probe.service" <<'UNIT'
[Unit]
Description=Disposable emulation-only native KVM guest probe
After=uke-root-status.service

[Service]
Type=oneshot
ExecStart=/usr/bin/uke-kvm-probe
SELinuxContext=system_u:system_r:unconfined_service_t:s0
StandardOutput=tty
StandardError=tty
TTYPath=/dev/ttyAMA0
SuccessExitStatus=2
UNIT
printf 'system_u:object_r:bin_t:s0\0' > "$out/bin.context"
printf 'system_u:object_r:systemd_unit_file_t:s0\0' > "$out/unit.context"
cat > "$out/debugfs.commands" <<EOF
write "$out/uke-kvm-probe" /usr/bin/uke-kvm-probe
set_inode_field /usr/bin/uke-kvm-probe mode 0100755
ea_set -f "$out/bin.context" /usr/bin/uke-kvm-probe security.selinux
write "$out/uke-kvm-probe.service" /etc/systemd/system/uke-kvm-probe.service
ea_set -f "$out/unit.context" /etc/systemd/system/uke-kvm-probe.service security.selinux
symlink /etc/systemd/system/multi-user.target.wants/uke-kvm-probe.service ../uke-kvm-probe.service
EOF
debugfs -w -f "$out/debugfs.commands" "$out/probe.ext4" > "$out/debugfs.log" 2>&1
debugfs -R "dump /usr/bin/uke-kvm-probe \"$out/readback-probe\"" "$out/probe.ext4" >> "$out/debugfs.log" 2>&1
cmp "$out/uke-kvm-probe" "$out/readback-probe"
e2fsck -fn "$out/probe.ext4" > "$out/e2fsck.log" 2>&1
bytes=$(stat -c %s "$out/probe.ext4")
truncate -s "$((bytes + 4*1024*1024))" "$out/probe.disk"
printf 'label: gpt\nunit: sectors\n\nstart=2048,size=%s,type=L,name="linux"\n' "$((bytes / 512))" |
    sfdisk "$out/probe.disk" > "$out/gpt.log"
dd if="$out/probe.ext4" of="$out/probe.disk" bs=1M seek=1 conv=notrunc,sparse status=none
(cd "$out" && sha256sum Image uke-kvm-probe probe.disk > SHA256SUMS)
echo 'Disposable EL2 probe fixture prepared; no Uke storage changed'
