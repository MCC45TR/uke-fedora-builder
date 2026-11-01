#!/usr/bin/env bash
# Host-side scan of an already extracted target payload. Never runs target files.
set -euo pipefail
export LC_ALL=C
original=''
if [[ ${1:-} == --original-kde-payload ]]; then
  [[ $# == 3 && -d $2 ]] || exit 2
  original=$(realpath -- "$2"); shift 2
fi
[[ $# == 1 && -d $1 ]] || { echo 'Usage: check-target-payload.sh [--original-kde-payload VERIFIED_ORIGINAL_DIRECTORY] EXTRACTED_TARGET_DIRECTORY' >&2; exit 2; }
for tool in realpath find findmnt jq readlink readelf cmp mktemp rm; do
  command -v "$tool" >/dev/null || { printf 'Missing host audit tool: %s\n' "$tool" >&2; exit 2; }
done
root=$(realpath -- "$1")
[[ $root != / && $original != "$root" ]] || exit 2
# Finish discovery before issuing any acceptance result. Process substitution
# would hide find's exit status and could silently omit an unreadable subtree.
listing=$(mktemp)
mounts=$(mktemp)
read_errors=$(mktemp)
trap 'rm -f -- "$listing" "$mounts" "$read_errors"' EXIT
# Never inspect a live procfs/sysfs/device mount as extracted RPM bytes. Fail
# before discovery rather than pruning paths that could contain real payload.
if ! findmnt --all --list --json --output TARGET > "$mounts" ||
   ! jq -e --arg prefix "$root/" '
     (.filesystems | type == "array" and length > 0) and
     all(.filesystems[]; (.target | type == "string") and
                        (.target | startswith($prefix) | not))' "$mounts" >/dev/null; then
  echo 'Mounted target subtree or incomplete mount inventory; payload audit refused' >&2
  exit 1
fi
if ! find "$root" -mindepth 1 \( -type f -o -type l \) -print0 > "$listing"; then
  echo 'Target traversal failed; payload audit is incomplete' >&2
  exit 1
fi
python_needed=$'NEEDED[^\n]*libpython'
failed=0
python_payload() {
  local path=$1 expected
  if [[ -n $original ]]; then
    expected=$original/${path#"$root/"}
    # Only bytes from the separately verified original KDE closure may pass.
    if [[ -L $path && -L $expected && $(realpath -- "$(dirname -- "$expected")") == "$original/"* && $(readlink -- "$path") == "$(readlink -- "$expected")" ]]; then return; fi
    if [[ ! -L $path && ! -L $expected && -f $expected && $(realpath -- "$expected") == "$original/"* ]] && cmp -s -- "$path" "$expected"; then return; fi
  fi
  printf 'Unapproved Python target payload: %s\n' "${path#"$root/"}" >&2
  failed=1
}
while IFS= read -r -d '' path; do
  name=${path##*/}
  case "$name" in
    *.py|*.pyc|*.pyo|*.pyz|python|python[0-9]*|libpython*|pypy*)
      python_payload "$path"; continue;;
  esac
  if [[ -L $path ]]; then
    link=$(readlink -- "$path")
    case "${link##*/}" in python*|pypy*|libpython*) python_payload "$path";; esac
  elif [[ -f $path ]]; then
    [[ -r $path ]] || { printf 'Unreadable target file: %s\n' "${path#"$root/"}" >&2; failed=1; continue; }
    # Bound the header read without spawning several processes for every file.
    header=''
    if IFS= read -r -n 256 -d '' header 2> "$read_errors" < "$path"; then :
    elif [[ -s $read_errors ]]; then
      printf 'Unreadable target header rejected: %s\n' "${path#"$root/"}" >&2
      failed=1; continue
    fi
    if [[ $header =~ ^\#\![^[:cntrl:]]*(python|pypy) ]]; then
      python_payload "$path"
    elif [[ ${header:0:4} == $'\177ELF' ]]; then
      if ! dynamic=$(readelf -d -- "$path" 2>/dev/null); then
        printf 'Unreadable target ELF rejected: %s\n' "${path#"$root/"}" >&2; failed=1
      elif [[ $dynamic =~ $python_needed ]]; then
        python_payload "$path"
      fi
    fi
  fi
done < "$listing"
((failed==0)) || exit 1
if [[ -n $original ]]; then
  echo 'Extracted target payload: Python limited to byte-identical verified original KDE closure'
else
  echo 'Extracted target payload: no recognized Python files, entrypoints or dynamic dependencies'
fi
