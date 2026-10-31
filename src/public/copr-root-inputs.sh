#!/usr/bin/env bash
# Validate the complete frozen public root before starting a guest.
public_copr_root_request() {
    jq -e '.device=="uke" and .architecture=="aarch64" and .distribution=="fedora" and
        .fedora_release=="rawhide" and .channel=="unstable" and .target=="image" and
        .kernel_profile=="normal" and (.desktop=="kde" or .desktop=="gnome") and
        (.default_shell=="bash" or .default_shell=="fish" or .default_shell=="zsh") and
        ((.mode=="multiboot" and .partition=="linux") or (.mode=="singleboot" and .partition=="userdata")) and
        (.filesystem=="ext4" or .filesystem=="f2fs" or .filesystem=="btrfs" or .filesystem=="xfs") and
        (.size_mib|type=="number" and .>=8192 and .<=65536 and floor==.) and
        (.jobs|type=="number" and .>0 and floor==.) and
        (.kernel_commit|test("^[0-9a-f]{40}$")) and
        (.kernel_version|test("^[0-9]+[.][0-9]+([.][0-9]+)?$")) and
        (.kernel_rpm_request|test("^7[.]3[.][0-9]+-[1-9][0-9]*[.]fc46$")) and
        (.kernel_rpm_request|split("-")[0])==.kernel_version and
        (.firmware_review_sha256|test("^[0-9a-f]{64}$")) and
        (has("kernel_bundle")|not) and (has("touch_reference")|not)' "$1" >/dev/null
}

public_copr_root_inputs() {
    local recipe=$1 target=$2 scratch=$3 path role archive name fingerprint digest expected
    [[ -d $recipe && -d $target && ! -L $target && -d $scratch ]] || return 1
    for path in request.json manifest.json firmware-review.json uke-key.asc; do
        [[ -f $target/$path && ! -L $target/$path ]] || return 1
    done
    public_copr_root_request "$target/request.json" || return
    if ! jq -e '.schema_version==1 and .purpose=="full-public-uke-root" and .metadata_only==false and
        (.request_sha256|test("^[0-9a-f]{64}$")) and (.rpms|type=="array" and length>0) and
        (.root_nevras|type=="array" and length>0) and
        (.rpms|map(.nevra)|unique|length)==(.rpms|length)' "$target/manifest.json" >/dev/null; then
        echo 'Invalid frozen root schema or duplicate RPM NEVRA' >&2
        return 1
    fi
    [[ $(sha256sum "$target/request.json" | cut -d ' ' -f1) == "$(jq -er .request_sha256 "$target/manifest.json")" ]] || return 1
    [[ $(sha256sum "$target/firmware-review.json" | cut -d ' ' -f1) == "$(jq -er .firmware_review_sha256 "$target/request.json")" ]] || return 1
    if ! jq -e '.redistribution_review_complete==true and .firmware_blob_package_ready==true and
        .payload_files>0 and (.notice_mapped_files|length)==.payload_files and
        (.notice_mapped_files|unique_by([.target_root,.target_path])|length)==.payload_files and
        all(.notice_mapped_files[];(.sha256|test("^[0-9a-f]{64}$")) and (.content_ids|length)>0) and
        .missing_original_notice_paths==0 and .unmatched_named_notice_paths==0' "$target/firmware-review.json" >/dev/null; then
        echo 'Complete firmware redistribution evidence is required before public root inputs are accepted' >&2
        return 1
    fi
    fingerprint=$(gpg --batch --show-keys --with-colons "$target/uke-key.asc" | awk -F: '$1=="fpr" {print $10;exit}') || return
    [[ $fingerprint == 2204A661EA630A5303500085538797E72A3E4ECA ]] || return 1
    for path in rpms rpms/fedora rpms/uke; do
        [[ -d $target/$path && ! -L $target/$path ]] || return 1
    done
    mkdir "$scratch/target-fedora-keydb" "$scratch/target-uke-keydb" || return
    rpmkeys --dbpath "$scratch/target-fedora-keydb" --import "$recipe/configs/keys/fedora-46.asc" || return
    rpmkeys --dbpath "$scratch/target-uke-keydb" --import "$target/uke-key.asc" || return
    local entries=()
    jq -er '.rpms[]|[.path,.sha256,.nevra]|@tsv' "$target/manifest.json" > "$scratch/target-entries.tsv" || return
    mapfile -t entries < "$scratch/target-entries.tsv" || return
    (( ${#entries[@]} > 0 )) || return 1
    : > "$scratch/target-actual-rpms.tsv"
    for path in "${entries[@]}"; do
        IFS=$'\t' read -r path digest expected <<< "$path"
        [[ $path =~ ^rpms/(fedora|uke)/[A-Za-z0-9+_.:-]+[.]rpm$ && $digest =~ ^[0-9a-f]{64}$ && -f $target/$path && ! -L $target/$path ]] || return 1
        archive=$target/$path
        role=${path#rpms/}
        role=${role%%/*}
        [[ $(sha256sum "$archive" | cut -d ' ' -f1) == "$digest" && $(rpm -qp --qf '%{NEVRA}' "$archive") == "$expected" ]] || return 1
        name=$(rpm -qp --qf '%{NAME}' "$archive") || return
        case $name in uke-local-touch-data|uke-video-firmware-local) return 1;; esac
        case $(rpm -qp --qf '%{ARCH}' "$archive") in aarch64|noarch) ;; *) return 1;; esac
        if [[ $role == uke ]]; then
            case $name in uke-*|senemos-uke-*) ;; *) return 1;; esac
            case $(rpm -qp --qf '%{RELEASE}' "$archive") in *.fc46|*.fc46.*) ;; *) return 1;; esac
        else
            case $name in uke-*|senemos-uke-*) return 1;; esac
            [[ $(rpm -qp --qf '%{VENDOR}' "$archive") == 'Fedora Project' ]] || return 1
        fi
        rpmkeys --dbpath "$scratch/target-$role-keydb" --checksig "$archive" | grep -F 'signatures OK' || return
        printf '%s\t%s\n' "$path" "$expected" >> "$scratch/target-actual-rpms.tsv"
    done
    find "$target/rpms" -type f -name '*.rpm' -printf '%P\n' | LC_ALL=C sort > "$scratch/target-found-rpms.txt" || return
    cut -f1 "$scratch/target-actual-rpms.tsv" | sed 's|^rpms/||' | LC_ALL=C sort > "$scratch/target-declared-rpms.txt" || return
    cmp "$scratch/target-found-rpms.txt" "$scratch/target-declared-rpms.txt" || return
    [[ $(wc -l < "$scratch/target-declared-rpms.txt") == "$(sort -u "$scratch/target-declared-rpms.txt" | wc -l)" ]] || return 1
    jq -er '.root_nevras[]|select(type=="string" and test("^[A-Za-z0-9+_.:~^-]+$"))' "$target/manifest.json" | LC_ALL=C sort > "$scratch/target-root-nevras.txt" || return
    [[ $(wc -l < "$scratch/target-root-nevras.txt") == "$(jq '.root_nevras|length' "$target/manifest.json")" &&
       $(wc -l < "$scratch/target-root-nevras.txt") == "$(sort -u "$scratch/target-root-nevras.txt" | wc -l)" ]] || return 1
    cut -f2 "$scratch/target-actual-rpms.tsv" | LC_ALL=C sort > "$scratch/target-all-nevras.txt" || return
    comm -23 "$scratch/target-root-nevras.txt" "$scratch/target-all-nevras.txt" > "$scratch/target-missing-nevras.txt" || return
    [[ ! -s $scratch/target-missing-nevras.txt ]]
}
