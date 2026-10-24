#!/usr/bin/env bash
# Kernel source selection and cache admission, shared by the host entry, the build stages and their fixtures.
# The caller provides die and say.

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
    printf '%s\n' "$version"
}

# Resolve the source commit once. A local checkout wins; otherwise the remote branch head, or when offline the
# newest source already cached under CACHE.
kernel_commit_resolve() {
    local url=$1 ref=$2 offline=$3 cache=$4 commit='' entry
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

# Ask the kernel source's own entry whether it has a reviewed Uke profile for this exact version; it fails
# rather than substituting a generic or older kernel.
kernel_source_check() {
    local source=$1 version=$2 plan
    [[ -f $source/senemos.sh ]] || die "This kernel source has no senemos.sh to validate Linux $version"
    plan=$(cd -- "$source" && bash ./senemos.sh --build "$version" --distro=fedora --dry-run 2>&1) ||
        die "This kernel source cannot build Linux $version: ${plan##*$'\n'}"
    grep -F "Linux $version;" <<< "$plan" > /dev/null || die "Kernel source resolved a different version than Linux $version"
}

# The producer is what compiles the kernel and links its initramfs: the route, the recipe and the worker images.
kernel_producer_json() {
    local route=$1 recipe=$2
    shift 2
    jq -nSc --arg route "$route" --arg recipe "$recipe" '{route:$route,recipe_sha256:$recipe,worker_images:$ARGS.positional}' --args "$@"
}
kernel_producer_sha() {
    jq -cS . "$1" | sha256sum | cut -d ' ' -f1
}

# Cache key: source commit, exact version and producer. The release is derived from the source and recorded in it.
kernel_cache_dir() {
    printf '%s/cache/kernel-builds/%s-%s-%s\n' "$output" "$KERNEL_COMMIT" "$KERNEL_VERSION" "${KERNEL_PRODUCER_SHA:0:16}"
}
# Succeeds only for an entry that is complete, checksummed and was produced for this source and producer.
kernel_cache_check() {
    local dir=$1 file
    for file in SHA256SUMS kernel/kernel-info.json kernel/producer.json boot-linux.img boot-userdata.img; do
        [[ -f $dir/$file ]] || { KERNEL_CACHE_WHY="missing $file"; return 1; }
    done
    (cd "$dir" && sha256sum -c --quiet SHA256SUMS) > /dev/null 2>&1 || { KERNEL_CACHE_WHY='checksum mismatch'; return 1; }
    jq -e --arg commit "$KERNEL_COMMIT" --arg version "$KERNEL_VERSION" \
        '.kernel_source_commit == $commit and .kernel_version == $version' "$dir/kernel/kernel-info.json" > /dev/null 2>&1 ||
        { KERNEL_CACHE_WHY='metadata names a different source'; return 1; }
    [[ $(kernel_producer_sha "$dir/kernel/producer.json") == "$KERNEL_PRODUCER_SHA" ]] ||
        { KERNEL_CACHE_WHY='built by a different producer'; return 1; }
}
kernel_cache_restore() {
    local dir; dir=$(kernel_cache_dir)
    [[ -d $dir ]] || die "No cached kernel for Linux $KERNEL_VERSION from ${KERNEL_COMMIT:0:12} built by this producer ($dir); build it first with --build kernel"
    kernel_cache_check "$dir" || die "Cached kernel not admitted ($KERNEL_CACHE_WHY): $dir; rebuild it without --reuse-kernel"
    cp -a "$dir/kernel" "$dir"/boot-*.img "$WORK/artifacts/"
    jq --slurpfile info "$dir/kernel/kernel-info.json" '. + $info[0]' "$WORK/request.json" > "$WORK/artifacts/manifest.json"
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
    (cd "$tmp" && find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 -P "$JOBS" -n 4 sha256sum | LC_ALL=C sort -k2 > SHA256SUMS)
    if [[ -e $dir ]]; then mv -- "$dir" "$tmp.old"; fi
    mv -- "$tmp" "$dir"
    rm -rf -- "$tmp.old"
    say "Cached kernel for later image builds: $dir"
}
