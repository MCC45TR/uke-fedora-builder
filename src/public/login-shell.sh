#!/usr/bin/env bash
# Host-only image provisioning. AccountsService invokes useradd without a shell override.
set -Eeuo pipefail
root=$1 shell=$2
case $shell in bash|fish|zsh) ;; *) echo 'Unsupported login shell' >&2; exit 1;; esac
[[ -d $root/etc && ! -L $root/etc && -f $root/etc/passwd ]]
# Read the executable from the target RPM; never use the host's shell lookup.
path=''
while IFS= read -r candidate; do
    case $candidate in /bin/"$shell"|/usr/bin/"$shell")
        [[ -z $path ]] || continue
        chroot "$root" test -x "$candidate"
        path=$candidate;;
    esac
done < <(rpm --root "$root" -ql "$shell")
[[ -n $path ]] || { echo 'Target shell RPM has no executable' >&2; exit 1; }
grep -Fxq -- "$path" "$root/etc/shells"
before=$(sha256sum "$root/etc/passwd")
chroot "$root" /usr/sbin/useradd -D -s "$path"
[[ $(sha256sum "$root/etc/passwd") == "$before" ]]
# This changes new-account defaults only; existing accounts and root retain their shells.
jq -n --arg shell "$shell" --arg path "$path" '{shell:$shell,path:$path,provisioning:"useradd-default; graphical first-account validation pending",first_account_tested:false}'
