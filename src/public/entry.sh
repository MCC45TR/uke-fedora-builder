#!/usr/bin/env bash
# Public host orchestration; no connected device is opened.
# shellcheck disable=SC2034,SC2154
# shellcheck source=kernel-source.sh
# shellcheck disable=SC1091
source "$BUILDER/src/public/kernel-source.sh"
public_help() {
    cat <<'HELP'
Uke Fedora AArch64 source and image builder
Usage: ./ukelinux.sh [--build image|kernel] [options]
  --mode multiboot|singleboot        Root partition: linux or userdata
  --filesystem ext4|f2fs|btrfs|xfs   Single-device root filesystem
  --release 44|45|rawhide            Target Fedora version; default Rawhide
  --desktop kde|gnome|cutefish      Graphical session; Cutefish image setup is gated
  --shell bash|fish|zsh              New user login shell; default Bash
  --channel stable|testing|unstable Uke RPM channel; independent of Fedora version
  --kernel-rpm EVR|latest           Verified testing/unstable RPMs; unstable defaults to latest
  --kernel VERSION|latest|lastest   Linux version to build; latest is kernel.org's newest stable
                                    release and needs a reviewed Uke profile (default: policy version)
  --kernel-profile normal|el2-require|el2-exit-experimental
                                    Explicit kernel family; firmware exit is not admitted
  --skip-tests                     Defer kernel tests; keep source/payload integrity checks
  --out DIRECTORY                   Default: ./out in the invoking directory
  --linux-size MIB                  Root image size; default 16384, minimum 8192
  --jobs N, --jN                    Compiler workers; default all online CPUs
  --touch-reference FILE            Optional device-local 5432-byte reference
  --yes                             Consent to listed host preparation operations
  --offline                         Reuse prepared worker images and kernel inputs
  --reuse-kernel                    Image only: reuse the kernel from an earlier build of the same source
  --dry-run                         Print selections; no installation or build
  --self-test                       Run shell contract fixtures; no image build
  --help, -h                        Show this help

Supported Linux hosts: Ubuntu, Fedora, openSUSE, Arch Linux and Alpine;
x86_64 and AArch64. Bash bootstraps after confirmation on minimal hosts.
Image builds compile the pinned native kernel spec, then compose an empty root.
Kernel-only builds produce its source RPM, binary RPMs and both boot profiles.
Unstable Rawhide selections consume signed COPR kernels and image helpers.
Existing core, boot, boot-pair and --check-device commands remain available.
Run sudo dnf update --refresh after the first Fedora boot. This is required.
Build output is unqualified until its separate physical installation test.
HELP
}
public_choice() {
    local name=$1 prompt=$2 answer
    [[ ${selected[$name]:-0} == 0 ]] || return 0
    [[ -t 0 && $DRY_RUN == 0 && $UKE_ASSUME_YES == 0 ]] || return 0
    read -r -p "$prompt [${!name}]: " answer
    [[ -z $answer ]] || printf -v "$name" '%s' "$answer"
}
public_flash_help() {
    local partition=$1
    cat <<TEXT
Manual installation of this exact output (no command below was executed):
  1. Unlock the Uke bootloader and retain verified backups and a working recovery route.
     Confirm matching stock firmware in slot B. Preserve Android slot A and stock early firmware.
  2. Verify SHA256SUMS in the output directory. Enter bootloader fastboot, then inspect:
       fastboot getvar product
       fastboot getvar current-slot
       fastboot getvar partition-size:$partition
       fastboot getvar partition-size:boot_b
     Confirm the product is uke and both capacities cover the RAW sizes in manifest.json.
     For multiboot, the existing GPT partition must be named linux; this builder does not create it.
  3. Flash only after confirming the correct files and recovery backups:
TEXT
    if [[ $partition == userdata ]]; then
        printf '%s\n' '     WARNING: flashing userdata destroys Android apps, files and encryption metadata.'
    else
        printf '%s\n' '     WARNING: flashing linux replaces the existing Linux filesystem.'
    fi
    printf '       fastboot flash %s %s.img\n' "$partition" "$partition"
    printf '%s\n' '       fastboot flash boot_b boot.img' '       fastboot set_active b' '       fastboot reboot' \
        '  4. Complete the original desktop account setup.' \
        '     REQUIRED: run sudo dnf update --refresh in Fedora after the first boot.' \
        '     Automatic kernel activation stays disabled. Updates do not authorize a slot write.' \
        '     F2FS userdata grows offline during first boot; other formats retain the image size.'
}
public_main() {
    local target=image mode=multiboot filesystem=ext4 desktop=kde channel=testing fedora_release=rawhide login_shell=bash
    local output=$PWD/out out_given=0 reference='' root_mib=16384 key value argument prior='' kernel_request='' kernel_rpm=''
    local -A selected=()
    KERNEL_PROFILE=normal RUN_TESTS=1 KERNEL_CONFIG_SHA=''
    JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1) OFFLINE=0 DRY_RUN=0 UKE_ASSUME_YES=0 REUSE_KERNEL=0 ENGINE='' CID='' PAUSED=0
    # Preserve explicit historical commands without making them the default path.
    for argument in "$@"; do
        if [[ $argument == --check-device || $argument == --build=core || $argument == --build=boot || $argument == --build=boot-pair ||
              ( $prior == --build && ( $argument == core || $argument == boot || $argument == boot-pair ) ) ]]; then
            image_main "$@"; return
        fi
        prior=$argument
    done
    while (($#)); do
        key=''
        case $1 in
            --help|-h) public_help; return;;
            --self-test) bash "$BUILDER/tests/public-build-contract.sh"; return;;
            --skip-tests) RUN_TESTS=0;;
            --yes) UKE_ASSUME_YES=1;; --reuse-kernel) REUSE_KERNEL=1;; --offline) OFFLINE=1;; --dry-run) DRY_RUN=1;;
            --j[0-9]*) key=--jobs; value=${1#--j};;
            --release=*|--fedora-version=*|--shell=*|--build=*|--mode=*|--filesystem=*|--desktop=*|--channel=*|--kernel=*|--kernel-rpm=*|--kernel-profile=*|--out=*|--jobs=*|--linux-size=*|--touch-reference=*) key=${1%%=*}; value=${1#*=};;
            --release|--fedora-version|--shell|--build|--mode|--filesystem|--desktop|--channel|--kernel|--kernel-rpm|--kernel-profile|--out|--jobs|--linux-size|--touch-reference)
                key=$1; shift; (($#)) || die "Missing value for $key"; value=$1;;
            *) die "Unknown option: $1";;
        esac
        if [[ -n $key ]]; then [[ -n $value && $value != --* ]] || die "Missing value for $key"; fi
        case $key in
            --release|--fedora-version) fedora_release=$value; selected[fedora_release]=1;;
            --shell) login_shell=$value; selected[login_shell]=1;;
            --build) target=$value; selected[target]=1;; --mode) mode=$value; selected[mode]=1;;
            --filesystem) filesystem=$value; selected[filesystem]=1;;
            --desktop) desktop=$value; selected[desktop]=1;; --channel) channel=$value; selected[channel]=1;; --out) output=$value; out_given=1;;
            --kernel) kernel_request=$value;;
            --kernel-rpm) kernel_rpm=$value;;
            --kernel-profile) KERNEL_PROFILE=$value;;
            --jobs) JOBS=$value;; --linux-size) root_mib=$value;; --touch-reference) reference=$value;;
        esac
        shift
    done
    public_choice target 'Build image or kernel'
    public_choice fedora_release 'Fedora target: 44, 45 or rawhide'
    if [[ $target == image ]]; then
        public_choice mode 'Boot mode: multiboot or singleboot'
        public_choice filesystem 'Root filesystem: ext4, f2fs, btrfs or xfs'
        public_choice desktop 'Desktop: kde, gnome or cutefish'
        public_choice login_shell 'New user shell: bash, fish or zsh'
    fi
    public_choice channel 'Package channel: stable, testing or unstable'
    ((out_given)) || public_choice output 'Output directory'
    case $target in image|kernel) :;; *) die 'Build target must be image or kernel';; esac
    case $mode in multiboot|singleboot) :;; *) die 'Mode must be multiboot or singleboot';; esac
    case $filesystem in ext4|f2fs|btrfs|xfs) :;; *) die 'Unsupported root filesystem';; esac
    case $fedora_release in 44|45|rawhide) :;; *) die 'Fedora target must be 44, 45 or rawhide';; esac
    case $desktop in kde|gnome|cutefish) :;; *) die 'Desktop must be kde, gnome or cutefish';; esac
    case $login_shell in bash|fish|zsh) :;; *) die 'Login shell must be bash, fish or zsh';; esac
    if [[ $target == kernel && ( ${selected[desktop]:-0} == 1 || ${selected[login_shell]:-0} == 1 ) ]]; then
        die 'Desktop and login shell apply only to image builds'
    fi
    case $channel in stable|testing|unstable) :;; *) die 'Unknown package channel';; esac
    case $KERNEL_PROFILE in
        normal|el2-require) ;;
        el2-exit-experimental) die 'Firmware exit is not admitted: exact Uke firmware/ownership contract is unverified';;
        *) die 'Unknown kernel profile';;
    esac
    [[ $KERNEL_PROFILE == normal || $channel == testing ]] || die 'EL2 candidates require --channel testing'
    [[ -z $kernel_request || $kernel_request =~ ^(latest|lastest|[0-9]+\.[0-9]+(\.[0-9]+)?)$ ]] ||
        die 'Kernel must be an explicit version such as 7.2.12, latest or lastest'
    if [[ $channel == unstable && $fedora_release == rawhide ]]; then
        [[ -z $kernel_request && $REUSE_KERNEL == 0 ]] || die 'Unstable consumes signed COPR kernels; use --kernel-rpm for an exact release'
        [[ -n $kernel_rpm ]] || kernel_rpm=latest
    fi
    if [[ -n $kernel_rpm ]]; then
        [[ $kernel_rpm == latest || $kernel_rpm =~ ^7[.]3[.][0-9]+-[1-9][0-9]*[.]fc46$ ]] || die 'Kernel RPM must be latest or an exact 7.3.x-N.fc46 release'
        [[ ( ($target == image && $channel == testing) || $channel == unstable ) && $fedora_release == rawhide && $KERNEL_PROFILE == normal && $REUSE_KERNEL == 0 && -z $kernel_request ]] || die 'Repository kernel requires a normal Rawhide testing image or unstable selection without source/reuse options'
        [[ -z ${UKE_KERNEL_REPO:-} || $UKE_KERNEL_REPO == none ]] || die 'Repository kernel cannot use a local kernel source'
    fi
    [[ $REUSE_KERNEL == 0 || $target == image ]] || die '--reuse-kernel applies to image builds only'
    [[ $JOBS =~ ^[1-9][0-9]{0,3}$ ]] || die 'Jobs must be a positive integer'
    local processors; processors=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)
    ((JOBS <= processors)) || die "Jobs must not exceed the $processors online CPUs"
    [[ $root_mib =~ ^[1-9][0-9]{3,4}$ ]] || die 'Root size must be 8192..65536 MiB'
    ((root_mib >= 8192 && root_mib <= 65536)) || die 'Root size must be 8192..65536 MiB'
    [[ -n $output && $output != *:* && $output != *,* && $output != *$'\n'* ]] || die 'Output path must be nonempty and contain no colon, comma or newline'
    if [[ -n $reference ]]; then
        [[ $target == image && -f $reference && ! -L $reference ]] || die 'Touch reference must be a regular file for an image build'
        [[ $(stat -c %s "$reference") == 5432 && $(stat -c %a "$reference") == 600 ]] || die 'Touch reference must be exactly 5432 bytes with mode 0600'
    fi
    local partition=linux
    [[ $mode != singleboot ]] || partition=userdata
    local release_label=$fedora_release
    [[ $fedora_release != rawhide ]] || release_label=Rawhide
    say "$target: Fedora $release_label AArch64; $mode; $filesystem; $desktop; $channel; $JOBS workers"
    say "Fedora chroot: fedora-$fedora_release-aarch64; new user shell: $login_shell; RPM dist resolved in target worker"
    say "Root target: $partition; userdata flashing destroys Android data; linux must already exist. Builds never flash."
    [[ $desktop != cutefish || $target != image ]] || say 'Image support: blocked until Cutefish graphical login and first-account setup are validated'
    say "Output parent: $output (a new run directory is created; existing output is preserved)"
    say "Kernel profile: $KERNEL_PROFILE; kernel tests enabled: $RUN_TESTS"
    [[ -z $kernel_rpm ]] || say "Kernel input: signed $channel RPMs ($kernel_rpm), with signature and matching boot/module checks"
    say 'REQUIRED after first Fedora boot: sudo dnf update --refresh'
    # An explicit local checkout must be valid; it is never silently ignored.
    local kernel_repo=''
    FEDORA_TARGET=$fedora_release UKE_CACHE_CHANNEL=$channel
    local cache_root=$output/cache/fedora-$fedora_release-$channel
    if [[ -n ${UKE_KERNEL_REPO:-} && $UKE_KERNEL_REPO != none ]]; then kernel_repo=$(kernel_repo_validate "$UKE_KERNEL_REPO") || exit 1; fi
    if [[ -n $kernel_repo ]]; then say "Kernel: ${kernel_request:-the policy default version}; source: local checkout $kernel_repo"
    else say "Kernel: ${kernel_request:-the policy default version}; source: the policy repository, resolved once when the build starts"; fi
    ((REUSE_KERNEL == 0)) || say 'Kernel: reusing the cached build of this source; a missing cache stops the build'
    ((DRY_RUN == 0)) || return 0
    [[ $channel != unstable || $fedora_release == rawhide ]] || die 'Unstable packages are available only for Fedora Rawhide AArch64'
    [[ $target != image || $fedora_release == rawhide ]] || die "Unsupported Fedora $fedora_release image: signed native Uke family builds and complete dependency resolution are pending; no Rawhide RPM fallback is allowed"
    [[ $target != image || $desktop != cutefish ]] || die 'Unsupported image: Cutefish packages are built separately in mcc45tr/cutefish; graphical login and secure first-account setup are not validated'
    bootstrap
    architecture=$(uname -m)
    case $architecture in x86_64) host_platform=linux/amd64;; aarch64) host_platform=linux/arm64;; *) die 'Supported architectures: x86_64 and AArch64';; esac
    output=$(realpath -m -- "$output")
    mkdir -p -- "$output"
    [[ -d $output && ! -L $output ]] || die 'Output parent must be a real directory'
    exec 9>> "$output/.ukelinux.lock"
    flock -n 9 || die 'Another build is using this output directory'
    local available required
    available=$(df -Pk "$output" | awk 'NR==2 {print $4}')
    required=65536
    [[ $target != image ]] || required=$((65536 + root_mib * 3))
    [[ -z $kernel_rpm ]] || required=$((16384 + root_mib * 2))
    ((available >= required * 1024)) || die "At least $required MiB of free space is required"
    WORK=$(mktemp -d "$output/$target-fedora-$fedora_release-$channel-XXXXXXXX")
    chmod 700 "$WORK"
    [[ $(stat -c %a "$WORK") == 700 && $(stat -c %u "$WORK") == "$(id -u)" ]] || die 'Output filesystem must enforce a private, user-owned mode-0700 run directory'
    trap cleanup EXIT
    mkdir -p "$WORK/artifacts" "$WORK/recipe" "$WORK/inputs" "$output/cache"
    # Freeze the source recipe before any container operation.
    cp -a "$BUILDER/src" "$BUILDER/configs" "$BUILDER/tests" "$WORK/recipe/"
    # Resolve the kernel version and source revision once; every stage and the cache use these exact values.
    local policy_file=$WORK/recipe/configs/public-build.json kernel_url bundle='' kernel_ref
    kernel_ref=$(jq -er --arg profile "$KERNEL_PROFILE" '.kernel.profiles[$profile].ref // .kernel.ref' "$policy_file")
    KERNEL_CONFIG_SHA=$(jq -r --arg profile "$KERNEL_PROFILE" '.kernel.profiles[$profile].native_config_sha256 // empty' "$policy_file")
    [[ -n $kernel_request ]] || kernel_request=$(jq -er --arg profile "$KERNEL_PROFILE" '.kernel.profiles[$profile].default_version // .kernel.default_version' "$policy_file")
    if [[ -n $kernel_rpm ]]; then
        # Initial policy context only; signed payload metadata replaces this before root composition.
        KERNEL_VERSION=$kernel_request
    else
        KERNEL_VERSION=$(kernel_version_resolve "$kernel_request" "$WORK/inputs/releases.json" "$cache_root/releases/releases.json" "$OFFLINE") || exit 1
    fi
    kernel_url=$(jq -er .kernel.url "$policy_file")
    if [[ -n $kernel_repo ]]; then
        KERNEL_COMMIT=$(git -C "$kernel_repo" rev-parse HEAD)
        if [[ -f $kernel_repo/packaging/native/native.config ]]; then
            KERNEL_CONFIG_SHA=$(sha256sum "$kernel_repo/packaging/native/native.config" | cut -d ' ' -f1)
        fi
        kernel_repo_bundle "$kernel_repo" "$WORK/inputs/kernel.bundle"
        bundle=inputs/kernel.bundle
    elif [[ -n $kernel_rpm ]]; then
        KERNEL_COMMIT=$kernel_ref
    else
        KERNEL_COMMIT=$(kernel_commit_resolve "$kernel_url" "$kernel_ref" "$OFFLINE" "$cache_root") || exit 1
    fi
    say "Kernel source ${KERNEL_COMMIT:0:12}, Linux $KERNEL_VERSION (requested: $kernel_request)"
    jq -n --arg target "$target" --arg mode "$mode" --arg fs "$filesystem" --arg desktop "$desktop" \
        --arg release "$fedora_release" --arg shell "$login_shell" --arg channel "$channel" --arg partition "$partition" --argjson size "$root_mib" \
        --argjson jobs "$JOBS" --arg builder "$(git -C "$BUILDER" rev-parse HEAD)" --arg commit "$KERNEL_COMMIT" \
        --arg profile "$KERNEL_PROFILE" --arg config "$KERNEL_CONFIG_SHA" --argjson tests "$RUN_TESTS" \
        --arg kernel_rpm "$kernel_rpm" --arg version "$KERNEL_VERSION" --arg requested "$kernel_request" --arg url "$kernel_url" --arg bundle "$bundle" \
        '{device:"uke",architecture:"aarch64",distribution:"fedora",fedora_release:$release,release:$release,default_shell:$shell,copr_chroot:("fedora-"+$release+"-aarch64"),source_checked:false,rpm_transaction_validated:false,image_built:false,vm_tested:false,tablet_tested:false,target:$target,mode:$mode,filesystem:$fs,desktop:$desktop,channel:$channel,partition:$partition,size_mib:$size,jobs:$jobs,builder_commit:$builder,
          kernel_commit:$commit,kernel_version:$version,kernel_requested:$requested,kernel_url:$url,kernel_rpm_request:$kernel_rpm,kernel_profile:$profile,kernel_native_config_sha256:$config,run_kernel_tests:($tests==1)}
         + (if $bundle == "" then {} else {kernel_bundle:$bundle} end)' > "$WORK/request.json"
    if [[ -n $reference ]]; then install -m600 "$reference" "$WORK/inputs/reference.bin"; fi
    local native_image arm_image native_base arm_base recipe_sha arm_recipe=Containerfile.public native_recipe=Containerfile.public-native
    [[ -z $kernel_rpm ]] || arm_recipe=Containerfile.public-repository
    if [[ $channel == unstable ]]; then arm_recipe=Containerfile.public-unstable; native_recipe=$arm_recipe; fi
    native_base=$(jq -er --arg release "$fedora_release" --arg arch "$architecture" '.fedora_targets[$release].images[$arch]' "$WORK/recipe/configs/build-rules.json")
    arm_base=$(jq -er --arg release "$fedora_release" '.fedora_targets[$release].images.aarch64' "$WORK/recipe/configs/build-rules.json")
    recipe_sha=$({ printf '%s\n' "$fedora_release" "$native_base" "$arm_base" "$arm_recipe"; cat "$WORK/recipe/configs/Containerfile.public" "$WORK/recipe/configs/Containerfile.public-native" "$WORK/recipe/configs/Containerfile.public-repository" "$WORK/recipe/configs/Containerfile.public-unstable" "$WORK/recipe/configs/public-build.json" "$WORK/recipe/configs/build-rules.json"; } | sha256sum | cut -d ' ' -f1)
    native_image=localhost/uke-public-native:${recipe_sha:0:16}-$architecture
    arm_image=localhost/uke-public-arm64:${recipe_sha:0:16}
    public_worker "$native_image" "$host_platform" "$native_base" "$native_recipe"
    TEST_IMAGE=$arm_base
    "$ENGINE" image inspect "$arm_base" >/dev/null 2>&1 || { ((OFFLINE == 0)) && "$ENGINE" pull --platform linux/arm64 "$arm_base"; }
    if [[ $architecture == x86_64 ]]; then
        "$ENGINE" run --rm --network=none --security-opt label=disable -v "$WORK:/job" "$native_image" \
            cp /usr/bin/qemu-aarch64-static /job/inputs/qemu-aarch64-static
        UKE_AARCH64_INTERPRETER=$WORK/inputs/qemu-aarch64-static
        prepare_aarch64
    fi
    public_worker "$arm_image" linux/arm64 "$arm_base" "$arm_recipe"
    # x86_64 hosts run every step that executes no AArch64 code in a native worker; the
    # host's binfmt handler still runs RPM scriptlets and chroot commands. UKE_CROSS=0 emulates all steps.
    local cross=0 cross_image=localhost/uke-public-cross:${recipe_sha:0:16} root_image=$arm_image root_platform=linux/arm64
    # shortcut: KVM helpers build on AArch64; enable cross after porting their prebuilt paths.
    if [[ $architecture == x86_64 && ${UKE_CROSS:-1} != 0 && $KERNEL_PROFILE == normal && $channel != unstable ]]; then
        cross=1 root_image=$cross_image root_platform=$host_platform
        public_worker "$cross_image" "$host_platform" "$native_base" Containerfile.public
    fi
    if [[ -n $kernel_rpm ]]; then
        public_stage "$arm_image" linux/arm64 repository-kernel
    else
    # The cache identifies the producer: route, recipe and the worker images that compile the kernel and link its initramfs.
    local producer_file=$WORK/producer.json arm_id kernel_recipe
    kernel_recipe=$(kernel_recipe_hash "$WORK/recipe")
    arm_id=$("$ENGINE" image inspect --format '{{.Id}}' "$arm_image")
    if ((cross)); then
        kernel_producer_json cross "$kernel_recipe" "$("$ENGINE" image inspect --format '{{.Id}}' "$cross_image")" "$arm_id" > "$producer_file"
    elif [[ $architecture == x86_64 ]]; then
        kernel_producer_json emulated "$kernel_recipe" "$arm_id" > "$producer_file"
    else
        kernel_producer_json native "$kernel_recipe" "$arm_id" > "$producer_file"
    fi
    KERNEL_PRODUCER_SHA=$(kernel_producer_sha "$producer_file")
    if ((REUSE_KERNEL)); then
        kernel_cache_restore
    else
        if ((cross)); then
            say "Cross-compiling the AArch64 kernel natively on $JOBS CPUs; only AArch64 userspace steps are emulated"
            public_stage "$cross_image" "$host_platform" kernel-source
            public_stage "$arm_image" linux/arm64 kernel-base
            public_stage "$cross_image" "$host_platform" kernel-build
        else
            say 'Compiling the native AArch64 kernel; x86_64 workers use explicit emulation'
            public_stage "$arm_image" linux/arm64 kernel
        fi
        install -m644 "$producer_file" "$WORK/artifacts/kernel/producer.json"
        kernel_cache_save
    fi
    fi
    # A reused kernel keeps the producer that built it, not the workers of this run.
    jq --slurpfile producer "$WORK/artifacts/kernel/producer.json" '. + {kernel_producer:$producer[0]}' \
        "$WORK/artifacts/manifest.json" > "$WORK/manifest.tmp"
    mv "$WORK/manifest.tmp" "$WORK/artifacts/manifest.json"
    if [[ $target == image ]]; then
        if [[ $channel == stable ]]; then
            say 'Building the pinned platform source families missing from the stable repository'
            public_stage "$arm_image" linux/arm64 hardware
        fi
        ((cross == 0)) || say 'Installing the AArch64 root with native dnf; only package scriptlets are emulated'
        public_stage "$root_image" "$root_platform" root
        if [[ $channel == unstable ]]; then public_stage "$arm_image" linux/arm64 filesystem
        else public_stage "$native_image" "$host_platform" filesystem; fi
    fi
    local image_tools=null
    [[ $channel != unstable ]] || image_tools=$(cat "$WORK/artifacts/tools/manifest.json")
    jq --argjson tools "$image_tools" --arg native "$("$ENGINE" image inspect --format '{{.Id}}' "$native_image")" \
        --arg arm "$("$ENGINE" image inspect --format '{{.Id}}' "$arm_image")" \
        --arg cross "$( ((cross == 0)) || "$ENGINE" image inspect --format '{{.Id}}' "$cross_image")" \
        '. + {native_worker:$native,aarch64_worker:$arm} + (if $cross == "" then {} else {cross_worker:$cross} end)
         + (if $tools == null then {} else {image_tools:$tools} end)' \
        "$WORK/artifacts/manifest.json" > "$WORK/manifest.tmp"
    mv "$WORK/manifest.tmp" "$WORK/artifacts/manifest.json"
    if [[ $target == image ]]; then public_flash_help "$partition" > "$WORK/artifacts/FLASHING.txt";
    else
        cat > "$WORK/artifacts/FLASHING.txt" <<'TEXT'
