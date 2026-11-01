#!/usr/bin/env bash
# Tiny producer/root fixtures; no RPM installation, container or device access.
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/public/cohort.sh
# shellcheck disable=SC1091
source "$repo/src/public/cohort.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
c++ -std=c++20 -O2 -Wall -Wextra -Werror "$repo/src/boot/boot-image.cpp" -o "$fixture/codec"
artifacts=$fixture/artifacts root=$fixture/root release=7.3.0-16
modules=$root/usr/lib/modules/$release
bundle=$root/usr/lib/senemos/kernel-updates/$release
mkdir -p "$modules/kernel/drivers" "$modules/dtb/qcom" "$bundle" "$root/etc" "$artifacts/kernel"
truncate -s 64 "$modules/vmlinuz"
printf '\100\000\000\000\000\000\000\000' | dd of="$modules/vmlinuz" bs=1 seek=16 conv=notrunc status=none
printf '\101\122\115\144' | dd of="$modules/vmlinuz" bs=1 seek=56 conv=notrunc status=none
printf 'CONFIG_ARM64=y\n' > "$modules/config"
printf 'fixture module bytes\n' > "$modules/kernel/drivers/fixture.ko"
printf 'fixture DT bytes, not a physical board\n' > "$modules/dtb/qcom/sm7675-xiaomi-uke.dtb"
cohort_payload_inventory "$modules" > "$artifacts/kernel/payload.sha256"
payload=$(sha256sum "$artifacts/kernel/payload.sha256" | cut -d ' ' -f1)
"$fixture/codec" create "$modules/vmlinuz" "$bundle/userdata.img" userdata
cat > "$fixture/legacy-codec" <<'SH'
#!/usr/bin/env bash
[[ $1 != check-root ]] || exit 98
exec "$(dirname "$0")/codec" "$@"
SH
chmod +x "$fixture/legacy-codec"
cohort_boot_root_check "$bundle/userdata.img" userdata "$fixture/legacy-codec"
cp "$bundle/userdata.img" "$fixture/selector.img"
for commandline in 'senemos.root=linux' 'senemos.root=userdata senemos.root=userdata' \
    $'senemos.root=userdata\nsenemos.root=linux' 'senemos.root='; do
    dd if=/dev/zero of="$fixture/selector.img" bs=1 seek=44 count=1536 conv=notrunc status=none
    printf '%s\0' "$commandline" | dd of="$fixture/selector.img" bs=1 seek=44 conv=notrunc status=none
    if cohort_boot_root_check "$fixture/selector.img" userdata "$fixture/legacy-codec"; then
        echo 'Invalid or repeated boot root selector accepted' >&2; exit 1
    fi
done
dd if=/dev/zero of="$fixture/selector.img" bs=1 seek=44 count=1536 conv=notrunc status=none
printf 'extra=1\nsenemos.root=userdata\tother=2\0' | dd of="$fixture/selector.img" bs=1 seek=44 conv=notrunc status=none
cohort_boot_root_check "$fixture/selector.img" userdata "$fixture/legacy-codec"
dd if=/dev/zero of="$fixture/selector.img" bs=1 seek=44 count=1536 conv=notrunc status=none
cohort_boot_root_check "$fixture/selector.img" linux "$fixture/legacy-codec"
if cohort_boot_root_check "$fixture/selector.img" userdata "$fixture/legacy-codec"; then exit 1; fi
echo 'Legacy signed-codec interface, wrong/duplicate roots, whitespace and default root checks passed'
cp "$bundle/userdata.img" "$artifacts/boot.img"
cp "$bundle/userdata.img" "$artifacts/boot-userdata.img"
printf 'PARTLABEL=userdata / ext4 defaults 0 0\n' > "$root/etc/fstab"
sha=$(printf 'a%.0s' {1..40})
jq -n --arg sha "$sha" '{target:"image",fedora_release:"rawhide",kernel_profile:"normal",builder_commit:$sha,kernel_commit:$sha,kernel_version:"7.3.0",partition:"userdata",mode:"singleboot",filesystem:"ext4"}' > "$fixture/request.json"
jq -n --arg sha "$sha" --arg payload "$payload" '{rpm_dist:".fc46",rpm_version_release:"7.3.0-16",kernel_profile:"normal",kernel_family:"senemos-uke-linux-kernel-mainline",kernel_source_commit:$sha,kernel_version:"7.3.0",kernel_release:"7.3.0-16",payload_sha256:$payload}' > "$artifacts/kernel/kernel-info.json"
jq -s '.[0]+.[1]' "$fixture/request.json" "$artifacts/kernel/kernel-info.json" > "$artifacts/manifest.json"
for component in '' -core -modules -dtbs -boot -singleboot; do
 printf 'senemos-uke-linux-kernel-mainline%s-%s.fc46.aarch64\tsenemos-uke-linux-kernel-mainline-%s.fc46.src.rpm\n' "$component" "$release" "$release"
