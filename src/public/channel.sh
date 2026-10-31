#!/usr/bin/env bash
# Fixed repository/key routes shared by kernel and root assembly.
# shellcheck disable=SC2034
public_channel() {
    local channel=$1 policy=$2 project fingerprint expected_project expected_fingerprint
    case $channel in
        stable) expected_project=uke-linux; expected_fingerprint=30DFB81A724CE0762F9DF77F844A293E5068FAFE;;
        testing) expected_project=uke-linux-test; expected_fingerprint=DAFC3C5A881FB49C7167EE2D6F772E3D487BD13E;;
        unstable) expected_project=uke-linux-unstable; expected_fingerprint=2204A661EA630A5303500085538797E72A3E4ECA;;
        *) return 1;;
    esac
    project=$(jq -er --arg channel "$channel" '.channels[$channel].project' "$policy") || return
    fingerprint=$(jq -er --arg channel "$channel" '.channels[$channel].fingerprint' "$policy") || return
    [[ $project == "$expected_project" && $fingerprint == "$expected_fingerprint" ]] || return 1
    PUBLIC_PROJECT=$project PUBLIC_FINGERPRINT=$fingerprint
}
