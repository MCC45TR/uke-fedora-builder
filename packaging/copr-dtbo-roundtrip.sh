#!/usr/bin/bash
# Source-worker data collection only; DTS compilation is in native RPM build.
set -Eeuo pipefail
[[ $# == 1 && ${UKE_COPR_SOURCE_WORKER:-} == 1 && $(uname -m) == aarch64 ]]
owner=$(cd -- "$(dirname -- "$0")/.." && pwd)
pins=$owner/packaging/dtbo-roundtrip-source.json
result=$(realpath -m "$1")
[[ ! -e $result && ! -L $result ]]
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
mkdir "$result" "$work/reference"
[[ $(jq -er '.inputs|length' "$pins") == 5 ]]
while IFS=$'\t' read -r name path bytes hash;do
 [[ $name =~ ^(dtbo[.]img|base-[0-3][.]dtb)$ && $path =~ ^[A-Za-z0-9_,./-]+$ && $path != *..* ]]
 [[ $bytes =~ ^[1-9][0-9]{4,5}$ && $hash =~ ^[a-f0-9]{64}$ ]]
 curl -qfsSL --max-time 90 --max-filesize 1048576 \
  "https://raw.githubusercontent.com/Xiaomi-Pad-7-Pro-Resources/android_device_xiaomi_uke-kernel/0d2b9c42b8e1873e6c7b61326b35c94c991ab713/$path" -o "$work/reference/$name"
 [[ $(stat -c %s "$work/reference/$name") == "$bytes" ]]
 printf '%s  %s\n' "$hash" "$work/reference/$name" | sha256sum -c --strict --quiet -
done < <(jq -r '.inputs[]|[.name,.path,(.bytes|tostring),.sha256]|@tsv' "$pins")
tar --sort=name --mtime=@1794700800 --owner=0 --group=0 --numeric-owner -cJf "$result/public-dt-reference.tar.xz" -C "$work/reference" .
install -m644 "$owner/tests/dtbo-reference-roundtrip.sh" "$pins" "$result/"
install -m644 "$owner/packaging/uke-dtbo-roundtrip-check.spec" "$result/uke-dtbo-tools-source-check.spec"
[[ $(rpmspec --target aarch64 --define 'dist .fc46' -q --srpm --qf '%{NAME}-%{VERSION}-%{RELEASE}' "$result/uke-dtbo-tools-source-check.spec") == uke-dtbo-tools-source-check-1.0-9.fc46 ]]
printf 'Public complete FDT references pinned; native roundtrip remains a diagnostic without original-source, runtime or physical admission.\n'