done > "$artifacts/kernel/packages.tsv"
cp "$artifacts/kernel/packages.tsv" "$artifacts/installed-rpms.tsv"
check() { cohort_root_check "$fixture/request.json" "$artifacts" "$root" "$fixture/codec" "$artifacts/kernel/packages.tsv" "$artifacts/installed-rpms.tsv"; }
reject() { if check > "$fixture/rejected.log" 2>&1; then echo "Invalid cohort accepted: $1" >&2; exit 1; fi; }
check > "$fixture/receipt.json"
jq -e '.physical_boot_tested==false and .rollback_tested==false and .final_filesystem_hashes_verified==false and .runtime_firmware_compatibility=="unverified"' "$fixture/receipt.json" >/dev/null
# Exercise current producer package naming without installing any RPMs. Stable
# Fedora images remain gated by entry.sh; these are synthetic cohort fixtures.
cp "$fixture/request.json" "$fixture/request.base"
cp "$artifacts/kernel/kernel-info.json" "$fixture/info.base"
cp "$artifacts/kernel/packages.tsv" "$fixture/packages.base"
for target in 44 45 rawhide; do
 for profile in normal el2-require; do
  dist=.fc${target/rawhide/46}
  family=senemos-uke-linux-kernel-mainline
  abi=$release
  if [[ $profile == el2-require ]]; then family+=-kvm; abi+=-kvm; fi
  jq --arg target "$target" --arg profile "$profile" '.fedora_release=$target | .kernel_profile=$profile' "$fixture/request.base" > "$fixture/request.json"
  jq --arg dist "$dist" --arg profile "$profile" --arg family "$family" --arg abi "$abi" '.rpm_dist=$dist | .kernel_profile=$profile | .kernel_family=$family | .kernel_release=$abi' "$fixture/info.base" > "$artifacts/kernel/kernel-info.json"
  jq -s '.[0]+.[1]' "$fixture/request.json" "$artifacts/kernel/kernel-info.json" > "$artifacts/manifest.json"
  for component in '' -core -modules -dtbs -boot -singleboot; do
   printf '%s%s-%s%s.aarch64\t%s-%s%s.src.rpm\n' "$family" "$component" "$release" "$dist" "$family" "$release" "$dist"
  done > "$artifacts/kernel/packages.tsv"
  cp "$artifacts/kernel/packages.tsv" "$artifacts/installed-rpms.tsv"
  if [[ $abi != "$release" ]]; then mv "$modules" "${modules}-kvm"; mv "$bundle" "${bundle}-kvm"; fi
  check >/dev/null
  cp "$artifacts/manifest.json" "$fixture/variant.manifest"
  for expression in '.rpm_dist=".fc99"' '.kernel_profile="unknown"' '.kernel_family="other"' '.rpm_version_release="7.3.0-99"'; do
   jq "$expression" "$fixture/variant.manifest" > "$artifacts/manifest.json"
   reject "$target/$profile manifest $expression"
  done
  if [[ $abi != "$release" ]]; then mv "${modules}-kvm" "$modules"; mv "${bundle}-kvm" "$bundle"; fi
 done
