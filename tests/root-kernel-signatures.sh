#!/usr/bin/env bash
# Isolated verifier protocol: key import is mandatory; failed/unsigned results fail.
set -Eeuo pipefail
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/public/root-kernel-signatures.sh
# shellcheck disable=SC1091
source "$builder/src/public/root-kernel-signatures.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
printf pinned-public-key > "$work/key"
printf signed-rpm-fixture > "$work/kernel.rpm"
# shellcheck disable=SC2329
rpmkeys() {
    [[ $1 == --dbpath && $2 == "$work/database" ]]
    if [[ $3 == --import ]]; then
        [[ $4 == "$work/key" && ${refuse_import:-0} == 0 ]] || return 1
        touch "$2/initialized"
    elif [[ $3 == --checksig ]]; then
        [[ -f $2/initialized ]] || return 1
        case ${signature:-valid} in
            valid) printf '%s: digests signatures OK\n' "$4";;
            unsigned) printf '%s: digests OK\n' "$4";;
            corrupt) printf '%s: signatures NOT OK\n' "$4"; return 1;;
            false-success) printf '%s: signatures OK\n' "$4"; return 1;;
        esac
    else return 1; fi
}
public_root_kernel_signatures "$work/key" "$work/database" "$work/kernel.rpm"
for signature in unsigned corrupt false-success; do
    if public_root_kernel_signatures "$work/key" "$work/database" "$work/kernel.rpm" >/dev/null 2>&1; then exit 1; fi
done
signature=valid
if refuse_import=1 public_root_kernel_signatures "$work/key" "$work/database" "$work/kernel.rpm" >/dev/null 2>&1; then exit 1; fi
ln -s kernel.rpm "$work/link.rpm"
if public_root_kernel_signatures "$work/key" "$work/database" "$work/link.rpm" >/dev/null 2>&1; then exit 1; fi
echo 'Fresh worker imports its verified signer and rejects unsigned/corrupt archives, failed key import, false success and symlinks.'
