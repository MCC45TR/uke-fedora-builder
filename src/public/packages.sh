#!/usr/bin/env bash
# Shared host-worker transaction capture; never sourced on the tablet.
# shellcheck disable=SC2154
public_replay() {
    local transaction=$1 action repository package
    [[ -d $transaction && ! -L $transaction && ! -L $transaction/packages &&
       -f $transaction/transaction.json && ! -L $transaction/transaction.json &&
       -f $transaction/SHA256SUMS && ! -L $transaction/SHA256SUMS ]] || return 1
    (cd "$transaction" && sha256sum -c SHA256SUMS) || return
    jq -e '.version=="1.0" and (.rpms|type=="array")' "$transaction/transaction.json" > /dev/null || return
    # shortcut: package install/builddep actions only; extend for group/removal workflows.
    while IFS=$'\t' read -r action repository package; do
        [[ $action != Replaced ]] || continue
        case $action in Install|Upgrade|Downgrade|Reinstall) ;; *) return 1;; esac
        [[ $package == ./packages/*.rpm && ${package#./packages/} != */* &&
           -f $transaction/$package && ! -L $transaction/$package ]] || return 1
        case $repository in
            '@stored_transaction(@commandline)'|'@stored_transaction(uke-source-build)') ;;
            *) rpmkeys --root "$rpm_root" --checksig "$transaction/$package" | grep -F 'signatures OK' || return 1;;
        esac
    done < <(jq -r '.rpms[]|[.action,.repo_id,.package_path]|@tsv' "$transaction/transaction.json")
    # Stored transactions omit per-repository keys/settings; verify above first.
    "${dnf[@]}" --disable-repo='*' --setopt=gpgcheck=False --setopt=localpkg_gpgcheck=False -y replay "$transaction"
}
public_packages() {
    local transaction=$1 operation=$2 package name destination
    shift 2
    [[ ! -e $transaction ]] || { echo 'Package transaction already exists' >&2; return 1; }
    mkdir -p -- "$(dirname -- "$transaction")" || return
    "${dnf[@]}" "${repositories[@]}" -y "$operation" --store="$transaction" "$@" || return
    if [[ ! -f $transaction/transaction.json ]]; then
        mkdir -p -- "$transaction" || return
        printf '%s\n' 'DNF5 resolved no package changes.' > "$transaction/NO_CHANGES"
        return
    fi
    mkdir -p -- "$transaction/packages" || return
    # DNF5 records command-line RPMs but does not copy their bytes into the store.
    for package in "$@"; do
        [[ $package == *.rpm && -f $package ]] || continue
        name=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}.rpm' "$package") || return
        destination=$transaction/packages/$name
        if jq -e --arg path "./packages/$name" 'any(.rpms[]; .package_path==$path)' "$transaction/transaction.json" > /dev/null; then
            if [[ -e $destination ]]; then cmp -- "$package" "$destination" || return
            else cp -- "$package" "$destination" || return; fi
        fi
    done
    (cd "$transaction" && find . -type f ! -path './SHA256SUMS.part' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) > "$transaction/SHA256SUMS.part" || return
    mv "$transaction/SHA256SUMS.part" "$transaction/SHA256SUMS" || return
    public_replay "$transaction"
}
