#!/usr/bin/env bash
# Kernel source selection and cache admission, shared by the host entry, the build stages and their fixtures.
# The caller provides die, say, output and JOBS.

# Print the top level of an explicit local kernel checkout, or stop. Git decides what a checkout is, so a
# linked worktree (whose .git is a file) is accepted and a plain or bare directory is not.
kernel_repo_validate() {
    local path=$1 top actual
    command -v git >/dev/null 2>&1 || die 'UKE_KERNEL_REPO needs git on the host'
    [[ -d $path ]] || die "UKE_KERNEL_REPO is not a directory: $path"
    top=$(git -C "$path" rev-parse --show-toplevel 2>&1) || die "UKE_KERNEL_REPO is not a Git work tree: $path ($top)"
    actual=$(cd -- "$path" && pwd -P)
    [[ $actual == "$(cd -- "$top" && pwd -P)" ]] || die "UKE_KERNEL_REPO must be the top of a checkout; use $top"
    git -C "$top" rev-parse --verify --quiet 'HEAD^{commit}' >/dev/null || die "UKE_KERNEL_REPO has no commit checked out: $top"
    [[ -z $(git -C "$top" status --porcelain --untracked-files=no) ]] || die "Commit or discard changes in $top first"
    printf '%s\n' "$top"
}

# Snapshot the checked-out commit so the workers never read the live checkout, which may be a worktree whose
# object store lies outside it and may change during a long build.
kernel_repo_bundle() {
    git -C "$1" bundle create "$2" HEAD >/dev/null 2>&1 || die "Cannot snapshot the kernel checkout $1"
}

