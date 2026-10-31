#!/usr/bin/env bash
# shellcheck disable=SC2034
# Shell fixtures only: never install packages, run a container or compile a kernel.
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../src/image/core.sh
# shellcheck disable=SC1091
source "$root/src/image/core.sh"
# shellcheck source=../src/public/entry.sh
# shellcheck disable=SC1091
source "$root/src/public/entry.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
bootstrap() { echo 'Bootstrap must not run for a plan' >&2; exit 90; }
public_worker() { exit 91; }
public_stage() { exit 92; }
reject() {
    local status=0
    (public_main "$@") > /dev/null 2>&1 || status=$?
    ((status > 0 && status < 90)) || { echo 'Invalid request accepted or reached host preparation' >&2; exit 1; }
}
count=0
for fedora_release in 44 45 rawhide; do
for login_shell in bash fish zsh; do
for mode in multiboot singleboot; do
    for filesystem in ext4 f2fs btrfs xfs; do
        for desktop in kde gnome cutefish; do
            for channel in stable testing unstable; do
                (cd "$fixture"; public_main --build image --release "$fedora_release" --shell "$login_shell" --mode "$mode" --filesystem "$filesystem" --desktop "$desktop" --channel "$channel" --offline --dry-run) > "$fixture/plan"
                grep -F "$mode; $filesystem; $desktop; $channel" "$fixture/plan" >/dev/null
                grep -F "$fixture/out" "$fixture/plan" >/dev/null
                ((count+=1))
            done
        done
    done
done
done
done
[[ $count == 648 && ! -e $fixture/out ]]
for channel in stable testing unstable; do
    public_main --build kernel --channel "$channel" --dry-run > "$fixture/plan"
    grep -F 'kernel: Fedora Rawhide AArch64' "$fixture/plan" >/dev/null
done
reject --release
reject --shell
reject --build kernel --shell bash --dry-run
reject --build kernel --desktop kde --dry-run
reject --desktop cutefish --yes
reject --release 44 --yes
reject --release 45 --yes
for pair in '--release 46' '--release ../45' '--shell sh' '--mode bad' '--filesystem zfs' '--desktop xfce' '--channel latest' '--build plasma' '--jobs 0' '--jobs 99999' '--linux-size 65537'; do
    # Intentional fixture word splitting of fixed literal option/value pairs.
    # shellcheck disable=SC2086
    reject $pair --dry-run
done
reject --out '' --dry-run
reject --out '/tmp/unsafe:volume' --dry-run
reject --out '/tmp/unsafe,volume' --dry-run
reject --out --dry-run
reject --jobs
reject --unknown --dry-run
truncate -s 5432 "$fixture/reference.bin"
chmod 644 "$fixture/reference.bin"
reject --touch-reference "$fixture/reference.bin" --dry-run
chmod 600 "$fixture/reference.bin"
public_main --touch-reference "$fixture/reference.bin" --dry-run >/dev/null
ln -s reference.bin "$fixture/link.bin"
reject --touch-reference "$fixture/link.bin" --dry-run
truncate -s 5431 "$fixture/reference.bin"
reject --touch-reference "$fixture/reference.bin" --dry-run
# Refuse a filesystem that cannot protect private image inputs before copying them.
truncate -s 5432 "$fixture/reference.bin"
# shellcheck disable=SC2317,SC2329
(
    bootstrap() { :; }
    df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfixture 999999999 0 999999999 0%% /\n'; }
    stat() {
        if [[ $1 == -c && $2 == %a && $3 == "$fixture/refused-output/"* ]]; then printf '775\n'
        else command stat "$@"; fi
    }
    install() { echo 'Private input copy reached an inadmissible filesystem' >&2; exit 94; }
    reject --build image --yes --out "$fixture/refused-output" --touch-reference "$fixture/reference.bin"
)
for partition in linux userdata; do
    public_flash_help "$partition" > "$fixture/flash"
    grep -Fx "       fastboot flash $partition $partition.img" "$fixture/flash" >/dev/null
    grep -F 'sudo dnf update --refresh' "$fixture/flash" >/dev/null
    if grep -E 'fastboot (erase|format)|fastboot flash (boot_a|persist|xbl|abl)' "$fixture/flash"; then exit 1; fi
done
# Host package consent must precede the package manager, including without a TTY.
if (UKE_ASSUME_YES=0; confirm_host_change test < /dev/null) >/dev/null 2>&1; then exit 1; fi
(UKE_ASSUME_YES=1; confirm_host_change test < /dev/null)
privileged() { printf '%s\n' "$*" >> "$fixture/install-commands"; }
for manager in apt dnf zypper pacman apk; do
    (UKE_ASSUME_YES=1; install_packages "$manager" fixture-package) >/dev/null
