#!/usr/bin/bash
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
mkdir "$work/normal" "$work/unstable" "$work/rejected"
source_commit=717f7d6c8fd26d3c066f936101b8c2011391cbf2
printf '%s\n' "$source_commit" | jq -R '{
    kernel_source_commit:., kernel_profile:"normal",
    kernel_family:"senemos-uke-linux-kernel-mainline",
    kernel_repository:"mcc45tr/uke-linux", kernel_rpm_signature:"verified COPR signature",
    kernel_release:"7.3.6-4", rpm_version_release:"7.3.6-4", rpm_dist:".fc46"
}' > "$work/normal.json"
jq '. + {kernel_profile:"unstable",kernel_family:"senemos-uke-linux-kernel-mainline-unstable",
    kernel_repository:"mcc45tr/uke-linux-unstable",kernel_release:"7.3.6-4-unstable"}' \
    "$work/normal.json" > "$work/unstable.json"
program=$repo/src/image/rescue-seed-manifest.sh
for profile in normal unstable; do
    bash "$program" "$work/$profile" 671088640 "$work/$profile.json" 6442450944
    jq -e --slurpfile info "$work/$profile.json" '
        .kernel_release==$info[0].kernel_release and .kernel_source_commit==$info[0].kernel_source_commit
        and (.authorizes_key_release|not) and (.authorizes_resume|not)
    ' "$work/$profile/usr/share/uke-rescue/seed-layout.json" >/dev/null
done
for wrong in '.kernel_repository="mcc45tr/uke-linux"' '.kernel_family="senemos-uke-linux-kernel-mainline"' \
             '.rpm_version_release="7.3.6-5"' '.kernel_rpm_signature="unchecked"' '.rpm_dist=".fc45"'; do
    jq "$wrong" "$work/unstable.json" > "$work/rejected.json"
    if bash "$program" "$work/rejected" 671088640 "$work/rejected.json" 6442450944; then
        printf 'Accepted incorrect rescue kernel metadata: %s\n' "$wrong" >&2
        exit 1
    fi
    [[ ! -e $work/rejected/usr/share/uke-rescue/seed-layout.json ]]
done
printf 'Signed normal and unstable rescue tuples admitted; mismatched tuples rejected.\n'
