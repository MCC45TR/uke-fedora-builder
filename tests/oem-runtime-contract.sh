#!/usr/bin/env bash
# Synthetic regular files only; no OEM bytes, RPM transaction or device access.
set -Eeuo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
project=$work/project root=$work/root
mkdir -p "$project/src/image" "$project/configs/images" "$root/mnt/vendor/persist" "$root/var/lib/uke-touch" "$root/etc"
printf '%s\n' 'PARTLABEL=persist /mnt/vendor/persist ext4 ro,noload,nodev,nosuid,noexec,nofail,x-systemd.device-timeout=10s 0 0' > "$root/etc/fstab"
cp "$repo/src/image/audit-oem-runtime.sh" "$project/src/image/"
printf 'private fixture\n' > "$root/var/lib/uke-touch/reference.bin"
chmod 600 "$root/var/lib/uke-touch/reference.bin"
add_file() {
    local relative=$1 destination=$2 path=$3
    mkdir -p "$root/${relative%/*}"
    printf 'synthetic input\n' > "$root/$relative"
    jq -nc --arg destination "$destination" --arg path "$path" \
        --argjson bytes "$(stat -c %s "$root/$relative")" \
        --arg sha "$(sha256sum "$root/$relative" | cut -d ' ' -f1)" \
        '{target_root:$destination,target_path:$path,bytes:$bytes,sha256:$sha}'
}
{
    add_file usr/share/uke-sensors/odm/present.json sensors odm/present.json
    add_file usr/lib/firmware/qcom/uke/sensors/sns_tppe.so firmware qcom/uke/sensors/sns_tppe.so
    add_file usr/lib/firmware/qca/msnv12.bin firmware qca/msnv12.bin
    add_file var/lib/uke-touch/normal.bin touch-inputs csot/normal.bin
    mkdir -p "$root/usr/lib/firmware/qcom/uke/touch/csot"
    cp "$root/var/lib/uke-touch/normal.bin" "$root/usr/lib/firmware/qcom/uke/touch/csot/normal.bin"
    add_file usr/lib/firmware/qcom/uke/touch/tm/normal.bin touch-inputs tm/normal.bin
    printf 'present.json\nmissing.json\n' > "$root/usr/share/uke-sensors/odm/json.lst"
    jq -nc --argjson bytes "$(stat -c %s "$root/usr/share/uke-sensors/odm/json.lst")" \
      --arg sha "$(sha256sum "$root/usr/share/uke-sensors/odm/json.lst" | cut -d ' ' -f1)" \
      '{target_root:"sensors",target_path:"odm/json.lst",bytes:$bytes,sha256:$sha}'
} | jq -s '{files:.,missing_sensor_configs:["missing.json"]}' > "$work/oem.json"
add_file usr/lib/firmware/adsp.mdt firmware adsp.mdt | jq -s '{files:.}' > "$work/firmware.json"
jq --arg oem "$(sha256sum "$work/oem.json" | cut -d ' ' -f1)" \
   --arg firmware "$(sha256sum "$work/firmware.json" | cut -d ' ' -f1)" \
   '.oem_runtime_inputs.oem_manifest_sha256=$oem | .oem_runtime_inputs.firmware_manifest_sha256=$firmware' \
   "$repo/configs/images/userdata-rawhide.json" > "$project/configs/images/userdata-rawhide.json"
audit() { bash "$project/src/image/audit-oem-runtime.sh" "$root" "$work/oem.json" "$work/firmware.json" "$work/result.json"; }
reject() { if audit > "$work/rejected.log" 2>&1; then echo 'Invalid installed OEM state accepted' >&2; exit 1; fi; }
audit
jq -e '.installed_files_verified==8 and .active_inputs_verified==6 and .packaged_touch_assets_verified==2 and .hardware_tested==false and .missing_sensor_configs==["missing.json"]' "$work/result.json" >/dev/null
target=$root/usr/lib/firmware/qcom/uke/sensors/sns_tppe.so
printf 'tamper\n' >> "$target"; reject
printf 'synthetic input\n' > "$target"
mv "$target" "$work/outside"
ln -s "$work/outside" "$target"; reject
rm "$target"; mv "$work/outside" "$target"
chmod 644 "$root/var/lib/uke-touch/reference.bin"; reject
chmod 600 "$root/var/lib/uke-touch/reference.bin"
touch "$root/usr/share/uke-sensors/odm/missing.json"; reject
rm "$root/usr/share/uke-sensors/odm/missing.json"
cp "$root/etc/fstab" "$work/fstab"
sed -i 's/ro,noload/rw,noload/' "$root/etc/fstab"; reject
cp "$work/fstab" "$root/etc/fstab"
printf '\n' >> "$work/oem.json"; reject
echo 'Installed OEM inputs: valid profile passes; changed bytes, symlink, private modes, unexpected list closure and manifest tamper reject.'