# Print the exact stable version for an explicit version, latest or the existing alias lastest. Latest is
# kernel.org's newest stable release, fetched once into SNAPSHOT; offline builds read the cached copy.
kernel_version_resolve() {
    local request=$1 snapshot=$2 cached=$3 offline=$4 version=$1
    [[ $version != lastest ]] || version=latest
    if [[ $version == latest ]]; then
        if ((offline)); then
            [[ -s $cached ]] || die 'Offline latest needs the cached kernel.org release metadata'
            cp -- "$cached" "$snapshot"
        else
            curl -fsSL --retry 3 --connect-timeout 20 https://www.kernel.org/releases.json > "$snapshot.part" ||
                die 'Cannot fetch the kernel.org release list'
            mv -- "$snapshot.part" "$snapshot"
        fi
        version=$(jq -er '.latest_stable.version' "$snapshot" 2>/dev/null) || die 'kernel.org release list has no latest stable version'
    fi
    [[ $version =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die "Invalid stable kernel version: $request"
    [[ ! $version =~ ^[0-9]+\.[0-9]+$ ]] || version+=.0
    printf '%s\n' "$version"
}

# Resolve the source commit once. A local checkout wins; otherwise the remote branch head, or when offline the
# newest source already cached under CACHE.
kernel_commit_resolve() {
    local url=$1 ref=$2 offline=$3 cache=$4 commit='' entry
    if [[ $ref =~ ^[0-9a-f]{40}$ ]]; then
        [[ $offline == 0 || -d $cache/kernel-$ref/.git ]] || die 'Offline builds need the exact pinned kernel source'
        printf '%s\n' "$ref"
        return
    fi
    if ((offline)); then
        entry=$(find "$cache" -maxdepth 1 -type d -regextype posix-extended -regex '.*/kernel-[0-9a-f]{40}' -printf '%T@ %f\n' 2>/dev/null | sort -rn | head -n 1)
        [[ -n $entry ]] || die 'Offline builds need a cached kernel source or UKE_KERNEL_REPO'
        commit=${entry##*kernel-}
    else
        commit=$(git ls-remote "$url" "refs/heads/$ref" | cut -f1)
        [[ $commit =~ ^[0-9a-f]{40}$ ]] || die "Cannot resolve $ref in $url"
    fi
    printf '%s\n' "$commit"
}

# Use the same source checks as the SRPM producer; host-entry profiles can admit other build routes.
kernel_source_check() {
    local source=$1 version=$2 plan
    [[ -f $source/Makefile ]] || die "This kernel source has no SRPM Makefile to validate Linux $version"
    if [[ -f $source/src/boot/admit-el2-profile.sh ]]; then
        bash "$source/src/boot/admit-el2-profile.sh" "${KERNEL_PROFILE:-normal}" || die 'Kernel source refuses this profile'
    else
        [[ ${KERNEL_PROFILE:-normal} == normal ]] || die 'This source has no explicit EL2 profile producer'
    fi
    if [[ -n ${KERNEL_CONFIG_SHA:-} ]]; then
        [[ $(sha256sum "$source/packaging/native/native.config" | cut -d ' ' -f1) == "$KERNEL_CONFIG_SHA" ]] || die 'Native config differs from the requested source profile'
    fi
    if [[ ${RUN_TESTS:-1} == 0 ]]; then
        grep -Eq '^run_tests [?:]?=' "$source/Makefile" || die 'Selected source has no explicit test-deferral producer'
        jq -e --arg version "$version" '.version == $version and .hardware_tested == false' "$source/manifests/linux-$version.json" >/dev/null || die 'Source manifest does not admit the requested Linux version'
        return
    fi
    if ! plan=$(make -s -C "$source" validate version="$version" el2_profile="${KERNEL_PROFILE:-normal}" 2>&1); then
        printf '%s\n' "$plan" >&2
        die "The kernel SRPM producer does not admit Linux $version; select a version supported by this source"
    fi
}

# Record executable producer inputs separately so script edits do not rebuild unchanged worker images.
kernel_recipe_hash() {
    (cd -- "$1" && sha256sum configs/Containerfile.public configs/Containerfile.public-native \
        configs/public-build.json configs/build-rules.json \
        src/public/entry.sh src/public/stage.sh src/public/kernel-source.sh) | sha256sum | cut -d ' ' -f1
}

# The producer is what compiles the kernel and links its initramfs: the route, the recipe and the worker images.
kernel_producer_json() {
    local route=$1 recipe=$2
    shift 2
    jq -nSc --arg route "$route" --arg recipe "$recipe" --arg profile "${KERNEL_PROFILE:-normal}" \
        --arg config "${KERNEL_CONFIG_SHA:-}" --argjson tests "${RUN_TESTS:-1}" \
        '{route:$route,recipe_sha256:$recipe,kernel_profile:$profile,native_config_sha256:$config,run_kernel_tests:($tests==1),worker_images:$ARGS.positional}' --args "$@"
}
kernel_producer_sha() {
    jq -cS . "$1" | sha256sum | cut -d ' ' -f1
}

# Cache key: source commit, exact version and producer. The release is derived from the source and recorded in it.
kernel_cache_dir() {
    # shellcheck disable=SC2154
    printf '%s/cache/kernel-builds/fedora-%s-%s-aarch64/%s-%s-%s\n' "$output" "${FEDORA_TARGET:-rawhide}" "${UKE_CACHE_CHANNEL:-testing}" "$KERNEL_COMMIT" "$KERNEL_VERSION" "${KERNEL_PRODUCER_SHA:0:16}"
}
# Succeeds only for an entry that is complete, checksummed and was produced for this source and producer.
kernel_cache_check() {
    local dir=$1 file
    for file in SHA256SUMS kernel/kernel-info.json kernel/producer.json boot-linux.img boot-userdata.img; do
        [[ -f $dir/$file ]] || { KERNEL_CACHE_WHY="missing $file"; return 1; }
    done
    (cd "$dir" && sha256sum -c --quiet SHA256SUMS) > /dev/null 2>&1 || { KERNEL_CACHE_WHY='checksum mismatch'; return 1; }
    jq -e --arg commit "$KERNEL_COMMIT" --arg version "$KERNEL_VERSION" --arg profile "${KERNEL_PROFILE:-normal}" \
        '.kernel_source_commit == $commit and .kernel_version == $version and (.kernel_profile // "normal") == $profile' "$dir/kernel/kernel-info.json" > /dev/null 2>&1 ||
        { KERNEL_CACHE_WHY='metadata names a different source'; return 1; }
    [[ $(kernel_producer_sha "$dir/kernel/producer.json") == "$KERNEL_PRODUCER_SHA" ]] ||
        { KERNEL_CACHE_WHY='built by a different producer'; return 1; }
}
kernel_cache_restore() {
    local dir; dir=$(kernel_cache_dir)
    [[ -d $dir ]] || die "No cached kernel for Linux $KERNEL_VERSION from ${KERNEL_COMMIT:0:12} built by this producer ($dir); build it first with --build kernel"
    kernel_cache_check "$dir" || die "Cached kernel not admitted ($KERNEL_CACHE_WHY): $dir; rebuild it without --reuse-kernel"
    cp -a "$dir/kernel" "$dir"/boot-*.img "$WORK/artifacts/"
    jq --slurpfile info "$dir/kernel/kernel-info.json" '. + ($info[0] | del(.kernel_requested))' "$WORK/request.json" > "$WORK/artifacts/manifest.json"
    say "Reused cached kernel: $dir"
}
kernel_cache_save() {
    local dir tmp; dir=$(kernel_cache_dir)
    if [[ -e $dir ]]; then
        if kernel_cache_check "$dir"; then return 0; fi
        say "Replacing the damaged kernel cache entry ($KERNEL_CACHE_WHY): $dir"
    fi
    mkdir -p "${dir%/*}"
    tmp=$(mktemp -d "${dir%/*}/.tmp-XXXXXXXX")
    cp -a "$WORK/artifacts/kernel" "$WORK"/artifacts/boot-*.img "$tmp/"
    (cd "$tmp" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -P "$JOBS" -n 4 sha256sum | LC_ALL=C sort -k2) > "$tmp.sha256"
    mv -- "$tmp.sha256" "$tmp/SHA256SUMS"
    if [[ -e $dir ]]; then mv -- "$dir" "$tmp.old"; fi
    mv -- "$tmp" "$dir"
    rm -rf -- "$tmp.old"
    say "Cached kernel for later image builds: $dir"
}
