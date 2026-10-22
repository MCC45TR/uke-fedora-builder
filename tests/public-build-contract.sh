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
for mode in multiboot singleboot; do
    for filesystem in ext4 f2fs btrfs xfs; do
        for desktop in kde gnome; do
            for channel in stable testing unstable; do
                (cd "$fixture"; public_main --build image --mode "$mode" --filesystem "$filesystem" --desktop "$desktop" --channel "$channel" --offline --dry-run) > "$fixture/plan"
                grep -F "$mode; $filesystem; $desktop; $channel" "$fixture/plan" >/dev/null
                grep -F "$fixture/out" "$fixture/plan" >/dev/null
                ((count+=1))
            done
        done
    done
done
[[ $count == 48 && ! -e $fixture/out ]]
for channel in stable testing unstable; do
    public_main --build kernel --channel "$channel" --dry-run > "$fixture/plan"
    grep -F 'kernel: Fedora Rawhide AArch64' "$fixture/plan" >/dev/null
done
for pair in '--mode bad' '--filesystem zfs' '--desktop xfce' '--channel latest' '--build plasma' '--jobs 0' '--jobs 9' '--linux-size 65537'; do
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
jq -e '.kernel.commit|test("^[a-f0-9]{40}$")' "$root/configs/public-build.json" >/dev/null
bash -n "$root"/src/public/*.sh
printf '%s\n' '48 image selections, three kernel channels, minimal-PATH planning, invalid inputs, local-data refusal and five host-manager mappings passed; no builds ran.'
