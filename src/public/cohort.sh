#!/usr/bin/env bash
# Host-only cohort checks. Sources only functions; never activates a boot image.
cohort_identity() {
    local request=$1 info=$2 manifest=$3
    jq -e --slurpfile r "$request" --slurpfile k "$info" '
      ($r[0]) as $r | ($k[0]) as $k |
      ($r.builder_commit | type == "string" and test("^[0-9a-f]{40}$")) and
      ($r.kernel_commit | type == "string" and test("^[0-9a-f]{40}$")) and
      ($r.kernel_version | type == "string" and test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$")) and
      ($k.rpm_version_release | type == "string" and test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?-[0-9A-Za-z._+]+$")) and
      ($k.rpm_dist | type == "string" and test("^[.]fc[0-9]+$")) and
      (($r.fedora_release == "44" and $k.rpm_dist == ".fc44") or
       ($r.fedora_release == "45" and $k.rpm_dist == ".fc45") or
       ($r.fedora_release == "rawhide")) and
      $r.kernel_profile == $k.kernel_profile and
      (($k.kernel_profile == "normal" and
        $k.kernel_family == "senemos-uke-linux-kernel-mainline" and
        ((($k.kernel_release | test("^7[.]4[.](5|[1-9][0-9]+)-senemos$")) and $k.kernel_version == "7.3.5" and
          ($k.rpm_version_release | test("^7[.]3[.]5-[1-9][0-9]*$"))) or
         $k.kernel_release == $k.rpm_version_release or
         (($k.rpm_version_release | startswith($k.kernel_release + ".")) and
          ($k.rpm_version_release | ltrimstr($k.kernel_release + ".") | test("^[1-9][0-9]*$"))))) or
       (($k.kernel_release | rtrimstr("-unstable")) as $abi |
        $k.kernel_profile == "unstable" and $r.channel == "unstable" and
        $r.fedora_release == "rawhide" and
        $k.kernel_family == "senemos-uke-linux-kernel-mainline-unstable" and
        ($k.kernel_release | test("^[0-9]+[.][0-9]+[.][0-9]+-[1-9][0-9]*-unstable$")) and
        ($k.rpm_version_release == $abi or
         (($k.rpm_version_release | startswith($abi + ".")) and
          ($k.rpm_version_release | ltrimstr($abi + ".") | test("^[1-9][0-9]*$"))))) or
       ($k.kernel_profile == "el2-require" and
        $k.kernel_family == "senemos-uke-linux-kernel-mainline-kvm" and
        $k.kernel_release == ($k.rpm_version_release + "-kvm"))) and
      (($k.kernel_release | startswith($r.kernel_version + "-")) or
       ($k.kernel_profile == "normal" and ($k.kernel_release | test("^7[.]4[.](5|[1-9][0-9]+)-senemos$")))) and
      ($k.payload_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
      $k.kernel_source_commit == $r.kernel_commit and $k.kernel_version == $r.kernel_version and
      .builder_commit == $r.builder_commit and .kernel_commit == $r.kernel_commit and
      .kernel_source_commit == $k.kernel_source_commit and .kernel_version == $k.kernel_version and
      .kernel_release == $k.kernel_release and .payload_sha256 == $k.payload_sha256 and
      .rpm_dist == $k.rpm_dist and .rpm_version_release == $k.rpm_version_release and
      .kernel_profile == $k.kernel_profile and .kernel_family == $k.kernel_family and
      .fedora_release == $r.fedora_release and
      .partition == $r.partition and .filesystem == $r.filesystem and .mode == $r.mode and
      .target == "image" and $r.target == "image" and
      (.filesystem | IN("ext4", "f2fs", "xfs", "btrfs")) and
      ((.mode == "singleboot" and .partition == "userdata") or
       (.mode == "multiboot" and .partition == "linux"))
    ' "$manifest" >/dev/null
}

# Run only after verifying all producer RPM signatures. A packaging-only RPM
# revision may preserve the kernel ABI, but its signed composition must attest
# that exact relationship; never infer an ABI by dropping arbitrary suffixes.
cohort_repository_release() (
    set -Eeuo pipefail
    local root=$1 rpm_release=$2 profile=${3:-normal} abi base_abi source composition bundle published=false
    [[ $rpm_release =~ ^7[.]3[.][0-9]+-[1-9][0-9]*([.][1-9][0-9]*)?$ ]] || return 1
    abi=$(find "$root/usr/lib/modules" -mindepth 1 -maxdepth 1 -printf '%f\n') || return 1
    case $profile in
        normal)
            if [[ $abi =~ ^7[.]4[.](5|[1-9][0-9]+)-senemos$ ]]; then
                published=true
                [[ $rpm_release =~ ^7[.]3[.]5-[1-9][0-9]*$ ]] || return 1
                base_abi=$rpm_release
            else
                [[ $abi =~ ^7[.]3[.][0-9]+-[1-9][0-9]*$ ]] || return 1
                base_abi=$abi
            fi
            ;;
        unstable) [[ $abi =~ ^7[.]3[.][0-9]+-[1-9][0-9]*-unstable$ ]] || return 1; base_abi=${abi%-unstable};;
        *) return 1;;
    esac
    [[ -d $root/usr/lib/modules/$abi && ! -L $root/usr/lib/modules/$abi ]] || return 1
    bundle=$root/usr/lib/senemos/kernel-updates/$abi
    [[ -d $bundle && ! -L $bundle && -f $bundle/manifest && ! -L $bundle/manifest ]] || return 1
    [[ $(awk -F= '$1=="kernel_release" {print $2}' "$bundle/manifest") == "$abi" ]] || return 1
    if [[ $rpm_release != "$base_abi" ]]; then
        [[ $rpm_release == "$base_abi".* && ${rpm_release#"$base_abi".} =~ ^[1-9][0-9]*$ ]] || return 1
    fi
    if [[ $profile == unstable || $rpm_release != "$base_abi" || $published == true ]]; then
        source=$root/usr/share/senemos/uke/$abi/source-commit
        composition=$root/usr/share/senemos/uke/$abi/source-composition.json
        [[ -f $source && ! -L $source && -f $composition && ! -L $composition ]] || return 1
        [[ $(< "$source") =~ ^[0-9a-f]{40}$ ]] || return 1
        jq -e --argjson published "$published" --arg abi "$abi" --arg evr "$rpm_release" --arg source "$(< "$source")" '
          .kernel_release==$abi and .source_commit==$source and
          .upstream_version==($evr|split("-")[0]) and
          .rpm_revision==($evr|split("-")[1]) and
          (if $published then
              .publication.family=="senemos-uke-linux-kernel-mainline" and
              (.publication.parent_copr_build|type=="number" and .>0 and floor==.) and
              (if $abi=="7.4.5-senemos" then
                 .publication.source_kernel_release==($evr+"-unstable")
               else
                 (.publication.normal_parent_copr_build|type=="number" and .>0 and floor==.) and
                 (.publication.source_rpm_revision|type=="string" and test("^[1-9][0-9]*$")) and
                 .publication.source_kernel_release==("7.3.5-"+.publication.source_rpm_revision+"-unstable")
               end)
           else true end)' "$composition" >/dev/null || return 1
    fi
    printf '%s\n' "$abi"
)

# Canonical producer/root byte inventory. Do not parse filenames supplied by a receipt.
cohort_payload_inventory() (
    set -Eeuo pipefail
    local modules=$1 discovered
    [[ -d $modules && ! -L $modules ]]
    cd -- "$modules"
    for path in vmlinuz config dtb/qcom/sm7675-xiaomi-uke.dtb; do
        [[ -f $path && ! -L $path ]]
    done
    [[ -d kernel && -d dtb ]]
    discovered=$(find kernel dtb -type l -print -quit) || exit 1
    [[ -z $discovered ]]
    discovered=$(find kernel -type f -name '*.ko*' -print -quit) || exit 1
    [[ -n $discovered ]]
    discovered=$(find kernel dtb ! -type d ! -type f -print -quit) || exit 1
    [[ -z $discovered ]]
    { printf 'vmlinuz\0config\0'; find kernel dtb -type f -print0; } |
        LC_ALL=C sort -z | xargs -0 sha256sum
)

cohort_boot_root_check() (
    set -Eeuo pipefail
    local image=$1 expected=$2 codec=$3 commandline token selected=linux selectors=0
    local -a tokens=()
    [[ $expected == linux || $expected == userdata ]]
    [[ -f $image && ! -L $image ]]
    # The signed codec validates the bounded Android v4 header, including the
    # 1536-byte NUL-terminated command line. Older signed codecs expose inspect
    # and extract but not the newer check-root subcommand.
    "$codec" inspect "$image" >/dev/null
    IFS= read -r -d '' commandline < <(dd if="$image" bs=1 skip=44 count=1536 iflag=nofollow status=none)
    commandline=${commandline//$'\t'/ }
    commandline=${commandline//$'\n'/ }
    commandline=${commandline//$'\r'/ }
    commandline=${commandline//$'\v'/ }
    commandline=${commandline//$'\f'/ }
    read -r -a tokens <<< "$commandline"
    for token in "${tokens[@]}"; do
        if [[ $token == senemos.root=* ]]; then
            selectors=$((selectors + 1))
            selected=${token#senemos.root=}
        fi
    done
    [[ $selectors -le 1 && $selected == "$expected" ]]
)

# Use the RPM headers from the selected producer inventory to distinguish
# legacy split packages from a core RPM that owns all three payloads.
cohort_kernel_components() {
    local inventory=$1 family=$2 evr=$3 component count=0
    for component in -modules -dtbs -boot; do
        if awk -F '\t' -v name="$family$component-$evr.aarch64" '$1==name { found=1 } END { exit !found }' "$inventory"; then
            count=$((count + 1))
        fi
    done
    case $count in
        0) printf '%s\n' '' -core ;;
        3) printf '%s\n' '' -core -modules -dtbs -boot ;;
        *) printf 'Incomplete split RPM family in %s\n' "$inventory" >&2; return 1 ;;
    esac
}

cohort_root_check() {
    # A fresh shell preserves fail-fast behavior even when a caller tests status
    # with if/!; Bash otherwise disables errexit throughout a called function.
    bash "${BASH_SOURCE[0]}" root "$@"
}

cohort_root_check_main() (
    set -Eeuo pipefail
    [[ $# == 6 ]]
    local request=$1 artifacts=$2 root=$3 codec=$4 expected_packages=$5 installed_packages=$6
    local info=$artifacts/kernel/kernel-info.json manifest=$artifacts/manifest.json
    cohort_identity "$request" "$info" "$manifest"
    local release partition filesystem modules bundle scratch hash component nevra expected actual releases family rpm_release dist profile components
    release=$(jq -er .kernel_release "$info")
    family=$(jq -er .kernel_family "$info")
    rpm_release=$(jq -er .rpm_version_release "$info")
    dist=$(jq -er .rpm_dist "$info")
    profile=$(jq -er .kernel_profile "$info")
    if [[ $profile == unstable || ( $profile == normal && $rpm_release != "$release" ) ]]; then
        [[ $(cohort_repository_release "$root" "$rpm_release" "$profile") == "$release" ]]
        [[ $(< "$root/usr/share/senemos/uke/$release/source-commit") == "$(jq -er .kernel_source_commit "$info")" ]]
    fi
    partition=$(jq -er .partition "$request")
    filesystem=$(jq -er .filesystem "$request")
    modules=$root/usr/lib/modules/$release
    bundle=$root/usr/lib/senemos/kernel-updates/$release
    # This gate is for a fresh image root, not a live system retaining rollback releases.
    releases=$(find "$root/usr/lib/modules" -mindepth 1 -maxdepth 1 -printf '%f\n') || exit 1
    [[ $releases == "$release" ]]
    [[ -d $bundle && ! -L $bundle ]]
    [[ -f $artifacts/kernel/payload.sha256 && ! -L $artifacts/kernel/payload.sha256 ]]
    hash=$(sha256sum "$artifacts/kernel/payload.sha256"); hash=${hash%% *}
    [[ $hash == "$(jq -er .payload_sha256 "$info")" ]]
    scratch=$(mktemp -d)
    trap 'rm -rf -- "$scratch"' EXIT
    cohort_payload_inventory "$modules" > "$scratch/payload.sha256"
    cmp "$artifacts/kernel/payload.sha256" "$scratch/payload.sha256"
    # Compare installed package identity to the independently queried producer RPM set.
    components=$(cohort_kernel_components "$expected_packages" "$family" "$rpm_release$dist")
    while IFS= read -r component; do
        nevra=$family$component-$rpm_release$dist.aarch64
        expected=$(awk -F '\t' -v name="$nevra" '$1==name {print $1 "\t" $2}' "$expected_packages")
        actual=$(awk -F '\t' -v name="$nevra" '$1==name {print $1 "\t" $2}' "$installed_packages")
        [[ -n $expected && $expected != *$'\n'* && $expected == "$actual" && $expected != *$'\t' ]]
        printf '%s\n' "$expected" >> "$scratch/expected-packages"
    done <<< "$components"
    if [[ $partition == userdata ]]; then
        nevra=$family-singleboot-$rpm_release$dist.aarch64
        expected=$(awk -F '\t' -v name="$nevra" '$1==name {print $1 "\t" $2}' "$expected_packages")
        actual=$(awk -F '\t' -v name="$nevra" '$1==name {print $1 "\t" $2}' "$installed_packages")
        [[ -n $expected && $expected != *$'\n'* && $expected == "$actual" && $expected != *$'\t' ]]
        printf '%s\n' "$expected" >> "$scratch/expected-packages"
    fi
    LC_ALL=C sort "$scratch/expected-packages" > "$scratch/expected-sorted"
    awk -F '\t' '$1 ~ /^senemos-uke-linux-kernel-mainline-/ {print $1 "\t" $2}' "$installed_packages" |
        LC_ALL=C sort > "$scratch/installed-sorted"
    cmp "$scratch/expected-sorted" "$scratch/installed-sorted"
    [[ $(awk '$1 !~ /^#/ && $2=="/" {print $1 " " $3}' "$root/etc/fstab") == "PARTLABEL=$partition $filesystem" ]]
    for path in "$artifacts/boot.img" "$artifacts/boot-$partition.img" "$bundle/$partition.img"; do
        [[ -f $path && ! -L $path ]]
    done
    cmp "$artifacts/boot.img" "$artifacts/boot-$partition.img"
    cmp "$artifacts/boot.img" "$bundle/$partition.img"
    cohort_boot_root_check "$artifacts/boot.img" "$partition" "$codec"
    "$codec" extract "$artifacts/boot.img" "$scratch/Image"
    cmp "$modules/vmlinuz" "$scratch/Image"
    jq -n '{source:"matched-request-and-producer",packages:"matched-producer-rpm-identities",
      kernel_modules_config_dt:"matched-producer-payload-bytes",boot_kernel:"extracted-and-matched",
      root_selector:"matched-fstab",final_filesystem_hashes_verified:false,
      runtime_firmware_compatibility:"unverified",physical_boot_tested:false,rollback_tested:false}'
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -Eeuo pipefail
    [[ $# == 7 && $1 == root ]]
    shift
    cohort_root_check_main "$@"
fi
