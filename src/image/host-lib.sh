#!/usr/bin/env bash
# Sourced host preparation; the entry assigns architecture and job state.
# shellcheck disable=SC2034,SC2154
package_manager() {
    case " $1 $2 " in
        *' fedora '*|*' rhel '*|*' centos '*|*' rocky '*|*' almalinux '*) echo dnf;;
        *' debian '*|*' ubuntu '*|*' linuxmint '*) echo apt;;
        *' opensuse '*|*' opensuse-tumbleweed '*|*' opensuse-leap '*|*' suse '*) echo zypper;;
        *' arch '*|*' manjaro '*) echo pacman;;
        *' alpine '*|*' postmarketos '*) echo apk;;
        *) return 1;;
    esac
}
privileged() {
    if ((EUID == 0)); then "$@";
    elif command -v sudo >/dev/null 2>&1; then sudo -- "$@";
    elif command -v doas >/dev/null 2>&1; then doas -- "$@";
    else die "Missing installation privilege (root, sudo or doas): $*"; fi
}
install_packages() {
    local manager=$1; shift
    say "Installing missing host prerequisites with $manager"
    case $manager in
        dnf) privileged dnf -y --setopt=install_weak_deps=False install "$@";;
        apt) privileged apt-get update; privileged env DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends "$@";;
        zypper) privileged zypper --non-interactive install --no-recommends "$@";;
        pacman) privileged pacman -Syu --needed --noconfirm "$@";;
        apk) privileged apk add --no-cache "$@";;
    esac
}
bootstrap() {
    local ID='' ID_LIKE='' VERSION='' manager missing=0 cmd require_engine=${1:-1}
    # /etc/os-release is the host's trusted distribution identity.
    # shellcheck disable=SC1091
    source /etc/os-release
    manager=$(package_manager "$ID" "${ID_LIKE:-}") || die "Unsupported build host: $ID"
    for cmd in curl jq git tar xz gpg flock sha256sum realpath find; do
        command -v "$cmd" >/dev/null 2>&1 || missing=1
    done
    if ((missing)); then
        ((OFFLINE == 0)) || die 'Offline mode cannot install missing prerequisites'
        # jq may be missing, so bootstrap names deliberately do not depend on it.
        case $manager in
            dnf) install_packages dnf bash curl jq git tar xz gnupg2 util-linux coreutils findutils;;
            apt) install_packages apt bash curl jq git tar xz-utils gnupg util-linux coreutils findutils uidmap;;
            zypper) install_packages zypper bash curl jq git tar xz gpg2 util-linux coreutils findutils;;
            pacman) install_packages pacman bash curl jq git tar xz gnupg util-linux coreutils findutils;;
            apk) install_packages apk bash curl jq git tar xz gnupg util-linux coreutils findutils shadow-subids;;
        esac
    fi
    for cmd in curl jq git tar xz gpg flock sha256sum realpath find; do
        command -v "$cmd" >/dev/null 2>&1 || die "Host prerequisite still missing after installation: $cmd"
    done
    ((require_engine)) || return 0
    if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then ENGINE=podman;
    elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then ENGINE=docker;
    else
        ((OFFLINE == 0)) || die 'Offline mode needs an operational Podman or Docker'
        install_packages "$manager" podman
        if [[ $manager == apt ]]; then install_packages apt uidmap; fi
        if ((EUID != 0)) && ! podman info >/dev/null 2>&1; then
            local account range_start range_end
            account=$(id -un)
            if ! grep -Eq "^($account|$EUID):" /etc/subuid 2>/dev/null || \
               ! grep -Eq "^($account|$EUID):" /etc/subgid 2>/dev/null; then
                range_start=$(awk -F: 'BEGIN {limit=100000} {end=$2+$3; if(end>limit) limit=end} END {print limit}' /etc/subuid /etc/subgid 2>/dev/null) || range_start=100000
                range_end=$((range_start + 65535))
                ((range_end < 4294967295)) || die 'No available rootless UID/GID mapping range'
                say 'Preparing missing rootless UID/GID allocations'
                privileged usermod --add-subuids "$range_start-$range_end" --add-subgids "$range_start-$range_end" "$account"
            fi
        fi
        podman info >/dev/null 2>&1 || die 'Podman is installed but unusable; check user namespaces and subuid/subgid allocation'
        ENGINE=podman
    fi
}
prepare_aarch64() {
    [[ $architecture == x86_64 ]] || return 0
    if "$ENGINE" run --rm --platform linux/arm64 --network=none "$TEST_IMAGE" /bin/true \
        > "$WORK/emulation-preflight.log" 2>&1; then return 0; fi
    ((OFFLINE == 0)) || die 'Offline target tests require operational AArch64 binfmt emulation'
    local ID='' ID_LIKE='' VERSION='' manager binary registration
    # shellcheck disable=SC1091
    source /etc/os-release
    manager=$(package_manager "$ID" "${ID_LIKE:-}")
    case $manager in
        dnf) install_packages dnf qemu-user-static-aarch64;;
        apt) install_packages apt qemu-user-static binfmt-support;;
        pacman) install_packages pacman qemu-user-static qemu-user-static-binfmt;;
        zypper) install_packages zypper qemu-linux-user;;
        apk) install_packages apk qemu-aarch64;;
    esac
    binary=$(command -v qemu-aarch64-static || command -v qemu-aarch64) || die 'Official AArch64 emulator binary is unavailable'
    [[ -e /proc/sys/fs/binfmt_misc/register ]] || privileged mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
    # Register only our handler; existing host handlers are preserved. F keeps
    # the official static interpreter open across a container's mount namespace.
    registration=':senemos-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:'"$binary"':F'
    [[ -e /proc/sys/fs/binfmt_misc/senemos-aarch64 ]] || \
        printf '%s\n' "$registration" | privileged tee /proc/sys/fs/binfmt_misc/register >/dev/null
    "$ENGINE" run --rm --platform linux/arm64 --network=none "$TEST_IMAGE" /bin/true \
        > "$WORK/emulation-preflight.log" 2>&1 || die 'AArch64 emulation is installed but unusable; inspect emulation-preflight.log'
}
heavy_busy() {
    local process comm group state_record
    for process in /proc/[0-9]*; do
        [[ -r $process/comm ]] || continue
        IFS= read -r comm < "$process/comm" || continue
        case $comm in make|gmake|ninja|ninja-build|soong_ui|ckati|clang|clang++|clang-[0-9]*|clang++-[0-9]*|cc1|cc1plus|ld.lld|ld.lld-[0-9]*|rustc) ;; *) continue;; esac
        IFS= read -r state_record < "$process/stat" 2>/dev/null || continue
        state_record=${state_record##*) }
        case ${state_record%% *} in Z|X) continue;; esac
        group=$(cat "$process/cgroup" 2>/dev/null) || continue
        [[ -n $group ]] || continue
        [[ -n ${CID:-} && $group == *"$CID"* ]] && continue
        return 0
    done
    return 1
}
wait_idle() {
    local announced=0
    while heavy_busy; do
        if ((announced == 0)); then say 'Queued behind another active build; existing work is preserved'; announced=1; fi
        sleep 10
    done
}
