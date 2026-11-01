#!/bin/sh
# Plasma Setup must finish before a normal user's NextKDE services may start.
set -eu
[ "$(id -u)" -ge 1000 ] && [ "$(id -u)" -lt 65534 ] || exit 0
[ -e /etc/plasma-setup-done ] || exit 0
case :${XDG_CURRENT_DESKTOP:-}: in *:KDE:*) ;; *) exit 0;; esac
exec systemctl --user start kos-platform.service kos-data.service kos-shell.service
