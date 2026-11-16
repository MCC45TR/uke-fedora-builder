#!/usr/bin/bash
# Fake account databases only; no real password, authentication or device access.
set -Eeuo pipefail
[[ $(id -u) == 0 ]]
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/image/rescue-admin-policy.sh
# shellcheck disable=SC1091
source "$repo/src/image/rescue-admin-policy.sh"
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
root=$work/root
fixture_hash="\$6\$fixture\$structural_only"
reset(){
    if [[ -d $root ]];then find "$root" -depth -delete;fi
    mkdir -m700 "$root" "$root/etc"
    printf 'root:x:0:0:root:/root:/bin/bash\nfixture:x:1000:1000:Fixture:/home/fixture:/bin/bash\n' > "$root/etc/passwd"
    printf 'root:x:0:\nwheel:x:10:fixture\nfixture:x:1000:\n' > "$root/etc/group"
    printf 'root:!:20000:0:99999:7:::\nfixture:%s:20000:0:99999:7:::\n' "$fixture_hash" > "$root/etc/shadow"
    chmod 644 "$root/etc/passwd" "$root/etc/group"
    chmod 600 "$root/etc/shadow"
}
reject(){
    if uke_rescue_admin_hash "$root" "${1:-fixture}" > "$work/result" 2> "$work/error";then
        echo 'Unsafe rescue identity admitted' >&2;exit 1
    fi
    [[ ! -s $work/result ]]
}
reset
[[ $(uke_rescue_admin_hash "$root" fixture) == "$fixture_hash" ]]
reject unknown
reject root
reject $'fixture\\nroot'
reject 'fixture;root'
sed -i 's/wheel:x:10:fixture/wheel:x:10:fixture2/' "$root/etc/group"
reject
reset
sed -i 's/1000:1000/1000:10/' "$root/etc/passwd"
sed -i 's/wheel:x:10:fixture/wheel:x:10:/' "$root/etc/group"
[[ $(uke_rescue_admin_hash "$root" fixture) == "$fixture_hash" ]]
reset
sed -i 's/fixture:x:1000/fixture:x:0/' "$root/etc/passwd"
reject
reset
sed -i 's/fixture:\$/fixture:!$/' "$root/etc/shadow"
reject
reset
printf 'fixture:x:1001:1001:Duplicate:/home/other:/bin/bash\n' >> "$root/etc/passwd"
reject
reset
printf 'wheel:x:20:fixture\n' >> "$root/etc/group"
reject
reset
tail -n1 "$root/etc/shadow" >> "$work/duplicate"
cat "$work/duplicate" >> "$root/etc/shadow"
reject
reset
mv "$root/etc/shadow" "$work/owned-shadow"
ln -s "$work/owned-shadow" "$root/etc/shadow"
reject
reset
chmod 666 "$root/etc/group"
reject
reset
ln "$root/etc/shadow" "$work/shadow-link"
reject
unlink "$work/shadow-link"
reset
chown 12345 "$root/etc/shadow"
reject
reset
truncate -s 1048577 "$root/etc/group"
reject
echo 'Rescue administrator data policy: primary/supplementary wheel, enabled hash, UID, duplicates, links, ownership, writable and bounded database refusals passed. No password authentication or hardware test.'