Kernel-only manual installation (none of these commands was executed):
  Retain verified boot_b backups, a working recovery route and matching stock B firmware.
  Copy the exact kernel RPM set into the existing compatible Fedora installation.
  Install its core/modules/dtbs/boot and parent RPMs together using sudo dnf install
  with their explicit local paths. Add the singleboot RPM only for userdata roots.
  Keep automatic activation disabled. Confirm the installed module release matches
  manifest.json before leaving Fedora; a boot image alone is insufficient.
  In bootloader fastboot, verify product=uke and the actual boot_b capacity:
    fastboot getvar product
    fastboot getvar current-slot
    fastboot getvar partition-size:boot_b
  For an existing multiboot linux root:
    fastboot flash boot_b boot-linux.img
  For an existing singleboot userdata root, use this alternative instead:
    fastboot flash boot_b boot-userdata.img
  After choosing the image matching the installed root and module tuple:
    fastboot set_active b
    fastboot reboot
  Preserve boot_a, all root data, persist and stock early firmware.
  REQUIRED in Fedora after boot: sudo dnf update --refresh
TEXT
    fi
    (cd "$WORK/artifacts" || exit; find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 -P "$JOBS" -n 4 sha256sum | LC_ALL=C sort -k2 > ../SHA256SUMS)
    mv "$WORK/SHA256SUMS" "$WORK/artifacts/SHA256SUMS"
    say "Completed host output: $WORK/artifacts"
    cat "$WORK/artifacts/FLASHING.txt"
}
public_worker() {
    local image=$1 platform=$2 base=$3 file=$4
    if "$ENGINE" image inspect "$image" >/dev/null 2>&1; then return; fi
    ((OFFLINE == 0)) || die "Offline worker missing: $image; prepare it online first"
    "$ENGINE" build --platform "$platform" --build-arg "BASE_IMAGE=$base" \
        -t "$image" -f "$WORK/recipe/configs/$file" "$WORK/recipe/configs"
}
public_stage() {
    local image=$1 platform=$2 stage=$3 result owner=none
    local network=none
    ((OFFLINE)) || network=bridge
    if [[ $ENGINE == docker ]] && ! "$ENGINE" info --format '{{json .SecurityOptions}}' | jq -e 'any(.[]; contains("rootless"))' >/dev/null; then
        owner=$(id -u):$(id -g)
    fi
    local devices=()
    [[ $stage != root ]] || devices+=(--privileged)
    # Only the filesystem appliance benefits from hardware virtualization; it falls back to TCG without it.
    if [[ $stage == filesystem && $platform == "$host_platform" && -r /dev/kvm && -w /dev/kvm ]]; then devices=(--device /dev/kvm); fi
    mkdir -p "$output/cache/fedora-$fedora_release-$channel"
    wait_idle
    CID=$("$ENGINE" create --platform "$platform" --network="$network" --security-opt label=disable ${devices[@]+"${devices[@]}"} \
        --cpus="$JOBS" -v "$WORK:/job" -v "$WORK/recipe:/builder:ro" -v "$output/cache/fedora-$fedora_release-$channel:/cache" \
        -e "UKE_OFFLINE=$OFFLINE" -e "UKE_OUTPUT_OWNER=$owner" "$image" bash /builder/src/public/stage.sh "$stage")
    "$ENGINE" start -a "$CID" 2>&1 | tee "$WORK/$stage.log"
    result=$("$ENGINE" inspect --format '{{.State.ExitCode}}' "$CID")
    "$ENGINE" rm "$CID" >/dev/null; CID=''
    [[ $result == 0 ]] || die "Stage $stage failed; inspect $WORK/$stage.log"
}
