#!/usr/bin/env bash
# COPR source-worker metadata audit. Never download or install target RPMs.
set -Eeuo pipefail
[[ $# == 3 && -n ${COPR_RESULTDIR:-} && -d $1 && -d $3 && ! -e $2 && ! -L $2 ]]
recipe=$(realpath "$1") output=$(realpath -m "$2") cache=$(realpath "$3")
export LANG=C LC_ALL=C
# shellcheck source=../src/public/root-packages.sh
# shellcheck disable=SC1091
source "$recipe/src/public/root-packages.sh"
kernel=$(jq -er .kernel_rpm "$recipe/configs/copr-image-closure.json")
[[ $kernel =~ ^7[.]3[.][0-9]+-[1-9][0-9]*[.]fc46$ ]]
family=$(jq -er .kernel.profiles.normal.family "$recipe/configs/public-build.json")
[[ $family == senemos-uke-linux-kernel-mainline ]]
excluded=$(public_root_exclusions normal)
mkdir -p "$output"
find "$cache" -type f -name '*.rpm' -printf '%P\t%s\n' | LC_ALL=C sort > "$output/rpms-before.tsv"
[[ ! -s $output/rpms-before.tsv ]]
packages=()
for desktop in kde gnome; do
    for login_shell in bash fish zsh; do
        for partition in linux userdata; do
            case_dir=$output/$desktop-$login_shell-$partition
            solver=$case_dir/root
            mkdir -p "$solver/usr/lib/sysimage/rpm"
            rpm --dbpath "$solver/usr/lib/sysimage/rpm" --initdb
            public_root_packages packages rawhide unstable "$desktop" "$login_shell"
            for component in '' -core -modules -dtbs -boot; do
                packages+=("$family$component-$kernel.aarch64")
            done
            [[ $partition != userdata ]] || packages+=("$family-singleboot-$kernel.aarch64")
            printf '%s\n' "${packages[@]}" > "$case_dir/requested-packages.txt"
            status=0
            (cd "$case_dir" || exit
                dnf5 --forcearch=aarch64 --releasever=rawhide --installroot="$solver" \
                    --disable-repo='*' \
                    --repofrompath=copr-public-fedora,https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Everything/aarch64/os/ \
                    --setopt=copr-public-fedora.baseurl= \
                    --setopt='copr-public-fedora.metalink=https://mirrors.fedoraproject.org/metalink?repo=rawhide&arch=aarch64&protocol=https' \
                    --repofrompath=uke-selected,https://download.copr.fedorainfracloud.org/results/mcc45tr/uke-linux-unstable/fedora-rawhide-aarch64/ \
                    --enable-repo=copr-public-fedora --enable-repo=uke-selected \
                    --setopt=cachedir="$cache" --setopt=install_weak_deps=False \
                    --setopt=gpgcheck=True --setopt=installonly_limit=0 \
                    --setopt=copr-public-fedora.metadata_expire=-1 --setopt=uke-selected.metadata_expire=-1 \
                    --setopt=uke-selected.priority=40 \
                    --setopt=uke-selected.includepkgs='uke-*,senemos-uke-linux-kernel-*' \
                    --setopt=optional_metadata_types=filelists --setopt=tsflags=nodocs \
                    --setopt="excludepkgs=$excluded" --debugsolver --assumeno install "${packages[@]}"
            ) > "$case_dir/dnf.log" 2>&1 || status=$?
            if [[ $status != 1 ]] || ! grep -Fxq 'Operation aborted by the user.' "$case_dir/dnf.log"; then
                cat "$case_dir/dnf.log" >&2
                exit 1
            fi
            mapfile -t results < <(find "$case_dir/debugdata" -type f -name solver.result)
            [[ ${#results[@]} == 1 && -s ${results[0]} && ! -L ${results[0]} ]]
            cp "${results[0]}" "$case_dir/solver.result"
            awk '$1=="install" || $1=="multiinstall" {if(NF!=2) bad=1; print $2; next}
                $1=="problem" || $1 ~ /^(erase|reinstall|downgrade|change|upgrade|obsolete|multireinstall)$/ {bad=1}
                END {exit bad}' "$case_dir/solver.result" | LC_ALL=C sort > "$case_dir/resolved-packages.txt"
            [[ -s $case_dir/resolved-packages.txt ]]
            for component in '' -core -modules -dtbs -boot; do
                grep -Fxq "$family$component-$kernel.aarch64@uke-selected" "$case_dir/resolved-packages.txt"
            done
            if [[ $partition == userdata ]]; then
                grep -Fxq "$family-singleboot-$kernel.aarch64@uke-selected" "$case_dir/resolved-packages.txt"
            fi
            if grep -E '^uke-(local-touch-data|video-firmware-local)-' "$case_dir/resolved-packages.txt"; then exit 1; fi
            rpm --dbpath "$solver/usr/lib/sysimage/rpm" -qa > "$case_dir/installed.txt"
            [[ ! -s $case_dir/installed.txt ]]
            find "$cache" -type f -name '*.rpm' -printf '%P\t%s\n' | LC_ALL=C sort > "$case_dir/rpms-after.tsv"
            cmp "$output/rpms-before.tsv" "$case_dir/rpms-after.tsv"
            jq -n --arg desktop "$desktop" --arg login_shell "$login_shell" --arg partition "$partition" \
                --arg kernel "$kernel" --argjson count "$(wc -l < "$case_dir/resolved-packages.txt")" \
                '{desktop:$desktop,default_shell:$login_shell,partition:$partition,kernel_rpm:$kernel,
                  resolved_packages:$count,goal_resolved:true,metadata_only:true,rpm_downloaded:false,
                  installed:false,rpm_signatures_verified:false,full_os_composition:false,hardware_tested:false}' > "$case_dir/report.json"
            find "$solver" "$case_dir/debugdata" -depth -delete
            printf 'UKE_COPR_FULL_ROOT_GOAL desktop=%s shell=%s partition=%s kernel=%s metadata_only=true installed=false full_os_composition=false hardware_tested=false\n' \
                "$desktop" "$login_shell" "$partition" "$kernel"
        done
    done
done
jq -s 'length==12 and all(.[];.goal_resolved and .metadata_only and
    (.rpm_downloaded==false) and (.installed==false) and (.rpm_signatures_verified==false) and
    (.full_os_composition==false) and (.hardware_tested==false))' "$output/"*/report.json
