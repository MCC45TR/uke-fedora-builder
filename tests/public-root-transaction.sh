#!/usr/bin/env bash
# Failure controls only; all external root/package operations are shell doubles.
set -Eeuo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
source "$repo/src/public/root-transaction.sh"
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
mkdir "$work/root"
dnf_policy=(fake_dnf) local_inputs=() selection=(fixture)
fake_dnf() {
    if [[ $1 == check ]]; then return "${check_status:-0}"; fi
    [[ ${SYSTEMD_IN_CHROOT:-} == 0 ]] || return 91
    printf '%s\n' "${install_output:-Complete!}"
    return "${install_status:-0}"
}
chroot() { [[ $1 == "$work/root" && $2 == /usr/bin/true ]]; return "${chroot_status:-0}"; }
run() { public_root_transaction "$work/root" "$work/install.log" dnf_policy local_inputs selection; }
reject() { if run > /dev/null 2>&1; then echo 'Invalid transaction accepted' >&2; exit 1; fi; }
run
install_status=1; reject; unset install_status
check_status=1; reject; unset check_status
chroot_status=1; reject; unset chroot_status
for install_output in 'warning: %post scriptlet failed, exit status 1' 'Scriptlet failure in rpm' 'Error in POSTIN scriptlet'; do reject; done
unset install_output
run
printf '%s\n' 'Root transaction rejects DNF, dependency, execution and silent scriptlet failures; no root or package operations ran.'