done
grep -F 'apt-get -y install --no-install-recommends fixture-package' "$fixture/install-commands" >/dev/null
grep -F 'dnf -y --setopt=install_weak_deps=False install fixture-package' "$fixture/install-commands" >/dev/null
grep -F 'zypper --non-interactive install --no-recommends fixture-package' "$fixture/install-commands" >/dev/null
grep -F 'pacman -Syu --needed --noconfirm fixture-package' "$fixture/install-commands" >/dev/null
grep -F 'apk add --no-cache fixture-package' "$fixture/install-commands" >/dev/null
[[ $(package_manager ubuntu debian) == apt && $(package_manager fedora '') == dnf ]]
[[ $(package_manager opensuse-tumbleweed suse) == zypper && $(package_manager arch '') == pacman && $(package_manager alpine '') == apk ]]
# A minimal PATH without jq must still print the new plan without bootstrapping.
mkdir "$fixture/bin"
ln -s "$(command -v dirname)" "$fixture/bin/dirname"
PATH=$fixture/bin public_main --build image --dry-run > "$fixture/minimal-plan"
[[ ! -e $fixture/out ]]
jq -e '.kernel | (.ref|type=="string") and (.default_version|test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$")) and (has("commit")|not) and (has("release")|not)' \
    "$root/configs/public-build.json" >/dev/null
