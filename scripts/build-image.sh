#!/usr/bin/env bash
# Host-only package image entry; source compilation requires --build-from-source.
set -Eeuo pipefail
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/image/core.sh
# shellcheck disable=SC1091
source "$builder/src/image/core.sh"
# shellcheck source=../src/public/entry.sh
# shellcheck disable=SC1091
source "$builder/src/public/entry.sh"
public_main --build image "$@"
