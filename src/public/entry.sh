#!/usr/bin/env bash
# Public host orchestration; no connected device is opened.
# shellcheck disable=SC2034,SC2154
public_help() {
    cat <<'HELP'
Uke Fedora AArch64 source and image builder
Usage: ./ukelinux.sh [--build image|kernel] [options]
  --mode multiboot|singleboot        Root partition: linux or userdata
  --filesystem ext4|f2fs|btrfs|xfs   Single-device root filesystem
  --desktop kde|gnome               Original Fedora desktop
  --channel stable|testing|unstable Uke RPM channel (Fedora remains Rawhide)
  --out DIRECTORY                   Default: ./out in the invoking directory
  --linux-size MIB                  Root image size; default 16384, minimum 8192
  --jobs N, --jN                    Parallel workers; default: available CPUs
  --touch-reference FILE            Private image with the device's 5432-byte reference
  --defer-touch-reference           Omit private data; provision touch locally before setup
  --yes                             Consent to listed host preparation operations
  --offline                         Reuse prepared worker images and kernel inputs
  --dry-run                         Print selections; no installation or build
  --self-test                       Run shell contract fixtures; no image build
  --help, -h                        Show this help

Supported Linux hosts: Ubuntu, Fedora, openSUSE, Arch Linux and Alpine;
x86_64 and AArch64. Bash bootstraps after confirmation on minimal hosts.
Testing images use the latest signed COPR mainline kernel and an empty root.
Other image channels compile the pinned native kernel spec before composition.
Kernel-only builds produce its source RPM, binary RPMs and both boot profiles.
Existing core, boot, boot-pair and --check-device commands remain available.
Run sudo dnf update --refresh after the first Fedora boot. This is required.
Build output is unqualified until its separate physical installation test.
Image builds need the device's accepted touch reference for account setup.
Redistributable images use --defer-touch-reference and require local provisioning.
USB keyboard/mouse setup is not supported by the current hardware profile.
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
    local partition=$1 defer_reference=${2:-0}
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
    printf '%s\n' '       fastboot flash boot_b boot.img' '       fastboot set_active b' '       fastboot reboot'
    if ((defer_reference)); then
        printf '%s\n' '  4. Before account setup, provision the target tablet with its own accepted 5432-byte touch reference' \
            '     at /var/lib/uke-touch/reference.bin with owner root:root and mode 0600.' \
            '     The image contains no touch reference. Touch startup remains conditional on this file.' \
            '     A working local provisioning/recovery route is required; USB setup is not qualified.'
    else
        printf '%s\n' '  4. Use this private image only on the device that supplied its touch reference.' \
            '     Complete the original desktop account setup using the touchscreen.'
    fi
    printf '%s\n' \
        '     REQUIRED: run sudo dnf update --refresh in Fedora after the first boot.' \
        '     Automatic kernel activation stays disabled. Updates do not authorize a slot write.' \
        '     The initial raw filesystem size is recorded in manifest.json.' \
        '     Growth follows the installed Uke filesystem policy; physical growth was not tested by this build.'
}
public_main() {
    local target=image mode=multiboot filesystem=ext4 desktop=kde channel=testing
    local output=$PWD/out out_given=0 reference='' defer_reference=0 root_mib=16384 key value argument prior=''
    local -A selected=()
    JOBS=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1\n')
    OFFLINE=0 DRY_RUN=0 UKE_ASSUME_YES=0 ENGINE='' CID='' PAUSED=0
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
            --yes) UKE_ASSUME_YES=1;; --offline) OFFLINE=1;; --dry-run) DRY_RUN=1;;
            --defer-touch-reference) defer_reference=1;;
            --j[0-9]*) key=--jobs; value=${1#--j};;
            --build=*|--mode=*|--filesystem=*|--desktop=*|--channel=*|--out=*|--jobs=*|--linux-size=*|--touch-reference=*) key=${1%%=*}; value=${1#*=};;
            --build|--mode|--filesystem|--desktop|--channel|--out|--jobs|--linux-size|--touch-reference)
                key=$1; shift; (($#)) || die "Missing value for $key"; value=$1;;
            *) die "Unknown option: $1";;
        esac
        if [[ -n $key ]]; then [[ -n $value && $value != --* ]] || die "Missing value for $key"; fi
        case $key in
            --build) target=$value; selected[target]=1;; --mode) mode=$value; selected[mode]=1;;
            --filesystem) filesystem=$value; selected[filesystem]=1;;
            --desktop) desktop=$value; selected[desktop]=1;; --channel) channel=$value; selected[channel]=1;; --out) output=$value; out_given=1;;
            --jobs) JOBS=$value;; --linux-size) root_mib=$value;; --touch-reference) reference=$value;;
        esac
        shift
    done
    public_choice target 'Build image or kernel'
    if [[ $target == image ]]; then
        public_choice mode 'Boot mode: multiboot or singleboot'
        public_choice filesystem 'Root filesystem: ext4, f2fs, btrfs or xfs'
        public_choice desktop 'Desktop: kde or gnome'
    fi
    public_choice channel 'Package channel: stable, testing or unstable'
    ((out_given)) || public_choice output 'Output directory'
    case $target in image|kernel) :;; *) die 'Build target must be image or kernel';; esac
    case $mode in multiboot|singleboot) :;; *) die 'Mode must be multiboot or singleboot';; esac
    case $filesystem in ext4|f2fs|btrfs|xfs) :;; *) die 'Unsupported root filesystem';; esac
    case $desktop in kde|gnome) :;; *) die 'Desktop must be kde or gnome';; esac
    case $channel in stable|testing|unstable) :;; *) die 'Unknown package channel';; esac
    [[ $JOBS =~ ^[1-9][0-9]*$ ]] || die 'Jobs must be a positive integer'
    [[ $root_mib =~ ^[1-9][0-9]{3,4}$ ]] || die 'Root size must be 8192..65536 MiB'
    ((root_mib >= 8192 && root_mib <= 65536)) || die 'Root size must be 8192..65536 MiB'
    [[ -n $output && $output != *:* && $output != *,* && $output != *$'\n'* ]] || die 'Output path must be nonempty and contain no colon, comma or newline'
    if ((defer_reference)); then
        [[ $target == image && -z $reference ]] || die 'Deferred touch provisioning is image-only and cannot include --touch-reference'
    fi
    if [[ -n $reference ]]; then
        [[ $target == image && -f $reference && ! -L $reference ]] || die 'Touch reference must be a regular file for an image build'
        [[ $(stat -c %s "$reference") == 5432 && $(stat -c %a "$reference") == 600 ]] || die 'Touch reference must be exactly 5432 bytes with mode 0600'
    fi
    local partition=linux
    [[ $mode != singleboot ]] || partition=userdata
    say "$target: Fedora Rawhide AArch64; $mode; $filesystem; $desktop; $channel; $JOBS workers"
    say "Output parent: $output (a new run directory is created; existing output is preserved)"
    say 'Testing images use the latest signed mainline kernel from uke-linux-test; source builds retain the explicit kernel pin.'
    say 'REQUIRED after first Fedora boot: sudo dnf update --refresh'
    ((DRY_RUN == 0)) || return 0
    [[ $target != image || -n $reference || $defer_reference == 1 ]] || die 'Image account setup requires --touch-reference or explicit --defer-touch-reference; USB input is not yet supported'
    bootstrap
    architecture=$(uname -m)
    case $architecture in x86_64) host_platform=linux/amd64;; aarch64) host_platform=linux/arm64;; *) die 'Supported architectures: x86_64 and AArch64';; esac
    output=$(realpath -m -- "$output")
    mkdir -p -- "$output"
    [[ -d $output && ! -L $output ]] || die 'Output parent must be a real directory'
    exec 9> "$output/.ukelinux.lock"
    flock -n 9 || die 'Another build is using this output directory'
    local available required
    available=$(df -Pk "$output" | awk 'NR==2 {print $4}')
    required=65536
    [[ $target != image ]] || required=$((65536 + root_mib * 3))
    ((available >= required * 1024)) || die "At least $required MiB of free space is required"
    WORK=$(mktemp -d "$output/$target-$channel-XXXXXXXX")
    chmod 700 "$WORK"
    [[ $(stat -c %a "$WORK") == 700 && $(stat -c %u "$WORK") == "$(id -u)" ]] || die 'Output filesystem must enforce a private, user-owned mode-0700 run directory'
    trap cleanup EXIT
    mkdir -p "$WORK/artifacts" "$WORK/recipe" "$WORK/inputs" "$output/cache"
    # Freeze the source recipe before any container operation.
    cp -a "$BUILDER/src" "$BUILDER/configs" "$BUILDER/tests" "$WORK/recipe/"
    (cd "$WORK" && find recipe -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) > "$WORK/recipe.SHA256SUMS"
    jq -n --arg target "$target" --arg mode "$mode" --arg fs "$filesystem" --arg desktop "$desktop" \
        --arg channel "$channel" --arg partition "$partition" --argjson size "$root_mib" \
        --argjson jobs "$JOBS" --argjson defer_reference "$defer_reference" --arg builder "$(git -C "$BUILDER" rev-parse HEAD)" \
        '{device:"uke",architecture:"aarch64",distribution:"fedora",release:"rawhide",target:$target,mode:$mode,filesystem:$fs,desktop:$desktop,channel:$channel,partition:$partition,size_mib:$size,jobs:$jobs,builder_commit:$builder,defer_touch_reference:($defer_reference==1)}' > "$WORK/request.json"
    if [[ -n $reference ]]; then install -m600 "$reference" "$WORK/inputs/reference.bin"; fi
    local native_image arm_image native_base arm_base recipe_sha
    native_base=$(jq -er --arg arch "$architecture" '.fedora_rawhide_images[$arch]' "$WORK/recipe/configs/build-rules.json")
    arm_base=$(jq -er '.fedora_rawhide_images.aarch64' "$WORK/recipe/configs/build-rules.json")
    recipe_sha=$(cat "$WORK/recipe/configs/Containerfile.public" "$WORK/recipe/configs/Containerfile.public-native" "$WORK/recipe/configs/public-build.json" "$WORK/recipe/configs/build-rules.json" | sha256sum | cut -d ' ' -f1)
    native_image=localhost/uke-public-native:${recipe_sha:0:16}-$architecture
    arm_image=localhost/uke-public-arm64:${recipe_sha:0:16}
    public_worker "$native_image" "$host_platform" "$native_base" Containerfile.public-native
    local repository_kernel=0
    [[ $target != image || $channel != testing ]] || repository_kernel=1
    if ((repository_kernel)); then
        arm_image=$native_image
    else
    TEST_IMAGE=$arm_base
    "$ENGINE" image inspect "$arm_base" >/dev/null 2>&1 || { ((OFFLINE == 0)) && "$ENGINE" pull --platform linux/arm64 "$arm_base"; }
    if [[ $architecture == x86_64 ]]; then
        "$ENGINE" run --rm --network=none --security-opt label=disable -v "$WORK:/job" "$native_image" \
            cp /usr/bin/qemu-aarch64-static /job/inputs/qemu-aarch64-static
        UKE_AARCH64_INTERPRETER=$WORK/inputs/qemu-aarch64-static
        prepare_aarch64
    fi
    public_worker "$arm_image" linux/arm64 "$arm_base" Containerfile.public
    fi
    native_image=$(public_snapshot_worker "$native_image")
    arm_image=$(public_snapshot_worker "$arm_image")
    (cd "$WORK" && sha256sum inputs/worker-*.tar) > "$WORK/inputs/worker-archives.sha256"
    if ((repository_kernel)); then
        say 'Retrieving the latest signed AArch64 mainline kernel from uke-linux-test'
        public_stage "$arm_image" "$host_platform" kernel
    else
        say 'Compiling the native AArch64 kernel; x86_64 workers use explicit emulation'
        public_stage "$arm_image" linux/arm64 kernel
    fi
    if [[ $target == image ]]; then
        if [[ $channel == stable ]]; then
            say 'Building the pinned platform source families missing from the stable repository'
            public_stage "$arm_image" linux/arm64 hardware
        fi
        local root_platform=linux/arm64
        ((repository_kernel == 0)) || root_platform=$host_platform
        public_stage "$arm_image" "$root_platform" root
        public_stage "$native_image" "$host_platform" filesystem
    fi
    jq --arg native "$native_image" --arg arm "$arm_image" \
        --arg recipe "$(sha256sum "$WORK/recipe.SHA256SUMS" | cut -d ' ' -f1)" \
        '. + {native_worker:$native,aarch64_worker:$arm,recipe_checksums_sha256:$recipe,
          worker_archives:{native:("inputs/worker-"+($native|ltrimstr("sha256:"))+".tar"),
                           aarch64:("inputs/worker-"+($arm|ltrimstr("sha256:"))+".tar")},
          release_reproducibility_tested:false}' "$WORK/artifacts/manifest.json" > "$WORK/manifest.tmp"
    mv "$WORK/manifest.tmp" "$WORK/artifacts/manifest.json"
    if [[ $target == image ]]; then public_flash_help "$partition" "$defer_reference" > "$WORK/artifacts/FLASHING.txt";
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
    (cd "$WORK/artifacts" || exit; find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > ../SHA256SUMS)
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
public_snapshot_worker() {
    local image archive
    image=$("$ENGINE" image inspect --format '{{.Id}}' "$1") || return
    image=sha256:${image#sha256:}
    [[ $image =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
    archive=$WORK/inputs/worker-${image#sha256:}.tar
    if [[ ! -f $archive ]]; then
        "$ENGINE" save --output "$archive.part" "$image" >&2 || return
        mv -- "$archive.part" "$archive" || return
    fi
    printf '%s\n' "$image"
}
public_stage() {
    local image=$1 platform=$2 stage=$3 result owner=none
    local network=none
    ((OFFLINE)) || network=bridge
    if [[ $ENGINE == docker ]] && ! "$ENGINE" info --format '{{json .SecurityOptions}}' | jq -e 'any(.[]; contains("rootless"))' >/dev/null; then
        owner=$(id -u):$(id -g)
    fi
    wait_idle
    local -a capabilities=() stage_command=(bash /builder/src/public/stage.sh "$stage")
    # A distinct user namespace keeps rootful and concurrent workers' binfmt separate.
    if [[ $stage == root && $platform == linux/amd64 ]]; then
        capabilities+=(--cap-add SYS_ADMIN)
        stage_command=(bash /builder/src/public/worker-namespace.sh "${stage_command[@]}")
    fi
    CID=$("$ENGINE" create --platform "$platform" --network="$network" --security-opt label=disable "${capabilities[@]}" \
        --cpus="$JOBS" -v "$WORK:/job" -v "$WORK/recipe:/builder:ro" -v "$output/cache:/cache" \
        -e "UKE_OFFLINE=$OFFLINE" -e "UKE_OUTPUT_OWNER=$owner" "$image" "${stage_command[@]}")
    "$ENGINE" start -a "$CID" 2>&1 | tee "$WORK/$stage.log"
    result=$("$ENGINE" inspect --format '{{.State.ExitCode}}' "$CID")
    "$ENGINE" rm "$CID" >/dev/null; CID=''
    [[ $result == 0 ]] || die "Stage $stage failed; inspect $WORK/$stage.log"
}
