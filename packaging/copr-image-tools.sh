#!/usr/bin/env bash
# COPR custom source worker only. Produces unpacked native RPM build inputs.
set -Eeuo pipefail
[[ $# == 1 && $1 =~ ^[a-f0-9]{40}$ && -n ${COPR_RESULTDIR:-} ]]
source_commit=$1
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
curl --proto '=https' --tlsv1.2 --fail --location --retry 3 \
    "https://github.com/MCC45TR/uke-fedora-builder/archive/$source_commit.tar.gz" -o "$work/source.tar.gz"
mkdir "$work/uke-image-tools-1.0.0"
tar -xf "$work/source.tar.gz" --strip-components=1 -C "$work/uke-image-tools-1.0.0"
jq -n --arg commit "$source_commit" --arg archive "$(sha256sum "$work/source.tar.gz" | cut -d ' ' -f1)" \
    '{repository:"https://github.com/MCC45TR/uke-fedora-builder",commit:$commit,archive_sha256:$archive,
      native_build_location:"COPR fedora-rawhide-aarch64",physical_acceptance:false}' > "$COPR_RESULTDIR/source-identity.json"
tar -cJf "$COPR_RESULTDIR/uke-image-tools-1.0.0.tar.xz" -C "$work" uke-image-tools-1.0.0
cp "$work/uke-image-tools-1.0.0/packaging/uke-image-tools.spec" "$COPR_RESULTDIR/"
mkdir "$work/guest-inputs"
bash "$work/uke-image-tools-1.0.0/packaging/copr-guest-inputs.sh" \
    "$work/uke-image-tools-1.0.0" "$work/guest-inputs"
jq --arg sha "$(sha256sum "$COPR_RESULTDIR/guest-fedora-inputs.tar.xz" | cut -d ' ' -f1)" \
    '. + {guest_inputs_sha256:$sha,guest_inputs_origin:"signature-verified public Fedora RPMs"}' \
    "$COPR_RESULTDIR/source-identity.json" > "$work/identity.json"
mv "$work/identity.json" "$COPR_RESULTDIR/source-identity.json"
