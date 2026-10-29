#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/public/workspace-source.sh
# shellcheck disable=SC1091
source "$root/src/public/workspace-source.sh"
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=Fixture
export GIT_CONFIG_KEY_1=user.email GIT_CONFIG_VALUE_1=fixture@example.invalid
export GIT_CONFIG_KEY_2=protocol.file.allow GIT_CONFIG_VALUE_2=always
git init -q -b main "$fixture/component"
printf old > "$fixture/component/code"
git -C "$fixture/component" add code; git -C "$fixture/component" commit -qm old
component_old=$(git -C "$fixture/component" rev-parse HEAD)
git init -q -b main "$fixture/aggregate"
git -C "$fixture/aggregate" submodule add -q "$fixture/component" component
git -C "$fixture/aggregate" commit -qm pin
selected=$(git -C "$fixture/aggregate" rev-parse HEAD)
printf new > "$fixture/component/code"
git -C "$fixture/component" commit -qam new
git -C "$fixture/aggregate/component" pull -q
git -C "$fixture/aggregate" commit -qam advance
checkout_release_workspace "$fixture/aggregate" "$selected" "$fixture/selected"
[[ $(git -C "$fixture/selected" rev-parse HEAD) == "$selected" ]]
[[ $(git -C "$fixture/selected/component" rev-parse HEAD) == "$component_old" ]]
reject() {
    if checkout_release_workspace "$fixture/aggregate" "$1" "$2" > "$fixture/rejected.log" 2>&1; then
        echo 'Invalid acquisition accepted' >&2; exit 1
    fi
}
for bad in main HEAD deadbeef 'main;false' 0000000000000000000000000000000000000000; do
    reject "$bad" "$fixture/rejected-${#bad}"
done
printf keep > "$fixture/selected/keep"
reject "$selected" "$fixture/selected"
[[ $(cat "$fixture/selected/keep") == keep ]]
echo 'Moved aggregate/component branches retained selected pins; invalid refs and occupied destinations refused'
# Never execute an old aggregate whose builder silently ignores the source override.
if admit_release_builder "$fixture/selected" >/dev/null 2>&1; then exit 1; fi
mkdir -p "$fixture/selected/uke-fedora-builder/configs"
capability=$fixture/selected/uke-fedora-builder/configs/source-selection.json
cp "$root/configs/source-selection.json" "$capability"
admit_release_builder "$fixture/selected"
for field in local_kernel_repository explicit_kernel_version cohort_validation; do
    jq --arg field "$field" '.[$field]=false' "$root/configs/source-selection.json" > "$capability"
    if admit_release_builder "$fixture/selected" >/dev/null 2>&1; then exit 1; fi
done
jq '.schema_version=2' "$root/configs/source-selection.json" > "$capability"
if admit_release_builder "$fixture/selected" >/dev/null 2>&1; then exit 1; fi
echo 'Legacy/missing/disabled/unknown source-selection capabilities refused before recipe execution'
