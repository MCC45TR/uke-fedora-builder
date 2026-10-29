#!/usr/bin/env bash
# Host worker only: isolate binfmt while preserving every available numeric ID.
set -Eeuo pipefail
[[ $# -gt 0 && $(id -u) == 0 ]]
options=(--user --mount --propagation private)
while read -r inside _ count; do
    options+=(--map-users="$inside:$inside:$count")
done < /proc/self/uid_map
while read -r inside _ count; do
    options+=(--map-groups="$inside:$inside:$count")
done < /proc/self/gid_map
exec unshare "${options[@]}" -- "$@"