done
cp "$fixture/request.base" "$fixture/request.json"
cp "$fixture/info.base" "$artifacts/kernel/kernel-info.json"
cp "$fixture/packages.base" "$artifacts/kernel/packages.tsv"
cp "$fixture/packages.base" "$artifacts/installed-rpms.tsv"
jq -s '.[0]+.[1]' "$fixture/request.json" "$artifacts/kernel/kernel-info.json" > "$artifacts/manifest.json"
for expression in '.rpm_dist=".el9"' '.kernel_profile="el2-require"' '.kernel_family="other"' '.rpm_version_release="7.3.0-99"' 'del(.rpm_dist)'; do
 jq "$expression" "$fixture/info.base" > "$artifacts/kernel/kernel-info.json"
 jq -s '.[0]+.[1]' "$fixture/request.json" "$artifacts/kernel/kernel-info.json" > "$artifacts/manifest.json"
 reject "self-consistent invalid producer $expression"
done
cp "$fixture/info.base" "$artifacts/kernel/kernel-info.json"
jq '.fedora_release="44"' "$fixture/request.base" > "$fixture/request.json"
jq -s '.[0]+.[1]' "$fixture/request.json" "$artifacts/kernel/kernel-info.json" > "$artifacts/manifest.json"
reject 'Fedora 44 request with Fedora 46 producer'
cp "$fixture/request.base" "$fixture/request.json"
jq -s '.[0]+.[1]' "$fixture/request.json" "$artifacts/kernel/kernel-info.json" > "$artifacts/manifest.json"
echo 'Six Fedora/profile cohorts and mismatched producer/manifest fixtures passed'
# Each enumeration must complete, even when its partial output looks admissible.
mkdir "$fixture/bin"
cat > "$fixture/bin/find" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
phase=other
if [[ $1 == "$UKE_FIND_ROOT/usr/lib/modules" ]]; then phase=releases
elif [[ $1 == kernel && $2 == dtb && $3 == -type && $4 == l ]]; then phase=symlinks
elif [[ $1 == kernel && $2 == -type ]]; then phase=modules
elif [[ $1 == kernel && $2 == dtb && $3 == '!' ]]; then phase=special
elif [[ $1 == kernel && $2 == dtb && $3 == -type && $4 == f ]]; then phase=inventory
fi
if [[ $phase == "$UKE_FIND_PHASE" ]]; then
    if [[ $UKE_FIND_OUTPUT == partial ]]; then "$UKE_REAL_FIND" "$@"; fi
    exit 1
fi
exec "$UKE_REAL_FIND" "$@"
SH
chmod +x "$fixture/bin/find"
real_find=$(command -v find)
for phase in releases symlinks modules special inventory; do
 for output in empty partial; do
  if PATH="$fixture/bin:$PATH" UKE_FIND_ROOT="$root" UKE_FIND_PHASE=$phase \
      UKE_FIND_OUTPUT=$output UKE_REAL_FIND="$real_find" check > "$fixture/find-output" 2>&1; then
   echo "Failed traversal accepted: $phase/$output" >&2; exit 1
  fi
  if grep -q 'matched-request-and-producer' "$fixture/find-output"; then
   echo "Failed traversal produced a success receipt: $phase/$output" >&2; exit 1
  fi
 done
