#!/usr/bin/env bash
# Publish only validated image assets; receipt files remain in Actions artifacts.
set -Eeuo pipefail
export LC_ALL=C
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
layout_tool=$builder/src/public/release-layout.sh
delivery=$(realpath -- "${1:?Expected delivery directory}")
: "${GITHUB_REPOSITORY:?Expected owner/repository}" "${SOURCE_COMMIT:?Expected immutable source commit}" "${GITHUB_RUN_ID:?Expected Actions build record}"
[[ $GITHUB_REPOSITORY =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $SOURCE_COMMIT =~ ^[0-9a-f]{40}$ && $GITHUB_RUN_ID =~ ^[0-9]+$ ]]
export UKE_RELEASE_BUILD_RUNS=$GITHUB_RUN_ID
# shellcheck source=../src/public/release-layout.sh
# shellcheck disable=SC1091
source "$layout_tool"
bash "$layout_tool" verify "$delivery"
tag=$(jq -er .tag "$delivery/receipts/layout.json")
boot=$(jq -er .boot "$delivery/receipts/layout.json")
cohort=$(sha256sum "$delivery/receipts/cohort.json"); cohort=${cohort%% *}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
bash "$layout_tool" inventory "$delivery" > "$work/local.tsv"
while IFS=$'\t' read -r name bytes _; do
    ((bytes < 2147483648)) || release_fail "Release asset exceeds the 2 GiB limit: $name"
done < "$work/local.tsv"
bash "$layout_tool" body "$delivery" "$work/local.tsv" > "$work/notes.md"
existing=0
if gh api "repos/$GITHUB_REPOSITORY/releases/tags/$tag" > "$work/release.json" 2> "$work/query-error"; then
    existing=1
elif ! jq -e '(.status|tostring)=="404"' "$work/release.json" >/dev/null; then
    cat "$work/query-error" >&2
    release_fail 'Unable to inspect release; no publication attempted'
fi
if ((existing)); then
    # Never convert a legacy release by deleting receipts or renaming its assets.
    jq -e '.assets|all(.[]; .state=="uploaded" and (.digest|type=="string" and test("^sha256:[0-9a-f]{64}$")))' "$work/release.json" >/dev/null || release_fail 'Incomplete remote assets'
    while IFS= read -r name; do
        release_asset_name "$delivery/receipts/layout.json" "$name" || release_fail 'Existing release contains legacy or non-image assets; preserve it and choose a new revision'
    done < <(jq -r '.assets[].name' "$work/release.json")
    mapfile -t markers < <(jq -r .body "$work/release.json" | sed -n 's/^<!-- uke-image-cohort-sha256: \([0-9a-f]\{64\}\) -->$/\1/p')
    [[ ${#markers[@]} == 1 && ${markers[0]} == "$cohort" ]] || release_fail 'Existing release has a different or unrecorded boot cohort'
    mapfile -t prior_runs < <(jq -r .body "$work/release.json" | sed -n 's/^<!-- uke-image-build-runs: \([0-9,]*\) -->$/\1/p')
    [[ ${#prior_runs[@]} == 1 && ${prior_runs[0]} =~ ^[0-9]+(,[0-9]+)*$ ]] || release_fail 'Existing release has no reliable Actions receipt records'
    UKE_RELEASE_BUILD_RUNS=$(printf '%s,%s\n' "${prior_runs[0]}" "$GITHUB_RUN_ID" | tr ',' '\n' | sort -nu | paste -sd,)
    if jq -e --arg boot "$boot" 'any(.assets[]; .name==$boot)' "$work/release.json" >/dev/null; then
        mkdir "$work/remote"
        gh release download "$tag" --repo "$GITHUB_REPOSITORY" --pattern "$boot" --dir "$work/remote"
        cmp "$delivery/assets/$boot" "$work/remote/$boot" || release_fail 'Published shared boot bytes differ'
    fi
    # Check all name collisions before uploading anything; never use --clobber.
    while IFS=$'\t' read -r name _ sha; do
        remote=$(jq -r --arg name "$name" '.assets[]|select(.name==$name)|.digest' "$work/release.json")
        [[ -z $remote || $remote == "sha256:$sha" ]] || release_fail "Published image collision: $name; choose another revision"
    done < "$work/local.tsv"
else
    gh release create "$tag" --repo "$GITHUB_REPOSITORY" --target "$SOURCE_COMMIT" --draft --prerelease \
        --title "Fedora $(jq -r .version "$delivery/receipts/layout.json") Uke Senemos · $(jq -r .date "$delivery/receipts/layout.json") r$(jq -r .revision "$delivery/receipts/layout.json")" \
        --notes-file "$work/notes.md"
    printf '{"assets":[]}\n' > "$work/release.json"
fi
uploads=()
while IFS=$'\t' read -r name _ _; do
    if ! jq -e --arg name "$name" 'any(.assets[]; .name==$name)' "$work/release.json" >/dev/null; then
        uploads+=("$delivery/assets/$name")
    fi
done < "$work/local.tsv"
if ((${#uploads[@]})); then gh release upload "$tag" "${uploads[@]}" --repo "$GITHUB_REPOSITORY"; fi
gh api "repos/$GITHUB_REPOSITORY/releases/tags/$tag" > "$work/published.json"
jq -e '.assets|length>1 and all(.[]; .state=="uploaded" and (.digest|type=="string" and test("^sha256:[0-9a-f]{64}$")))' "$work/published.json" >/dev/null || release_fail 'Uploaded assets have no complete digest inventory'
while IFS= read -r name; do
    release_asset_name "$delivery/receipts/layout.json" "$name" || release_fail 'Unexpected remote asset; release body was not finalized'
done < <(jq -r '.assets[].name' "$work/published.json")
while IFS=$'\t' read -r name _ sha; do
    [[ $(jq -er --arg name "$name" '.assets[]|select(.name==$name)|.digest' "$work/published.json") == "sha256:$sha" ]] || release_fail 'Uploaded image digest mismatch'
done < "$work/local.tsv"
jq -r '.assets[]|[.name,(.size|tostring),(.digest|sub("^sha256:";""))]|@tsv' "$work/published.json" | LC_ALL=C sort > "$work/all.tsv"
bash "$layout_tool" body "$delivery" "$work/all.tsv" > "$delivery/receipts/RELEASE.md"
gh release edit "$tag" --repo "$GITHUB_REPOSITORY" --notes-file "$delivery/receipts/RELEASE.md" --draft=false --prerelease
gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json url --jq .url
