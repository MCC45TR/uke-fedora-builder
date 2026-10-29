#!/usr/bin/env bash
# Host-only source acquisition. Sourcing this file performs no acquisition/build.
admit_release_builder() {
    # A versioned producer declaration is required before running a historical recipe.
    jq -e '.schema_version == 1 and .local_kernel_repository == true and
      .explicit_kernel_version == true and .cohort_validation == true' \
      "$1/uke-fedora-builder/configs/source-selection.json" >/dev/null || {
        echo 'Selected aggregate has no supported exact-source/cohort builder capability' >&2; return 1;
      }
}
checkout_release_workspace() (
    set -Eeuo pipefail
    local url=$1 commit=$2 destination=$3
    [[ $commit =~ ^[0-9a-f]{40}$ ]] || { echo 'Select a full lowercase aggregate commit SHA' >&2; exit 1; }
    [[ ! -e $destination ]] || { echo 'Workspace destination already exists' >&2; exit 1; }
    git clone --no-checkout -- "$url" "$destination"
    git -C "$destination" fetch origin "$commit"
    git -C "$destination" checkout --detach "$commit"
    [[ $(git -C "$destination" rev-parse HEAD) == "$commit" ]]
    git -C "$destination" submodule update --init --recursive
    if git -C "$destination" submodule status --recursive | grep -Eq '^[+U-]'; then
        echo 'Unresolved or mismatched submodule pins' >&2; exit 1
    fi
    [[ -z $(git -C "$destination" status --porcelain) ]]
)
