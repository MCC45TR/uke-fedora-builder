#!/usr/bin/env bash
# A private same-recipe Actions artifact, never a flashable or released image.
public_core_packages_check() {
    local baseline=$1 installed=$2
    [[ -s $baseline && -s $installed ]] || return 1
    LC_ALL=C sort --check "$baseline" && LC_ALL=C sort --check "$installed" || return
    [[ -z $(LC_ALL=C comm -23 "$baseline" "$installed") ]]
}

public_core_restore() {
    local archive=$1 work=$2 key
    [[ -f $archive && ! -L $archive && -d $work && ! -e $work/shared-core ]] || return 1
    mkdir "$work/shared-core"
    tar --zstd --extract --no-same-owner -f "$archive" -C "$work/shared-core" || return
    # RPM proof files can legitimately be 0000 (shadow) or execute-only (sudo).
    # The unprivileged receiver owns this byte-evidence copy; make it readable
    # without changing the separately archived root's original modes or owners.
    [[ -d $work/shared-core/original-fedora && ! -L $work/shared-core/original-fedora ]] || return 1
    chmod -R u+rX "$work/shared-core/original-fedora" || return
    (cd "$work/shared-core" && sha256sum --check --strict --quiet core-SHA256SUMS) || return
    jq -e '.desktop=="core" and .shared_core_phase=="export" and .target=="image" and
        .fedora_release=="rawhide" and .channel=="unstable" and .filesystem=="ext4" and
        .architecture=="aarch64" and .mode=="singleboot" and .partition=="userdata"' "$work/shared-core/request.json" >/dev/null || return
    for key in builder_commit default_shell fedora_release channel filesystem size_mib mode partition kernel_profile kernel_rpm_request; do
        [[ $(jq -c --arg key "$key" '.[$key]' "$work/request.json") == "$(jq -c --arg key "$key" '.[$key]' "$work/shared-core/request.json")" ]] || return 1
    done
    # Retain the exact source/module tuple resolved by the core producer. Only
    # the desktop selection and current worker count may change in the request.
    jq --slurpfile selected "$work/request.json" \
        '. + {desktop:$selected[0].desktop,jobs:$selected[0].jobs,shared_core_phase:"import"}' \
        "$work/shared-core/request.json" > "$work/request.next" || return
    mv "$work/request.next" "$work/request.json"
    cp -a "$work/shared-core/artifacts/." "$work/artifacts/" || return
    jq --arg desktop "$(jq -er .desktop "$work/request.json")" --arg sha "$(sha256sum "$archive" | cut -d ' ' -f1)" \
        '. + {desktop:$desktop,shared_core_phase:"import",shared_core_sha256:$sha}' \
        "$work/artifacts/manifest.json" > "$work/manifest.next" || return
    mv "$work/manifest.next" "$work/artifacts/manifest.json"
}

public_core_pack() {
    local job=$1
    [[ $(id -u) == 0 && -s $job/rootfs.tar && -d $job/original-fedora && ! -e $job/core.tar.zst ]] || return 1
    jq -e '.desktop=="core" and .shared_core_phase=="export" and .image_built==false and
        .rpm_transaction_validated==true and .credentials_included==false' "$job/artifacts/manifest.json" >/dev/null || return
    (
        cd "$job" || exit
        cp artifacts/installed-rpms.tsv artifacts/core-installed-rpms.tsv
        find request.json rootfs.tar fedora-inputs.tsv original-fedora artifacts/kernel artifacts/tools \
            artifacts/manifest.json artifacts/core-installed-rpms.tsv artifacts/boot.img artifacts/boot-linux.img artifacts/boot-userdata.img \
            -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > core-SHA256SUMS
        tar --create --format=posix --numeric-owner --sort=name -I 'zstd -T2 -3' -f core.tar.zst \
            core-SHA256SUMS request.json rootfs.tar fedora-inputs.tsv original-fedora \
            artifacts/kernel artifacts/tools artifacts/manifest.json artifacts/core-installed-rpms.tsv artifacts/boot.img artifacts/boot-linux.img artifacts/boot-userdata.img
    )
}
