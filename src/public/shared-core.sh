#!/usr/bin/env bash
# A private same-recipe Actions artifact, never a flashable or released image.
public_core_desktop_free() {
    local inventory=$1
    [[ -s $inventory ]] || return 1
    if LC_ALL=C grep -E '^(plasma-workspace|plasma-setup|plasma-login-manager|gnome-shell|gnome-session|gnome-session-wayland-session|gnome-initial-setup|gdm|sddm|cutefish-desktop|nextkde|quickshell|uke-kde-plasma-meta|uke-gnome-meta)-[0-9]' "$inventory"; then
        printf 'Common core contains a desktop session or display manager\n' >&2
        return 1
    fi
}

public_core_packages_check() {
    local baseline=$1 installed=$2
    [[ -s $baseline && -s $installed ]] || return 1
    LC_ALL=C sort --check "$baseline" && LC_ALL=C sort --check "$installed" || return
    [[ -z $(LC_ALL=C comm -23 "$baseline" "$installed") ]]
}

public_core_restore() {
    local archive=$1 work=$2 producer=${3:-} key consumer producer_workspace=${UKE_SHARED_CORE_WORKSPACE:-} producer_run=${UKE_SHARED_CORE_RUN_ID:-}
    [[ ( -z $producer_workspace && -z $producer_run ) || ( $producer_workspace =~ ^[0-9a-f]{40}$ && $producer_run =~ ^[1-9][0-9]+$ ) ]] || return 1
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
    consumer=$(jq -er .builder_commit "$work/request.json")
    producer=${producer:-$consumer}
    [[ $producer =~ ^[0-9a-f]{40}$ && $(jq -er .builder_commit "$work/shared-core/request.json") == "$producer" ]] || return 1
    for key in default_shell fedora_release channel filesystem size_mib mode partition kernel_profile kernel_rpm_request; do
        [[ $(jq -c --arg key "$key" '.[$key]' "$work/request.json") == "$(jq -c --arg key "$key" '.[$key]' "$work/shared-core/request.json")" ]] || return 1
    done
    # Retain the exact source/module tuple resolved by the core producer. Only
    # the desktop selection and current worker count may change in the request.
    public_core_desktop_free "$work/shared-core/artifacts/core-installed-rpms.tsv" || return
    # shellcheck source=languages.sh
    # shellcheck disable=SC1091
    source "$(dirname -- "${BASH_SOURCE[0]}")/languages.sh"
    public_language_receipt "$work/shared-core/artifacts/language-audit.json" || {
        echo 'Frozen core predates the complete-language audit; rebuild the core' >&2
        return 1
    }
    jq --slurpfile selected "$work/request.json" --arg producer "$producer" \
        '. + {desktop:$selected[0].desktop,jobs:$selected[0].jobs,builder_commit:$selected[0].builder_commit,
            shared_core_producer_builder_commit:$producer,shared_core_phase:"import"}' \
        "$work/shared-core/request.json" > "$work/request.next" || return
    mv "$work/request.next" "$work/request.json"
    cp -a "$work/shared-core/artifacts/." "$work/artifacts/" || return
    jq --arg desktop "$(jq -er .desktop "$work/request.json")" --arg sha "$(sha256sum "$archive" | cut -d ' ' -f1)" --arg producer "$producer" --arg consumer "$consumer" \
        --arg workspace "$producer_workspace" --arg run "$producer_run" \
        '. + {desktop:$desktop,builder_commit:$consumer,shared_core_producer_builder_commit:$producer,shared_core_phase:"import",shared_core_sha256:$sha}
         + (if $run=="" then {} else {shared_core_producer_workspace_commit:$workspace,shared_core_producer_run_id:$run} end)' \
        "$work/artifacts/manifest.json" > "$work/manifest.next" || return
    mv "$work/manifest.next" "$work/artifacts/manifest.json"
}

public_core_pack() {
    local job=$1
    [[ $(id -u) == 0 && -s $job/rootfs.tar && -d $job/original-fedora && ! -e $job/core.tar.zst ]] || return 1
    jq -e '.desktop=="core" and .shared_core_phase=="export" and .image_built==false and
        .rpm_transaction_validated==true and .credentials_included==false' "$job/artifacts/manifest.json" >/dev/null || return
    # shellcheck source=languages.sh
    # shellcheck disable=SC1091
    source "$(dirname -- "${BASH_SOURCE[0]}")/languages.sh"
    public_language_receipt "$job/artifacts/language-audit.json" || return
    (
        cd "$job" || exit
        cp artifacts/installed-rpms.tsv artifacts/core-installed-rpms.tsv
        public_core_desktop_free artifacts/core-installed-rpms.tsv || exit
        find request.json rootfs.tar fedora-inputs.tsv original-fedora artifacts/kernel artifacts/tools \
            artifacts/manifest.json artifacts/language-audit.json artifacts/core-installed-rpms.tsv artifacts/boot.img artifacts/boot-linux.img artifacts/boot-userdata.img \
            -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > core-SHA256SUMS
        tar --create --format=posix --numeric-owner --sort=name -I 'zstd -T2 -3' -f core.tar.zst \
            core-SHA256SUMS request.json rootfs.tar fedora-inputs.tsv original-fedora \
            artifacts/kernel artifacts/tools artifacts/manifest.json artifacts/language-audit.json artifacts/core-installed-rpms.tsv artifacts/boot.img artifacts/boot-linux.img artifacts/boot-userdata.img
    )
}
