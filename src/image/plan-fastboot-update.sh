#!/usr/bin/bash
# Data-only installation plan. No compile, image creation or device access.
set -Eeuo pipefail
[[ $# == 2 ]]
composition=$(realpath "$1")
output=$(realpath -m "$2")
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
[[ -f $composition && ! -L $composition && ! -e $output && ! -L $output ]]
jq -e '.kernel_release|test("^[0-9]+[.][0-9]+[.][0-9]+-[1-9][0-9]*-unstable$")' "$composition" >/dev/null
jq -e '.source_commit|test("^[a-f0-9]{40}$")' "$composition" >/dev/null
mkdir -m755 "$output"
jq --slurpfile source "$composition" \
   --arg planner "$(git -C "$repo" rev-parse HEAD)" \
   --arg hash "$(sha256sum "$composition" | cut -d ' ' -f1)" \
   '. + {planner_commit:$planner,kernel:{release:$source[0].kernel_release,source_commit:$source[0].source_commit,composition_sha256:$hash},
     payloads_available:false,archive_created:false,
     kernel_encryption_in_full_candidate:($source[0].storage_encryption_enabled_in_full_candidate==true)}' \
   "$repo/configs/images/fastboot-update-uke.json" > "$output/release-plan.json"
printf 'require product=uke\n' > "$output/android-info.txt"
{
 printf 'version 1\n'
 jq -r '.payloads[]|"flash "+.partition+" "+.file' "$repo/configs/images/fastboot-update-uke.json"
} > "$output/fastboot-info.txt"
cp "$repo/docs/FASTBOOT-UPDATE-PREPARATION.md" "$output/README.md"
printf 'Fastboot install plan prepared; no images,ZIP,flash,slot change or encryption activation.\n'
