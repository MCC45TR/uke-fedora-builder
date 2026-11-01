#!/usr/bin/env bash
# Host-only real GDM/PAM integration. It never changes the public test account's
# delivered password: the temporary generated probe password is discarded.
public_gdm_password_probe() (
    set -Eeuo pipefail
    root=$1
    [[ $(id -u) == 0 && $root != / && -d $root && ! -L $root && ! -S $root/run/dbus/system_bus_socket ]]
    bus_pid='' accounts_pid=''
    # Invoked by the EXIT trap, including failed PAM conversations.
    # shellcheck disable=SC2317,SC2329
    cleanup_probe() {
        [[ -z $accounts_pid ]] || kill "$accounts_pid" 2>/dev/null || :
        [[ -z $bus_pid ]] || kill "$bus_pid" 2>/dev/null || :
        [[ -z $accounts_pid ]] || wait "$accounts_pid" 2>/dev/null || :
        [[ -z $bus_pid ]] || wait "$bus_pid" 2>/dev/null || :
        rm -f "$root/run/uke-gdm-password-probe.js" "$root/run/dbus/system_bus_socket"
    }
    trap cleanup_probe EXIT
    mkdir -p "$root/run/dbus"
    install -m600 /builder/tests/host/gdm-password-change.js "$root/run/uke-gdm-password-probe.js"
    chroot "$root" /usr/bin/dbus-daemon --system --nofork --nopidfile > /job/gdm-probe-bus.log 2>&1 & bus_pid=$!
    for _ in {1..50}; do
        [[ ! -S $root/run/dbus/system_bus_socket ]] || break
        kill -0 "$bus_pid"
        sleep 0.1
    done
    [[ -S $root/run/dbus/system_bus_socket ]]
    chroot "$root" /usr/libexec/accounts-daemon > /job/gdm-probe-accounts.log 2>&1 & accounts_pid=$!
    chroot "$root" /usr/bin/gjs /run/uke-gdm-password-probe.js > /job/gdm-password-change.log 2>&1
    cat /job/gdm-password-change.log
    awk -F: '$1=="senemos" {if($3<=0)exit 1;found=1} END{if(!found)exit 1}' "$root/etc/shadow"
    printf 'senemos:fedora\n' | chroot "$root" /usr/sbin/chpasswd
    chroot "$root" /usr/bin/chage -d 0 senemos
)
