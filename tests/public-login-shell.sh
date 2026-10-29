#!/usr/bin/env bash
# Disposable host fixtures; no account on the build host is modified.
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/root/etc"
export UKE_SHELL_FIXTURE=$fixture
printf 'root:x:0:0:root:/root:/bin/bash\nexisting:x:1000:1000::/home/existing:/bin/custom\n' > "$fixture/root/etc/passwd"
cp "$fixture/root/etc/passwd" "$fixture/passwd.before"
rpm() { [[ $* == *'-ql'* ]] || return 1; printf '/usr/bin/%s\n' "${*: -1}"; }
chroot() {
    shift
    case $1 in
        test) [[ -e $UKE_SHELL_FIXTURE/executable ]];;
        /usr/sbin/useradd) [[ $2 == -D && $3 == -s ]]; printf 'SHELL=%s\n' "$4" > "$UKE_SHELL_FIXTURE/default";;
        *) return 1;;
    esac
}
export -f rpm chroot
for shell in bash fish zsh; do
    : > "$fixture/executable"
    printf '/usr/bin/%s\n' "$shell" > "$fixture/root/etc/shells"
    bash "$root/src/public/login-shell.sh" "$fixture/root" "$shell" > "$fixture/result.json"
    jq -e --arg shell "$shell" '.shell==$shell and .path==("/usr/bin/"+$shell) and .first_account_tested==false' "$fixture/result.json" >/dev/null
    grep -Fxq "SHELL=/usr/bin/$shell" "$fixture/default"
    cmp "$fixture/passwd.before" "$fixture/root/etc/passwd"
    rm "$fixture/executable"
    if bash "$root/src/public/login-shell.sh" "$fixture/root" "$shell" >/dev/null 2>&1; then exit 1; fi
    : > "$fixture/executable"; : > "$fixture/root/etc/shells"
    if bash "$root/src/public/login-shell.sh" "$fixture/root" "$shell" >/dev/null 2>&1; then exit 1; fi
done
if bash "$root/src/public/login-shell.sh" "$fixture/root" invalid >/dev/null 2>&1; then exit 1; fi
printf '%s\n' 'PASS: target shell ownership, executable/shells refusal and unchanged existing accounts'
