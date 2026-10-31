#!/usr/bin/env bash
# The assembly repository may be frozen; the delivered root uses its public channel.
public_root_repository() {
    local output=$1 project=$2 release=$3 mode=${4:-public} baseurl
    case $project in uke-linux|uke-linux-test|uke-linux-unstable) ;; *) return 1;; esac
    case $release in 44|45|rawhide) ;; *) return 1;; esac
    [[ $project != uke-linux-unstable || $release == rawhide ]] || return 1
    case $mode in
        public) baseurl=https://download.copr.fedorainfracloud.org/results/mcc45tr/$project/fedora-$release-\$basearch/;;
        copr-frozen)
            [[ $project == uke-linux-unstable && $release == rawhide ]] || return 1
            baseurl=file:///inputs/target/rpms/uke;;
        *) return 1;;
    esac
    cat > "$output" <<REPO
[uke-selected]
name=Uke $project
baseurl=$baseurl
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-uke-selected
skip_if_unavailable=False
priority=40
includepkgs=uke-*,senemos-uke-linux-kernel-*
REPO
}
