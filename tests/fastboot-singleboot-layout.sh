#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/image/fastboot-singleboot-layout.sh
# shellcheck disable=SC1091
source "$root/src/image/fastboot-singleboot-layout.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
[[ $(fastboot_install_name 141126) == fedora-rawhide-linux-kde-plasma-uke-senemos-sbfb-141126.zip ]]
[[ $(fastboot_install_name 290228) == fedora-rawhide-linux-kde-plasma-uke-senemos-sbfb-290228.zip ]]
for invalid in 310226 290227 000126 141326 14112026 abcdef; do
    if fastboot_install_name "$invalid" >/dev/null 2>&1; then printf 'Invalid date accepted: %s\n' "$invalid" >&2; exit 1; fi
done
# Check varied, nonuniform device capacities rather than pinning one tablet size.
for capacity in 4294967296 8321499136 8589934592 9126805504 11274289152 12884901888 17179869184 11274289664; do
    fastboot_super_layout "$capacity" > "$work/layout.json"
    jq -e --argjson size "$capacity" '.super_bytes == $size and .opt_partition == false and
      .partition_table_changes == false and
      ([.partitions[].bytes] | add) == .usable_payload_bytes and
      (.partitions | length) == 2 and
      .partitions[0].name == "system_a" and .partitions[0].label == "linux_swap" and
      .partitions[1].name == "system_b" and .partitions[1].format == "ext4" and
      .allocation_order == ["system_b","system_a"] and .rescue_relocation_required == false and
      .partitions[1].start_byte == .first_logical_byte and
      .partitions[0].start_byte == (.first_logical_byte + .partitions[1].bytes) and
      all(.partitions[]; .bytes % 1048576 == 0) and
      .first_logical_byte + .usable_payload_bytes <= $size and
      (.partitions[0].bytes / .usable_payload_bytes) <= 0.8 and
      (.partitions[0].bytes / .usable_payload_bytes) > 0.799 and
      .metadata_reserved_bytes + .alignment_padding_bytes + .usable_payload_bytes == $size' "$work/layout.json" >/dev/null
done
for raw in 67108864 805306368 1073741824 1409286144; do
    fastboot_seed_layout "$raw" 8321499136 > "$work/seed.json"
    jq -e --argjson raw "$raw" '.phase == "seed" and .group.name == "uke_seed" and
      .super_bytes <= 8321499136 and .partitions[1].bytes >= $raw and
      .partitions[1].start_byte == 1048576' "$work/seed.json" >/dev/null
done
if fastboot_seed_layout 2147483648 8321499136 >/dev/null 2>&1; then exit 1; fi
if fastboot_super_layout 8321499136 unknown >/dev/null 2>&1; then exit 1; fi
for capacity in 0 -1 abc 1000 1000000000 2199023255553 999999999999999999; do
    if fastboot_super_layout "$capacity" >/dev/null 2>&1; then printf 'Invalid capacity accepted: %s\n' "$capacity" >&2; exit 1; fi
done
cat > "$work/composition.json" <<'JSON'
{"kernel_release":"7.3.3-26-unstable","source_commit":"c7adc996350e3692b4492ab007cad63070dde6c2","storage_encryption_enabled_in_full_candidate":true}
JSON
cat > "$work/geometry.json" <<'JSON'
{"product":"uke","source":"synthetic-fixture","partitions":{"super":11274289152,"userdata":497535680512,"boot_a":100663296,"boot_b":100663296,"vendor_boot_a":100663296,"vendor_boot_b":100663296,"dtbo_a":25165824,"dtbo_b":25165824,"vbmeta_a":131072,"vbmeta_b":131072}}
JSON
bash "$root/src/image/plan-fastboot-update.sh" "$work/composition.json" "$work/geometry.json" "$work/plan" 141126
jq -e '.archive_created == false and .payloads_available == false and
  .first_boot.seamless_update_enabled and .secure_boot.required and
  .secure_boot.root_of_trust_qualified == false and .delivery.publish_release == false and
  .resolved_super_layout.partitions[0].bytes == 9017753600 and
  .resolved_super_layout.partitions[1].bytes == 2255486976 and
  .encryption.permitted_fallback == "unlock at user login if hardware-bound release cannot be provided"' "$work/plan/release-plan.json" >/dev/null
[[ $(grep -c '^flash boot_[ab] boot.img$' "$work/plan/fastboot-info.txt") == 2 ]]
[[ $(grep -c '^flash vendor_boot_[ab] vendor_boot.img$' "$work/plan/fastboot-info.txt") == 2 ]]
[[ $(grep -c '^flash dtbo_[ab] dtbo.img$' "$work/plan/fastboot-info.txt") == 2 ]]
[[ $(grep -c '^require partition-size:' "$work/plan/android-info.txt") == 10 ]]
grep -qx 'require is-userspace=no' "$work/plan/android-info.txt"
grep -qx 'require slot-count=2' "$work/plan/android-info.txt"
if grep -F '*' "$work/plan/android-info.txt"; then exit 1; fi
if grep -E 'erase|format|reboot|unlock|lock|disable|update-super' "$work/plan/fastboot-info.txt"; then exit 1; fi
if bash "$root/src/image/plan-fastboot-update.sh" "$work/composition.json" "$work/geometry.json" "$work/plan" 141126 >/dev/null 2>&1; then exit 1; fi
jq '.product = "foreign"' "$work/geometry.json" > "$work/foreign.json"
if bash "$root/src/image/plan-fastboot-update.sh" "$work/composition.json" "$work/foreign.json" "$work/foreign-plan" 141126 >/dev/null 2>&1; then exit 1; fi
[[ ! -e $work/foreign-plan ]]
jq 'del(.partitions.dtbo_b)' "$work/geometry.json" > "$work/incomplete.json"
if bash "$root/src/image/plan-fastboot-update.sh" "$work/composition.json" "$work/incomplete.json" "$work/incomplete-plan" 141126 >/dev/null 2>&1; then exit 1; fi
[[ ! -e $work/incomplete-plan ]]
# Invalid variant input must never produce a partly permissive requirement file.
# shellcheck source=../src/image/fastboot-requirements.sh
# shellcheck disable=SC1091
source "$root/src/image/fastboot-requirements.sh"
for invalid in foreign incomplete; do
    if fastboot_requirements "$work/geometry.json" "$work/$invalid.json" > "$work/invalid-info.txt" 2>/dev/null; then exit 1; fi
    [[ ! -s $work/invalid-info.txt ]]
done
printf 'Capacity-derived layout, date, explicit slots and incomplete/foreign geometry refusal passed; no device operations.\n'
