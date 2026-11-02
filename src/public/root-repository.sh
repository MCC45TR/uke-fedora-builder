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
    # Deliver the reviewed kernel-policy update without giving Fedora-named
    # packages the higher priority reserved for Uke packages. Frozen assembly
    # inputs retain their original, explicitly resolved repository selection.
    if [[ $project == uke-linux-unstable && $mode == public ]]; then
        cat >> "$output" <<REPO

[uke-policy]
name=Uke kernel policy compatibility
baseurl=$baseurl
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-uke-selected
skip_if_unavailable=False
priority=99
includepkgs=selinux-policy,selinux-policy-targeted
REPO
    fi
}

# Keep the default vendor restriction and permit only the named policy family
# to move between the selected COPR vendor and the original Fedora vendor.
public_root_vendor_policy() {
    local output=$1 project=$2
    case $project in
        uke-linux-unstable) ;;
        uke-linux|uke-linux-test) return 0;;
        *) return 1;;
    esac
    cat > "$output" <<'POLICY'
version = '1.1'

[[equivalent_vendors]]
vendor = 'Fedora Project'

[[equivalent_vendors]]
vendor = 'Fedora Copr - user mcc45tr'

[[outgoing_packages]]
filters = [
    { filter = 'name', value = 'selinux-policy' },
    { filter = 'source_name', value = 'selinux-policy' }
]

[[outgoing_packages]]
filters = [
    { filter = 'name', value = 'selinux-policy-targeted' },
    { filter = 'source_name', value = 'selinux-policy' }
]

[[incoming_packages]]
filters = [
    { filter = 'name', value = 'selinux-policy' },
    { filter = 'source_name', value = 'selinux-policy' }
]

[[incoming_packages]]
filters = [
    { filter = 'name', value = 'selinux-policy-targeted' },
    { filter = 'source_name', value = 'selinux-policy' }
]
POLICY
}
