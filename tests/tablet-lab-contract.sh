#!/usr/bin/env bash
# Fixture transports only: this test cannot access a physical tablet.
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
trap 'find "$scratch" -depth -delete' EXIT
mkdir "$scratch/bin" "$scratch/images"
export CALLS=$scratch/calls PRODUCT=uke DEVICES=one
cat > "$scratch/bin/fastboot" <<'EOF'
#!/bin/bash
set -eu
printf '%s\n' "$*" >> "$CALLS"
if [[ $1 == devices ]]; then
    printf 'fixture fastboot\n'
    [[ $DEVICES != two ]] || printf 'second fastboot\n'
elif [[ $3 == getvar ]]; then
    case $4 in
        product) printf 'product: %s\r\n' "$PRODUCT" >&2;;
        unlocked) echo 'unlocked: yes' >&2;;
        is-userspace) echo 'is-userspace: no' >&2;;
        *) exit 1;;
    esac
elif [[ $3 == boot ]]; then test -f "$4";
else exit 1; fi
EOF
cat > "$scratch/bin/ssh" <<'EOF'
#!/bin/bash
set -eu
printf '%s\n' "$*" >> "$CALLS"
if [[ ${*: -2} == 'sh -s' ]]; then
    cat >/dev/null
    [[ ${FOREIGN_IDENTITY:-0} == 0 ]] || exit 1
fi
if [[ ${FAIL_EARLY:-0} == 1 && ${*: -1} == *'uname -a;'* ]]; then
    if [[ ${*: -1} == 'set -e; '* ]]; then bash -c 'set -e; false; true';
    else bash -c 'false; true'; fi
    exit $?
fi
echo 'Fixture observation'
EOF
chmod +x "$scratch/bin/fastboot" "$scratch/bin/ssh"
export PATH=$scratch/bin:$PATH
truncate -s 100663296 "$scratch/images/fixture.img"
hash=$(sha256sum "$scratch/images/fixture.img" | cut -d ' ' -f1)
jq -n --arg hash "$hash" '{schema_version:1,device:"uke",soc:"SM7675",root_selector:"PARTLABEL=linux",flash_allowed:false,
    cases:["rollback","core","gpu","timeout"]|map({id:.,image:"images/fixture.img",sha256:$hash,
    kernel_release:(if .=="rollback" then "7.2.9-senemos-uke" else "7.2.10-senemos-uke" end),physical_tested_this_trial:false,flash_allowed:false})}' > "$scratch/manifest.json"
runner=$root/tests/tablet-lab.sh
bash "$runner" verify "$scratch"
test ! -e "$CALLS"
bash "$runner" boot "$scratch" core
grep -q 'boot .*images/fixture.img' "$CALLS"
count=$(wc -l < "$CALLS")
if bash "$runner" boot "$scratch" timeout; then exit 1; fi
test "$(wc -l < "$CALLS")" == "$count"
if PRODUCT=foreign bash "$runner" boot "$scratch" gpu; then exit 1; fi
if PRODUCT=$'uke\r\nproduct: foreign' bash "$runner" boot "$scratch" gpu; then exit 1; fi
if DEVICES=two bash "$runner" boot "$scratch" core; then exit 1; fi
test "$(grep -c 'boot .*images' "$CALLS")" == 1
cp "$scratch/manifest.json" "$scratch/saved.json"
jq '.cases[0].image="images/../foreign.img"' "$scratch/saved.json" > "$scratch/manifest.json"
if bash "$runner" verify "$scratch"; then exit 1; fi
jq '.cases[0].sha256=("0"*64)' "$scratch/saved.json" > "$scratch/manifest.json"
if bash "$runner" verify "$scratch"; then exit 1; fi
cp "$scratch/saved.json" "$scratch/manifest.json"
touch "$scratch/ssh-config"
export UKE_SSH_CONFIG=$scratch/ssh-config
bash "$runner" collect fixture "$scratch/collection"
test "$(stat -c %a "$scratch/collection")" == 700
test "$(stat -c %a "$scratch/collection/kernel.log")" == 600
(cd "$scratch/collection" && sha256sum -c SHA256SUMS >/dev/null)
if bash "$runner" collect fixture "$scratch/collection"; then exit 1; fi
if FOREIGN_IDENTITY=1 bash "$runner" collect fixture "$scratch/foreign"; then exit 1; fi
test ! -e "$scratch/foreign/kernel.log"
code=0
FAIL_EARLY=1 bash "$runner" collect fixture "$scratch/early-failure" || code=$?
test "$code" == 2
grep -qx $'startup\t1' "$scratch/early-failure/results.tsv"
test -s "$scratch/early-failure/kernel.log"
if grep -Eq '(^| )(flash|erase|set_active|reboot)( |$)' "$CALLS"; then exit 1; fi
echo 'PASS: verified RAM boot, foreign/multiple-device refusal, corrupt/path rejection and private identity-gated collection; no physical transport used.'
