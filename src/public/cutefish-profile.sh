#!/usr/bin/env bash
# The actual composition, repository and installed-closure policy share one profile.
public_cutefish_profile() {
    local profile
    profile=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../configs/images" && pwd)/cutefish-rawhide.json
    jq -e '.schema==1 and .desktop=="cutefish" and .release=="rawhide" and .channel=="unstable" and
        .credentials_included==false and
        ([.packages[],.required_packages[],.repository_packages[]] | all(.[];test("^[A-Za-z0-9][A-Za-z0-9+._-]*$")))' "$profile" >/dev/null || return
    jq -r "$1" "$profile"
}
