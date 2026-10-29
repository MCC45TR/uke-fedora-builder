#!/usr/bin/env bash
# Run only in a disposable Fedora container, never on a host or tablet.
set -Eeuo pipefail
[[ ${UKE_DISPOSABLE_SHELL_TEST:-0} == 1 && $(id -u) == 0 ]]
[[ -f /run/.containerenv || -f /.dockerenv ]]
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
root_before=$(getent passwd root)
useradd -m -s /bin/sh uke-existing-shell
existing_before=$(getent passwd uke-existing-shell)
for shell in bash fish zsh; do
    bash "$root/src/public/login-shell.sh" / "$shell"
    name=uke-shell-$shell
    useradd -m "$name"
    selected=$(getent passwd "$name" | cut -d: -f7)
    [[ $selected == /usr/bin/"$shell" || $selected == /bin/"$shell" ]]
    grep -Fxq "$selected" /etc/shells
    rpm -qf "$selected"
    # PATH must expand in the new login shell.
    # shellcheck disable=SC2016
    runuser -l "$name" -c 'test -n "$PATH"'
    [[ $(getent passwd root) == "$root_before" && $(getent passwd uke-existing-shell) == "$existing_before" ]]
done
printf '%s\n' 'PASS: actual Fedora useradd defaults, login, RPM ownership and existing-account preservation'