done
echo 'Ten empty/partial traversal failures rejected without a success receipt'
check >/dev/null
cp "$fixture/request.json" "$fixture/request.original"
"$fixture/codec" create "$modules/vmlinuz" "$bundle/linux.img"
cp "$bundle/linux.img" "$artifacts/boot-linux.img"
cp "$bundle/linux.img" "$artifacts/boot.img"
jq '.mode="multiboot" | .partition="linux"' "$fixture/request.original" > "$fixture/request.json"
jq -s '.[0]+.[1]' "$fixture/request.json" "$artifacts/kernel/kernel-info.json" > "$artifacts/manifest.json"
grep -v '^senemos-uke-linux-kernel-mainline-singleboot-' "$artifacts/kernel/packages.tsv" > "$artifacts/installed-rpms.tsv"
printf 'PARTLABEL=linux / ext4 defaults 0 0\n' > "$root/etc/fstab"
check >/dev/null
cp "$fixture/request.original" "$fixture/request.json"
jq -s '.[0]+.[1]' "$fixture/request.json" "$artifacts/kernel/kernel-info.json" > "$artifacts/manifest.json"
cp "$artifacts/kernel/packages.tsv" "$artifacts/installed-rpms.tsv"
cp "$bundle/userdata.img" "$artifacts/boot.img"
printf 'PARTLABEL=userdata / ext4 defaults 0 0\n' > "$root/etc/fstab"
cp "$artifacts/manifest.json" "$fixture/manifest.original"
for expression in '.kernel_commit="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' '.builder_commit="main"' '.kernel_source_commit="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' '.kernel_release="7.3.0-17"' '.kernel_version="7.2.12"' '.partition="linux"' '.filesystem="f2fs"' '.payload_sha256=null'; do
 jq "$expression" "$fixture/manifest.original" > "$artifacts/manifest.json"
 reject "$expression"
done
cp "$fixture/manifest.original" "$artifacts/manifest.json"
# Real byte changes are checked against producer evidence, not freshly self-certified.
for path in config kernel/drivers/fixture.ko dtb/qcom/sm7675-xiaomi-uke.dtb vmlinuz; do
 cp "$modules/$path" "$fixture/original"
 printf wrong >> "$modules/$path"
 reject "changed $path"
 cp "$fixture/original" "$modules/$path"
done
printf extra > "$modules/kernel/drivers/extra.ko"; reject 'extra module'; rm "$modules/kernel/drivers/extra.ko"
mv "$modules/kernel/drivers/fixture.ko" "$fixture/module"
reject 'missing module'
ln -s "$fixture/module" "$modules/kernel/drivers/fixture.ko"; reject 'symlink module'
rm "$modules/kernel/drivers/fixture.ko"; mv "$fixture/module" "$modules/kernel/drivers/fixture.ko"
mkdir "$root/usr/lib/modules/older"; reject 'additional release'; rmdir "$root/usr/lib/modules/older"
cp "$artifacts/installed-rpms.tsv" "$fixture/packages.original"
sed -i 's/7.3.0-16.fc46.src.rpm/7.3.0-17.fc46.src.rpm/' "$artifacts/installed-rpms.tsv"
reject 'different source RPM'
cp "$fixture/packages.original" "$artifacts/installed-rpms.tsv"
cat "$fixture/packages.original" >> "$artifacts/installed-rpms.tsv"; reject 'duplicate installed kernel packages'
cp "$fixture/packages.original" "$artifacts/installed-rpms.tsv"
printf 'PARTLABEL=linux / ext4 defaults 0 0\n' > "$root/etc/fstab"; reject 'wrong root selector'
printf 'PARTLABEL=userdata / ext4 defaults 0 0\n' > "$root/etc/fstab"
printf wrong >> "$artifacts/boot.img"; reject 'changed selected boot'
cp "$bundle/userdata.img" "$artifacts/boot.img"
"$fixture/codec" create "$modules/vmlinuz" "$fixture/linux.img" linux
for path in "$artifacts/boot.img" "$artifacts/boot-userdata.img" "$bundle/userdata.img"; do cp "$fixture/linux.img" "$path"; done
reject "matching kernel but wrong boot root selector"
# Three matching boot files can still embed the wrong Image.
cp "$modules/vmlinuz" "$fixture/wrong.Image"
printf X | dd of="$fixture/wrong.Image" bs=1 seek=0 conv=notrunc status=none
"$fixture/codec" create "$fixture/wrong.Image" "$fixture/wrong.img" userdata
for path in "$artifacts/boot.img" "$artifacts/boot-userdata.img" "$bundle/userdata.img"; do cp "$fixture/wrong.img" "$path"; done
reject 'self-consistent boot files with wrong embedded kernel'
echo 'Cohort identity, package, module/config/DT, boot and root mismatch fixtures passed; firmware/runtime/rollback remain unverified'
