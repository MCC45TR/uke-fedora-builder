#!/usr/bin/env bash
# Host-only RAM trials and private, bounded observations. Never flashes storage.
set -Eeuo pipefail
umask 077
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$root/src/device/preflight.sh"
die() { echo "$*" >&2; exit 1; }
usage() {
    cat <<'EOF'
Usage: bash tests/tablet-lab.sh verify BUNDLE
       bash tests/tablet-lab.sh boot BUNDLE rollback|core|gpu
       bash tests/tablet-lab.sh boot BUNDLE timeout --expect-timeout
       UKE_SSH_CONFIG=PRIVATE_CONFIG bash tests/tablet-lab.sh collect SSH_ALIAS NEW_DIRECTORY
The bundle is a local laboratory manifest, not a release or an installation image.
Install its signed matching kernel/support tuple before the 7.2.10 RAM trials.
The timeout case requires physical recovery and deliberately blocks root mounting.
Collection requires a pinned SSH host key, exact Uke identity and the physical
PARTLABEL=linux ext4 root. Raw observations stay in a new private directory.
No flashing, slot selection, service starts, module loads or register writes.
EOF
}
verify() {
    local bundle=$1 path hash
    [[ -d $bundle && ! -L $bundle && -f $bundle/manifest.json && ! -L $bundle/manifest.json ]] || die 'Missing regular bundle manifest'
    jq -e '
        .schema_version==1 and .device=="uke" and .soc=="SM7675" and
        .root_selector=="PARTLABEL=linux" and .flash_allowed==false and
        (.cases|length)==4 and ([.cases[].id]|sort)==["core","gpu","rollback","timeout"] and
        all(.cases[]; (.image|test("^images/[A-Za-z0-9_-]+\\.img$")) and
            (.sha256|test("^[a-f0-9]{64}$")) and .physical_tested_this_trial==false and
            .flash_allowed==false and
            (if .id=="rollback" then .kernel_release=="7.2.9-senemos-uke"
             else .kernel_release=="7.2.10-senemos-uke" end))
        ' "$bundle/manifest.json" >/dev/null || die 'Incompatible laboratory manifest'
    [[ -d $bundle/images && ! -L $bundle/images ]] || die 'Missing regular images directory'
    while IFS=$'\t' read -r path hash; do
        [[ -f $bundle/$path && ! -L $bundle/$path && $(stat -c %s "$bundle/$path") == 100663296 ]] || die 'Missing regular 96 MiB boot image'
        [[ $(sha256sum "$bundle/$path" | cut -d ' ' -f1) == "$hash" ]] || die "Checksum failed: $path"
    done < <(jq -r '.cases[]|[.image,.sha256]|@tsv' "$bundle/manifest.json")
    echo 'Local boot-image hashes verified; physical acceptance remains separate.'
}
boot() {
    local bundle=$1 trial=$2 extra=${3:-} listing serial mode product unlocked userspace image
    case $trial in
        rollback|core|gpu) [[ -z $extra ]] || die 'Unexpected boot option';;
        timeout) [[ $extra == --expect-timeout ]] || die 'Timeout fixture requires --expect-timeout and physical recovery';;
        *) die 'Unknown trial';;
    esac
    verify "$bundle"
    listing=$(timeout -k 2 8 fastboot devices)
    [[ $(printf '%s\n' "$listing" | awk 'NF{n++} END{print n+0}') == 1 ]] || die 'Exactly one fastboot device required'
    read -r serial mode <<< "$listing"
    [[ $serial =~ ^[A-Za-z0-9._:-]+$ && $mode == fastboot ]] || die 'Unexpected fastboot listing'
    product=$(device_fastboot_value "$serial" product) || die 'Ambiguous fastboot product'
    unlocked=$(device_fastboot_value "$serial" unlocked) || die 'Ambiguous lock state'
    userspace=$(device_fastboot_value "$serial" is-userspace) || die 'Ambiguous fastboot mode'
    [[ $product == uke ]] || die 'Foreign fastboot product'
    [[ $unlocked == yes ]] || die 'Unlocked bootloader required'
    [[ $userspace == no ]] || die 'Bootloader fastboot required'
    image=$(jq -r --arg trial "$trial" '.cases[]|select(.id==$trial)|.image' "$bundle/manifest.json")
    timeout -k 2 90 fastboot -s "$serial" boot "$bundle/$image"
}
# Variables in the fixed observation commands expand only in the tablet shell.
# shellcheck disable=SC2016
collect() {
    local alias=$1 output=$2 rc failures=0
    [[ $alias =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die 'Use a configured SSH alias'
    [[ -f ${UKE_SSH_CONFIG:-} ]] || die 'Set UKE_SSH_CONFIG to the private pinned-host configuration'
    [[ ! -e $output && ! -L $output ]] || die 'Collection directory must be new'
    mkdir -m 700 -- "$output"
    local -a remote=(ssh -F "$UKE_SSH_CONFIG" -o BatchMode=yes -o StrictHostKeyChecking=yes
        -o ConnectTimeout=4 -o ServerAliveInterval=3 -o ServerAliveCountMax=2 "$alias")
    if ! timeout -k 2 15 "${remote[@]}" sh -s > "$output/identity.log" 2>&1 <<'EOF'
set -eu
test "$(id -u)" = 0
tr '\000' '\n' < /sys/firmware/devicetree/base/compatible | grep -Fx 'xiaomi,uke'
tr '\000' '\n' < /sys/firmware/devicetree/base/compatible | grep -Fx 'qcom,sm7675'
test "$(findmnt -n -o FSTYPE /)" = ext4
test "$(stat -Lc '%d' /)" = "$(stat -Lc '%r' /dev/disk/by-partlabel/linux)"
uname -r
EOF
    then die 'Uke identity/root check failed; see private identity.log'; fi
    capture() {
        local name=$1 command=$2
        rc=0
        timeout -k 2 30 "${remote[@]}" "$command" > "$output/$name.log" 2>&1 || rc=$?
        printf '%s\t%s\n' "$name" "$rc" >> "$output/results.tsv"
        ((rc==0)) || failures=1
    }
    capture startup 'uname -a; cat /proc/cmdline; findmnt /; systemctl --no-pager --failed; systemctl --no-pager status uke-boot-guard.service; systemctl show uke-boot-guard.service -p Result -p ExecMainStatus -p ActiveState'
    capture kernel 'dmesg --color=never'
    capture journal 'journalctl -b --no-pager -n 1800 -o short-monotonic'
    capture previous 'journalctl -b -1 --no-pager -n 500 -o short-monotonic'
    capture pstore 'find /sys/fs/pstore -maxdepth 1 -type f -exec cat {} +'
    capture power 'for p in /sys/class/power_supply/*/uevent /sys/class/thermal/thermal_zone*/type /sys/class/thermal/thermal_zone*/temp /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq /sys/class/devfreq/*/cur_freq; do test ! -f "$p" || { echo "$p"; timeout -k 1 2 cat "$p"; }; done'
    capture display 'for p in /sys/class/drm/card*-*/status /sys/class/drm/card*-*/modes /sys/class/drm/card*-*/enabled /sys/class/backlight/*/brightness /sys/class/backlight/*/actual_brightness /sys/class/backlight/*/max_brightness /sys/class/backlight/*/bl_power; do test ! -f "$p" || { echo "$p"; timeout -k 1 2 cat "$p"; }; done; command -v modetest >/dev/null && timeout -k 2 8 modetest -c -p'
    capture input 'cat /proc/bus/input/devices; command -v libinput >/dev/null && timeout -k 2 8 libinput list-devices'
    capture sensors 'findmnt /mnt/vendor/persist; systemctl --no-pager status uke-ssc-root.service uke-ssc-sensors.service iio-sensor-proxy.service; busctl --auto-start=no --timeout=3 --system introspect net.hadess.SensorProxy /net/hadess/SensorProxy'
    capture usb 'for p in /sys/class/typec/*/data_role /sys/class/typec/*/power_role /sys/class/usb_role/*/role /sys/class/udc/*/state; do test ! -f "$p" || { echo "$p"; timeout -k 1 2 cat "$p"; }; done; command -v lsusb >/dev/null && lsusb -t'
    capture sessions 'loginctl list-sessions --no-pager; for p in /sys/bus/platform/drivers/nvmem-reboot-mode/*/of_node; do test ! -e "$p" || readlink -f "$p"; done'
    (cd "$output" && sha256sum ./*.log results.tsv > SHA256SUMS)
    echo "Private collection completed; each command exit status is in results.tsv (nonzero is not hardware acceptance)."
    ((failures==0)) || return 2
}
case ${1:---help} in
    --help|-h) usage;;
    verify) [[ $# == 2 ]] || die 'verify requires BUNDLE'; verify "$2";;
    boot) [[ $# == 3 || $# == 4 ]] || die 'boot requires BUNDLE CASE'; boot "$2" "$3" "${4:-}";;
    collect) [[ $# == 3 ]] || die 'collect requires SSH_ALIAS NEW_DIRECTORY'; collect "$2" "$3";;
    *) usage >&2; exit 1;;
esac
