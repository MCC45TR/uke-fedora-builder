#!/usr/bin/env bash
# Shared by the full root stage and the offline COPR guest integration check.
# The caller supplies its existing DNF policy and complete package selection.
public_root_transaction() {
    local root=$1 log=$2
    local -n transaction_dnf=$3 transaction_rpms=$4 transaction_packages=$5
    [[ -d $root && ! -L $root && ${#transaction_packages[@]} -gt 0 ]] || return 1
    # Never inherit a host bus. Keep RPM scriptlets and ordinary offline presets.
    SYSTEMD_IN_CHROOT=0 "${transaction_dnf[@]}" -y install \
        "${transaction_rpms[@]}" "${transaction_packages[@]}" 2>&1 | tee "$log" || return
    # RPM can report failed scriptlets without a failing DNF exit status.
    if grep -Ei 'scriptlet failed|scriptlet failure|Error in .*scriptlet' "$log"; then
        echo 'Root transaction contains a failed RPM scriptlet' >&2
        return 1
    fi
    chroot "$root" /usr/bin/true || return
    "${transaction_dnf[@]}" check
}
