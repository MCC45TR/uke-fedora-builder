#!/usr/bin/env bash
# Image delivery metadata; this script never opens a device or edits image bytes.
set -Eeuo pipefail
export LC_ALL=C
release_fail() { printf 'image-release: %s\n' "$*" >&2; exit 1; }
release_manifest() {
    jq -e '
      .distribution=="fedora" and .architecture=="aarch64" and
      (.fedora_release | IN("rawhide","44","45")) and .release==.fedora_release and
      .image_built and .rpm_transaction_validated and .source_checked and
      .mode=="singleboot" and .partition=="userdata" and .filesystem=="ext4" and
      .device_private_data_included==false and .ssh_enabled==false and .automatic_kernel_activation==false and
      ((.desktop=="cutefish" and .credentials_included==true and .public_test_account=="senemos" and
        .account_setup=="gdm-expired-public-test-account" and .password_change_required==true and .password_change_backend_tested==true and
        .autologin_enabled==false and .remote_password_login==false and .passwordless_sudo==false) or
       (.desktop!="cutefish" and .credentials_included==false)) and
      .kernel_rpm_signature=="verified COPR signature" and .kernel_rpms_locally_built==false and
      .filesystem_contents_readback and .filesystem_metadata_readback and
      .selinux_policy_contexts_verified and .independent_aosp_decoder_verified and .sparse_roundtrip_verified and
      .cohort_validation.final_filesystem_hashes_verified and
      .cohort_validation.source=="matched-request-and-producer" and .cohort_validation.packages=="matched-producer-rpm-identities" and
      .cohort_validation.kernel_modules_config_dt=="matched-producer-payload-bytes" and
      .cohort_validation.boot_kernel=="extracted-and-matched" and .cohort_validation.root_selector=="matched-fstab" and
      ([.boot_sha256,.root_sparse_sha256,.payload_sha256] | all(.[]; type=="string" and test("^[0-9a-f]{64}$"))) and
      (.size_mib|type=="number" and .>0) and .root_raw_bytes==(.size_mib*1048576) and
      ([.kernel_commit,.kernel_source_commit] | all(.[]; type=="string" and test("^[0-9a-f]{40}$"))) and
      ([.image_built,.rpm_transaction_validated,.source_checked,.filesystem_contents_readback,.filesystem_metadata_readback,
        .selinux_policy_contexts_verified,.independent_aosp_decoder_verified,.sparse_roundtrip_verified,.cohort_validation.final_filesystem_hashes_verified] | all(.[]; .==true)) and
      ([.kernel_profile,.kernel_family,.kernel_version,.kernel_release,.rpm_dist,.rpm_version_release,
        .kernel_repository,.kernel_key_fingerprint] | all(.[]; type=="string" and length>0))
    ' "$1" >/dev/null || release_fail 'Incomplete or unsupported image manifest'
}
release_cohort() {
    release_manifest "$1"
    # Desktop, shell and builder revision may differ. The boot bytes are checked
    # independently; module/config/DT identity and root selection must agree.
    jq -S '{distribution,architecture,fedora_release,mode,partition,filesystem,size_mib,root_raw_bytes,
      kernel_profile,kernel_family,kernel_version,kernel_release,kernel_commit,kernel_source_commit,
      rpm_dist,rpm_version_release,kernel_repository,kernel_key_fingerprint,payload_sha256}' "$1"
}
release_names() {
    local manifest=$1 day=$2 revision=$3 desktop version iso
    release_manifest "$manifest"
    [[ $day =~ ^[0-9]{6}$ && $revision =~ ^(0|[1-9][0-9]{0,3})$ ]] || release_fail 'Invalid DDMMYY date or numeric revision'
    iso=20${day:4:2}-${day:2:2}-${day:0:2}
    [[ $(date -d "$iso" +%d%m%y) == "$day" ]] || release_fail 'Invalid calendar date'
    version=$(jq -er .fedora_release "$manifest")
    case $(jq -er .desktop "$manifest") in
        kde) desktop=kde-plasma;; gnome) desktop=gnome;; plasma-mobile) desktop=kde-plasma-mobile;;
        cutefish) desktop=cutefish;; nextkde) desktop=nextkde;; *) release_fail 'Unknown desktop name';;
    esac
    jq -n --arg version "$version" --arg desktop "$desktop" --arg date "$day" --arg revision "$revision" '
      {distribution:"fedora",version:$version,date:$date,revision:$revision,
       tag:("fedora-"+$version+"-uke-senemos-"+$date+"-r"+$revision),
       boot:("fedora-"+$version+"-uke-senemos-boot-"+$date+"-r"+$revision+".img"),
       system:("fedora-"+$version+"-"+$desktop+"-uke-senemos-system-"+$date+"-r"+$revision+".img.zst")}'
}
release_asset_name() {
    local layout=$1 name=$2 version day revision
    version=$(jq -er .version "$layout"); day=$(jq -er .date "$layout"); revision=$(jq -er .revision "$layout")
    [[ $name == "fedora-$version-uke-senemos-boot-$day-r$revision.img" ||
       $name =~ ^fedora-$version-(kde-plasma|gnome|kde-plasma-mobile|cutefish|nextkde)-uke-senemos-system-$day-r${revision}[.]img([.]zst)?$ ]]
}
release_verify() {
    local delivery=$1 file name manifest cohort boot sha expected count=0
    [[ -f $delivery/receipts/layout.json && -f $delivery/receipts/cohort.json ]] || release_fail 'Missing delivery receipts'
    boot=$(jq -er .boot "$delivery/receipts/layout.json")
    [[ -f $delivery/assets/$boot && ! -L $delivery/assets/$boot ]] || release_fail 'Missing shared boot image'
    shopt -s nullglob
    local entries=("$delivery/assets/"*) manifests=("$delivery/receipts/images/"*.json)
    ((${#manifests[@]} > 0 && ${#entries[@]} == ${#manifests[@]} + 1)) || release_fail 'Unexpected image or receipt count'
    for file in "${entries[@]}"; do
        name=${file##*/}
        [[ -f $file && ! -L $file ]] || release_fail "Unexpected release asset: $name"
        release_asset_name "$delivery/receipts/layout.json" "$name" || release_fail "Unexpected release asset: $name"
    done
    for manifest in "${manifests[@]}"; do
        [[ -f $manifest && ! -L $manifest ]] || release_fail 'Unsafe image receipt'
        release_manifest "$manifest"
        cohort=$(release_cohort "$manifest")
        [[ $cohort == "$(cat "$delivery/receipts/cohort.json")" ]] || release_fail 'Incompatible kernel/module/DT/root cohort'
        name=${manifest##*/}; name=${name%.json}
        local names
        names=$(release_names "$manifest" "$(jq -er .date "$delivery/receipts/layout.json")" "$(jq -er .revision "$delivery/receipts/layout.json")")
        [[ $name == "$(jq -er .system <<< "$names")" && $(jq -Sc 'del(.system)' <<< "$names") == "$(jq -Sc . "$delivery/receipts/layout.json")" ]] || release_fail 'Image names do not match their receipts'
        [[ -f $delivery/assets/$name && ! -L $delivery/assets/$name ]] || release_fail 'Root image receipt has no asset'
        expected=$(jq -er .boot_sha256 "$manifest")
        sha=$(sha256sum "$delivery/assets/$boot"); [[ ${sha%% *} == "$expected" ]] || release_fail 'Shared boot hash mismatch'
        if [[ $name == *.zst ]]; then sha=$(zstd -dc -- "$delivery/assets/$name" | sha256sum)
        else sha=$(sha256sum "$delivery/assets/$name"); fi
        [[ ${sha%% *} == "$(jq -er .root_sparse_sha256 "$manifest")" ]] || release_fail 'Root image hash mismatch'
        count=$((count + 1))
    done
    ((count > 0))
}
release_inventory() {
    local delivery=$1 file sha
    shopt -s nullglob
    for file in "$delivery/assets/"*; do
        sha=$(sha256sum "$file")
        printf '%s\t%s\t%s\n' "${file##*/}" "$(stat -c %s "$file")" "${sha%% *}"
    done | LC_ALL=C sort
}
release_desktop_set() {
    local delivery=$1 core=$2 policy=${3:-complete} manifest actual
    [[ $core =~ ^[0-9a-f]{64}$ ]] || release_fail 'Missing expected common core hash'
    release_verify "$delivery"
    local manifests=("$delivery/receipts/images/"*.json)
    case $policy in complete|cutefish-optional) ;; *) release_fail 'Unknown desktop publication policy';; esac
    actual=$(jq -sr 'map(.desktop)|sort|join(",")' "${manifests[@]}")
    if [[ $policy == cutefish-optional && $actual == gnome,kde,nextkde ]]; then
        [[ ${#manifests[@]} == 3 ]]
    else
        [[ ${#manifests[@]} == 4 && $actual == cutefish,gnome,kde,nextkde ]] || release_fail 'Publication requires KDE, GNOME and NextKDE; only Cutefish may be omitted explicitly'
    fi
    for manifest in "${manifests[@]}"; do
        jq -e --arg core "$core" '.shared_core_sha256==$core and .desktop_isolation_audited==true and
            .previous_desktop_image_input==false and .fedora_release=="rawhide" and .channel=="unstable" and .default_shell=="bash"' \
            "$manifest" >/dev/null || release_fail 'Desktop set has a different core, profile or unverified isolation'
    done
}
release_stage() {
    local artifacts=$1 delivery=$2 day=$3 revision=$4 compressed=${5:-} names boot system cohort stage file
    release_manifest "$artifacts/manifest.json"
    for file in boot.img userdata.img; do
        [[ -f $artifacts/$file && ! -L $artifacts/$file ]] || release_fail "Missing regular input: $file"
    done
    [[ $(sha256sum "$artifacts/boot.img" | cut -d ' ' -f1) == "$(jq -er .boot_sha256 "$artifacts/manifest.json")" ]] || release_fail 'Input boot hash mismatch'
    [[ $(sha256sum "$artifacts/userdata.img" | cut -d ' ' -f1) == "$(jq -er .root_sparse_sha256 "$artifacts/manifest.json")" ]] || release_fail 'Input root hash mismatch'
    names=$(release_names "$artifacts/manifest.json" "$day" "$revision")
    boot=$(jq -er .boot <<< "$names"); system=$(jq -er .system <<< "$names")
    cohort=$(release_cohort "$artifacts/manifest.json")
    for file in "$delivery" "$delivery/assets" "$delivery/receipts" "$delivery/receipts/cohort.json" "$delivery/receipts/layout.json" "$delivery/assets/$boot" "$delivery/assets/$system"; do
        [[ ! -L $file ]] || release_fail 'Symlink in delivery layout'
    done
    mkdir -p "$delivery/assets" "$delivery/receipts/images" "$delivery/receipts/builds"
    if [[ -e $delivery/receipts/cohort.json ]]; then
        [[ $(cat "$delivery/receipts/cohort.json") == "$cohort" ]] || release_fail 'Use a separate revision for a different kernel cohort'
        [[ $(jq -Sc 'del(.system)' "$delivery/receipts/layout.json") == "$(jq -Sc 'del(.system)' <<< "$names")" ]] || release_fail 'Delivery name/revision mismatch'
    fi
    if [[ -e $delivery/assets/$boot ]]; then
        [[ ! -L $delivery/assets/$boot ]] || release_fail 'Symlink in shared boot path'
        cmp -s "$delivery/assets/$boot" "$artifacts/boot.img" || release_fail 'Desktop-independent boot name collision: boot bytes differ'
    fi
    if [[ -e $delivery/assets/$system ]]; then
        release_verify "$delivery"
        [[ $(jq -er .root_sparse_sha256 "$delivery/receipts/images/$system.json") == "$(jq -er .root_sparse_sha256 "$artifacts/manifest.json")" ]] || release_fail 'Root name collision: choose another revision'
        return
    fi
    stage=$(mktemp -d "$delivery/.stage.XXXXXXXX")
    if [[ -n $compressed ]]; then
        [[ -f $compressed && ! -L $compressed ]] || release_fail 'Compressed input is not a regular file'
        cp -- "$compressed" "$stage/$system"
    else
        zstd -T0 -10 --check --no-progress "$artifacts/userdata.img" -o "$stage/$system"
    fi
    [[ $(zstd -dc "$stage/$system" | sha256sum | cut -d ' ' -f1) == "$(jq -er .root_sparse_sha256 "$artifacts/manifest.json")" ]] || release_fail 'Compressed root mismatch'
    [[ -e $delivery/assets/$boot ]] || install -m644 "$artifacts/boot.img" "$delivery/assets/$boot"
    mv -- "$stage/$system" "$delivery/assets/$system"; rmdir "$stage"
    printf '%s\n' "$cohort" > "$delivery/receipts/cohort.json"
    jq 'del(.system)' <<< "$names" > "$delivery/receipts/layout.json"
    install -m644 "$artifacts/manifest.json" "$delivery/receipts/images/$system.json"
    local records=$delivery/receipts/builds/${system%.img.zst}
    mkdir -p "$records"
    for file in FLASHING.txt installed-rpms.tsv fedora-inputs.tsv desktop-inputs.tsv language-audit.json supported-locales.txt; do
        [[ ! -f $artifacts/$file ]] || install -m644 "$artifacts/$file" "$records/$file"
    done
    if [[ -d $artifacts/kernel ]]; then
        for file in packages.tsv RPM-SHA256SUMS kernel-info.json producer.json; do
            [[ ! -f $artifacts/kernel/$file ]] || install -m644 "$artifacts/kernel/$file" "$records/kernel-$file"
        done
    fi
    release_verify "$delivery"
    release_inventory "$delivery" > "$delivery/receipts/images.tsv"
}
# Markdown backticks are literal; printf supplies the variable fields.
# shellcheck disable=SC2016
release_body() {
    local delivery=$1 inventory=$2 file bytes sha boot version revision day source example runs run manifest
    boot=$(jq -er .boot "$delivery/receipts/layout.json")
    version=$(jq -er .version "$delivery/receipts/layout.json")
    revision=$(jq -er .revision "$delivery/receipts/layout.json")
    day=$(jq -er .date "$delivery/receipts/layout.json")
    source=$(sha256sum "$delivery/receipts/cohort.json"); source=${source%% *}
    printf 'Fedora %s AArch64 experimental Uke Senemos images, %s r%s.\n\n' "$version" "$day" "$revision"
    printf '<!-- uke-image-cohort-sha256: %s -->\n\n' "$source"
    runs=${UKE_RELEASE_BUILD_RUNS:-${GITHUB_RUN_ID:-}}
    if [[ -n $runs ]]; then
        [[ $runs =~ ^[0-9]+(,[0-9]+)*$ ]] || release_fail 'Invalid build record IDs'
        printf '<!-- uke-image-build-runs: %s -->\n\n' "$runs"
    fi
    printf 'Boot is shared across desktops only after byte equality and the kernel/module/DT/root cohort agree. Host verification does not qualify tablet boot, first-account setup, firmware compatibility or rollback.\n\n'
    for manifest in "$delivery/receipts/images/"*.json; do
        if jq -e '.shared_core_producer_run_id and .shared_core_producer_workspace_commit' "$manifest" >/dev/null; then
            printf 'Frozen common core: workspace `%s`, builder `%s`, successful core job in Actions run `%s`, archive SHA256 `%s`. Desktop composition records its consumer revision separately.\n\n' \
                "$(jq -er .shared_core_producer_workspace_commit "$manifest")" "$(jq -er .shared_core_producer_builder_commit "$manifest")" \
                "$(jq -er .shared_core_producer_run_id "$manifest")" "$(jq -er .shared_core_sha256 "$manifest")"
            break
        fi
    done
    printf 'Kernel cohort: `%s`; source `%s`; signer `%s`. Required userdata capacity: **%s bytes**.\n\n' \
        "$(jq -r .kernel_release "$delivery/receipts/cohort.json")" "$(jq -r .kernel_source_commit "$delivery/receipts/cohort.json")" \
        "$(jq -r .kernel_key_fingerprint "$delivery/receipts/cohort.json")" "$(jq -r .root_raw_bytes "$delivery/receipts/cohort.json")"
    printf '| Image | Bytes | SHA256 |\n| --- | ---: | --- |\n'
    while IFS=$'\t' read -r file bytes sha; do
        printf '| `%s` | %s | `%s` |\n' "$file" "$bytes" "$sha"
    done < "$inventory"
    printf '\nDownload the images and compare `sha256sum FILE` with the table before installation. Verify product `uke`, matching slot-B stock firmware, partition capacities, your own backups and a working recovery route.\n\n'
    example=$(awk -F '\t' '$1 ~ /-system-.*\.img\.zst$/ {print $1;exit}' "$inventory")
    [[ -n $example ]] || release_fail 'No system image in checksum inventory'
    printf '**Flashing userdata destroys Android apps, files and encryption metadata.** Choose one desktop root. Example using `%s`, after checksum verification and the device checks:\n\n```sh\n' "$example"
    printf 'zstd -d %s -o system.img\nfastboot getvar product\nfastboot getvar current-slot\nfastboot getvar partition-size:userdata\nfastboot getvar partition-size:boot_b\nfastboot flash userdata system.img\nfastboot flash boot_b %s\n```\n\n' "$example" "$boot"
    printf 'Confirm boot_b is the intended target and retain matching slot-B firmware. Slot selection and reboot are separate manual steps in the verified device-specific procedure.\n\n'
    printf 'Preserve stock early firmware and calibration partitions. Restore only your own matching backups through your verified recovery route; changing slots alone does not restore userdata. No device write was performed by the builder.\n\n'
    printf 'Automatic kernel activation and SSH remain disabled. No private touch reference is included; firmware redistribution review remains required. KDE Plasma and NextKDE use Plasma Setup; GNOME uses GNOME Initial Setup. NextKDE services start only in a normal account after setup.\n\n'
    if grep -q -- '-cutefish-uke-senemos-system-' "$inventory"; then
        printf '**Cutefish only:** public test login `senemos`, initial password `fedora`. GDM requires a password change at first login. The real GDM worker/PAM change-password conversation was tested during assembly; the tablet graphical login remains unqualified. Automatic login, remote password login and passwordless sudo are disabled. Change the published test password before use.\n\n'
    elif [[ ${UKE_ALLOW_MISSING_CUTEFISH:-0} == 1 ]]; then
        printf '**Cutefish is currently unavailable.** Its separate validation must succeed before a compatible image is added. KDE Plasma, GNOME and NextKDE passed their independent image checks.\n\n'
    fi
    printf 'Exact manifests, RPM inventories, checksums and diagnostics remain in Actions artifacts, separately from the image-only release assets.\n'
    if [[ -n ${GITHUB_REPOSITORY:-} && -n $runs ]]; then
        local -a run_ids=()
        IFS=, read -r -a run_ids <<< "$runs"
        for run in "${run_ids[@]}"; do printf '\nBuild and artifact records: https://github.com/%s/actions/runs/%s\n' "$GITHUB_REPOSITORY" "$run"; done
    fi
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    command=${1:-}; shift || :
    case $command in
        names) release_names "$@";; stage) release_stage "$@";; verify) release_verify "$@";;
        inventory) release_inventory "$@";; body) release_body "$@";; cohort) release_cohort "$@";; desktop-set) release_desktop_set "$@";;
        *) release_fail 'Expected names, stage, verify, inventory, body or cohort';;
    esac
fi