bash -n "$root"/src/public/*.sh
bash "$root/tests/public-source-inputs.sh"
bash "$root/tests/public-root-transaction.sh"
printf '%s\n' '648 image selections, three kernel channels, minimal-PATH planning, invalid inputs, local-data refusal and five host-manager mappings passed; no builds ran.'
quiet_fail() { if ("$@") > /dev/null 2>&1; then echo "Accepted: $*" >&2; exit 1; fi; }
# Kernel selection: explicit versions, latest and its alias are accepted; anything else is refused before a build starts.
for choice in 7.2.12 7.3 latest lastest; do public_main --kernel "$choice" --dry-run > /dev/null; done
for choice in 7.x latest\;rm v7.2.12 7.2.12.1 newest; do reject --kernel "$choice" --dry-run; done
reject --kernel
# Version resolution fetches kernel.org's list once for latest, never for an explicit version, and rejects bad lists.
# shellcheck disable=SC2317,SC2329
(
    snapshot=$fixture/releases.json cached=$fixture/cached-releases.json
    curl() { printf '{"latest_stable":{"version":"7.9.1"}}\n'; }
    [[ $(kernel_version_resolve 7.2.12 "$snapshot" "$cached" 0) == 7.2.12 && ! -e $snapshot ]]
    [[ $(kernel_version_resolve latest "$snapshot" "$cached" 0) == 7.9.1 && $(jq -r .latest_stable.version "$snapshot") == 7.9.1 ]]
    [[ $(kernel_version_resolve lastest "$snapshot" "$cached" 0) == 7.9.1 ]]
    quiet_fail kernel_version_resolve latest "$snapshot" "$cached" 1
    printf '{"latest_stable":{"version":"7.8.2"}}\n' > "$cached"
    [[ $(kernel_version_resolve latest "$snapshot" "$cached" 1) == 7.8.2 ]]
    quiet_fail kernel_version_resolve 7.x "$snapshot" "$cached" 0
    curl() { printf '{"latest_stable":{"version":"next"}}\n'; }
    quiet_fail kernel_version_resolve latest "$snapshot" "$cached" 0
    curl() { printf 'not json\n'; }
    quiet_fail kernel_version_resolve latest "$snapshot" "$cached" 0
    curl() { return 22; }
    quiet_fail kernel_version_resolve latest "$snapshot" "$cached" 0
)
# Admission uses the actual SRPM Makefile, including when the standalone host entry accepts another version.
(
    source=$fixture/kernel-source; mkdir -p "$source"
    quiet_fail kernel_source_check "$source" 7.2.12
    printf '%s\n' 'exit 0' > "$source/senemos.sh"
    quiet_fail kernel_source_check "$source" 7.2.9
    cat > "$source/Makefile" <<'MAKE'
validate:
	@test "$(version)" = 7.2.12
MAKE
    kernel_source_check "$source" 7.2.12
    quiet_fail kernel_source_check "$source" 7.2.9
    quiet_fail kernel_source_check "$source" 7.3
    sed -i 's/7.2.12/7.2.10/' "$source/Makefile"
    kernel_source_check "$source" 7.2.10
    quiet_fail kernel_source_check "$source" 7.2.12
)
# Local checkout: Git decides. Worktrees pass; plain, bare, nested, empty and dirty paths stop; the worker gets a snapshot.
(
    git() { command git -c user.name=fixture -c user.email=fixture@example.invalid -c init.defaultBranch=main "$@"; }
    repo=$fixture/kernel-repo; git init -q "$repo"; printf one > "$repo/file"
    git -C "$repo" add file; git -C "$repo" commit -q -m one
    git -C "$repo" worktree add -q --detach "$fixture/kernel-worktree"
    [[ $(kernel_repo_validate "$repo") == "$(cd "$repo" && pwd -P)" && $(kernel_repo_validate "$fixture/kernel-worktree") == "$(cd "$fixture/kernel-worktree" && pwd -P)" ]]
    [[ -f $fixture/kernel-worktree/.git ]]
    mkdir "$fixture/plain" "$repo/nested"; git init -q --bare "$fixture/bare.git"; git init -q "$fixture/empty"
    for bad in "$fixture/plain" "$fixture/missing" "$fixture/bare.git" "$repo/nested" "$fixture/empty" "$repo/file"; do quiet_fail kernel_repo_validate "$bad"; done
    printf two > "$repo/file"; quiet_fail kernel_repo_validate "$repo"; git -C "$repo" checkout -q -- file
    kernel_repo_bundle "$fixture/kernel-worktree" "$fixture/kernel.bundle"
    git clone -q --no-checkout "$fixture/kernel.bundle" "$fixture/from-bundle"
    [[ $(git -C "$fixture/from-bundle" rev-parse HEAD) == "$(git -C "$fixture/kernel-worktree" rev-parse HEAD)" ]]
    # The entry honors a valid override, refuses an invalid one even for a plan, and keeps none as the policy source.
    UKE_KERNEL_REPO=$fixture/kernel-worktree public_main --dry-run > /dev/null
    UKE_KERNEL_REPO=none public_main --dry-run > /dev/null
    status=0; (UKE_KERNEL_REPO=$fixture/plain public_main --dry-run) > /dev/null 2>&1 || status=$?
    ((status > 0 && status < 90)) || { echo 'Invalid UKE_KERNEL_REPO was ignored' >&2; exit 1; }
    # A reviewed commit is immutable; offline use requires that exact source.
    pin=$(printf 'd%.0s' {1..40})
    [[ $(kernel_commit_resolve "$repo" "$pin" 0 "$fixture/srcs") == "$pin" ]]
    quiet_fail kernel_commit_resolve "$repo" "$pin" 1 "$fixture/srcs"
    mkdir -p "$fixture/srcs/kernel-$pin/.git"
    [[ $(kernel_commit_resolve "$repo" "$pin" 1 "$fixture/srcs") == "$pin" ]]
    # Source commit: the remote branch head online, the newest cached source offline.
    [[ $(kernel_commit_resolve "$repo" main 0 "$fixture/none") == "$(git -C "$repo" rev-parse main)" ]]
    quiet_fail kernel_commit_resolve "$repo" absent 0 "$fixture/none"
    quiet_fail kernel_commit_resolve "$repo" main 1 "$fixture/none"
    mkdir -p "$fixture/srcs/kernel-$(printf 'b%.0s' {1..40})" "$fixture/srcs/kernel-$(printf 'c%.0s' {1..40})"
    touch -d '2 days ago' "$fixture/srcs/kernel-$(printf 'b%.0s' {1..40})"
    touch -d '3 days ago' "$fixture/srcs/kernel-$pin"
    [[ $(kernel_commit_resolve "$repo" main 1 "$fixture/srcs") == "$(printf 'c%.0s' {1..40})" ]]
)
# Kernel cache: restores byte-for-byte with its producer, is keyed by source, version and producer, and repairs damage.
cache_fixture=$(mktemp -d)
# shellcheck disable=SC2317,SC2329
(
    WORK=$cache_fixture/work output=$cache_fixture/out JOBS=2
    KERNEL_COMMIT=$(printf 'a%.0s' {1..40}) KERNEL_VERSION=7.2.12
    mkdir -p "$WORK/recipe/configs" "$WORK/artifacts/kernel"
    printf '{"channel":"testing","kernel_requested":"latest"}\n' > "$WORK/request.json"
    say() { :; }
    mkdir "$cache_fixture/recipe"
    cp -a "$root/src" "$root/configs" "$cache_fixture/recipe/"
    recipe_a=$(kernel_recipe_hash "$cache_fixture/recipe")
    [[ $recipe_a == "$(kernel_recipe_hash "$root")" ]]
    sed -i 's/clang++ -std=c++17 -O2/clang++ -std=c++17 -O0/' "$cache_fixture/recipe/src/public/stage.sh"
    recipe_b=$(kernel_recipe_hash "$cache_fixture/recipe")
    [[ $recipe_a != "$recipe_b" ]]
    producer_a=$(kernel_producer_json cross "$recipe_a" worker-1 worker-2) producer_b=$(kernel_producer_json cross "$recipe_a" worker-1 worker-3)
    producer_c=$(kernel_producer_json cross "$recipe_b" worker-1 worker-2)
    use_producer() { printf '%s\n' "$1" > "$cache_fixture/producer.json"; KERNEL_PRODUCER_SHA=$(kernel_producer_sha "$cache_fixture/producer.json"); }
    stage_artifacts() {
        rm -rf "$WORK/artifacts"; mkdir -p "$WORK/artifacts/kernel"
        printf '{"kernel_source_commit":"%s","kernel_version":"%s","kernel_release":"7.2.12-20","kernel_requested":"7.2.12"}\n' "$KERNEL_COMMIT" "$KERNEL_VERSION" > "$WORK/artifacts/kernel/kernel-info.json"
        cp "$cache_fixture/producer.json" "$WORK/artifacts/kernel/producer.json"
        : > "$WORK/artifacts/kernel/packages.tsv"; printf img > "$WORK/artifacts/boot-linux.img"; printf img > "$WORK/artifacts/boot-userdata.img"
    }
    use_producer "$producer_a"; stage_artifacts
    quiet_fail kernel_cache_restore
    kernel_cache_save
    entry=$(kernel_cache_dir); [[ -d $entry && $entry == *"-7.2.12-${KERNEL_PRODUCER_SHA:0:16}" ]]
    rm -rf "$WORK/artifacts"; mkdir "$WORK/artifacts"
    kernel_cache_restore
    [[ -f $WORK/artifacts/boot-linux.img && $(jq -r '.kernel_release + .channel' "$WORK/artifacts/manifest.json") == 7.2.12-20testing ]]
    [[ $(jq -r .kernel_requested "$WORK/artifacts/manifest.json") == latest ]]
    [[ $(kernel_producer_sha "$WORK/artifacts/kernel/producer.json") == "$KERNEL_PRODUCER_SHA" ]]
    # Another producer or version never sees this entry.
    use_producer "$producer_b"; quiet_fail kernel_cache_restore
    use_producer "$producer_c"; quiet_fail kernel_cache_restore
    use_producer "$producer_a"; (KERNEL_VERSION=7.2.11; quiet_fail kernel_cache_restore)
    # Metadata that names another producer or version is not admitted even when its checksums are valid.
    sealed() {
        (cd "$entry" && find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | LC_ALL=C sort -k2) > "$cache_fixture/SHA256SUMS"
        mv "$cache_fixture/SHA256SUMS" "$entry/SHA256SUMS"
    }
    printf '%s\n' "$producer_b" > "$entry/kernel/producer.json"; sealed; quiet_fail kernel_cache_restore
    stage_artifacts; kernel_cache_save; kernel_cache_restore
    jq '.kernel_version = "7.2.11"' "$entry/kernel/kernel-info.json" > "$cache_fixture/info" && cp "$cache_fixture/info" "$entry/kernel/kernel-info.json"; sealed
    quiet_fail kernel_cache_restore
    stage_artifacts; kernel_cache_save; kernel_cache_restore
    # A corrupt entry is not restored, and the next build replaces it instead of skipping the save.
    printf bad > "$entry/boot-linux.img"; quiet_fail kernel_cache_restore
    stage_artifacts; kernel_cache_save
    kernel_cache_restore
    [[ $(< "$WORK/artifacts/boot-linux.img") == img && -z $(compgen -G "$output/cache/kernel-builds/.tmp-*" || :) && -z $(compgen -G "$output/cache/kernel-builds/*.old" || :) ]]
    # An incomplete entry is replaced too, and an intact one is left alone.
    rm "$entry/kernel/producer.json"; quiet_fail kernel_cache_restore
    stage_artifacts; kernel_cache_save; kernel_cache_restore
    touch "$entry/kept"; stage_artifacts; kernel_cache_save; [[ -e $entry/kept ]]
)
rm -rf -- "$cache_fixture"
reject --build kernel --reuse-kernel --dry-run

# Run orchestration up to the first worker without installing or starting a container.
# shellcheck disable=SC2317,SC2329
(
    bootstrap() { :; }
    df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfixture 999999999 0 999999999 0%% /\n'; }
    public_worker() { printf '%s %s\n' "$1" "$3" >> "$fixture/worker-targets"; exit 91; }
    for release in 44 45; do
        status=0
        (public_main --build kernel --release "$release" --yes --out "$fixture/worker-$release") > /dev/null 2>&1 || status=$?
        [[ $status == 91 ]]
    done
    [[ $(awk '{print $1}' "$fixture/worker-targets" | sort -u | wc -l) == 2 ]]
    [[ $(awk '{print $2}' "$fixture/worker-targets" | sort -u | wc -l) == 2 ]]
)
