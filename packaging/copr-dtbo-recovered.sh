#!/usr/bin/bash
# Source-worker assembly only. The existing reference collector compiles nothing.
set -Eeuo pipefail
[[ $# == 1 && ${UKE_COPR_SOURCE_WORKER:-} == 1 && $(uname -m) == aarch64 ]]
owner=$(cd -- "$(dirname -- "$0")/.." && pwd)
result=$(realpath -m "$1")
bash "$owner/packaging/copr-dtbo-roundtrip.sh" "$result"
unlink "$result/uke-dtbo-tools-source-check.spec"
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
# This signed, previously qualified receipt retains unmodified formatter sources.
curl -qfsSL --max-time 120 --max-filesize 1048576 https://download.copr.fedorainfracloud.org/results/mcc45tr/uke-linux-test/fedora-rawhide-aarch64/Packages/u/uke-dtbo-tools-source-check-1.0-7.fc46.aarch64.rpm -o "$work/proof7.rpm"
printf '%s  %s\n' f66336f8a64b7c665f5bc716141cac4e8930967c157c863871460af145797aa6 "$work/proof7.rpm" | sha256sum -c --strict --quiet -
rpm2cpio "$work/proof7.rpm" | cpio -i --to-stdout --quiet ./usr/share/licenses/uke-dtbo-tools-source-check/upstream-notices.tar.xz > "$result/dtbo-upstream.tar.xz"
printf '%s  %s\n' 9458f02f027d449b6ff507790b51662247e68d031f94b97495a0fe4685e820cc "$result/dtbo-upstream.tar.xz" | sha256sum -c --strict --quiet -
install -m644 "$owner/tests/dtbo-producer.sh" "$owner/src/image/inspect-dtbo-reference.sh" \
 "$owner/src/image/package-recovered-dtbo.sh" "$owner/packaging/dtbo-tools-source.json" \
 "$owner/packaging/dtbo-recovered-qualification.json" "$result/"
install -m644 "$owner/packaging/uke-dtbo-recovered.spec" "$result/uke-senemos-dtbo.spec"
[[ $(rpmspec --target aarch64 --define 'dist .fc46' -q --srpm --qf '%{NAME}-%{VERSION}-%{RELEASE}' "$result/uke-senemos-dtbo.spec") == uke-senemos-dtbo-1.0-1.fc46 ]]
printf 'Complete public DTBO sources and exact qualified AOSP sources collected; native transport and runtime RPM checks remain in COPR.\n'
