#!/usr/bin/env bash
# Narrow, signature-checked desktop COPR repositories. Never replace Fedora Qt/KWin.
public_desktop_repository() {
    local desktop=$1 destination=$2 keydir=$3 project fingerprint allowed key
    case $desktop in
        nextkde) project=kdenext; fingerprint=0C7AFEE52E73FCC565CFFD8EDB4A656550EA0312; allowed='nextkde,quickshell';;
        cutefish) project=cutefish; fingerprint=8FBA3624A1628EB0AE35FD3A6525D78F085B03D6; allowed=cutefish-desktop;;
        core|kde|gnome|plasma-mobile) return 0;;
        *) return 1;;
    esac
    mkdir -p "$keydir"
    key=$keydir/RPM-GPG-KEY-uke-$project
    curl --proto '=https' --tlsv1.2 -fL --retry 3 \
        "https://download.copr.fedorainfracloud.org/results/mcc45tr/$project/pubkey.gpg" -o "$key.part" || return
    [[ $(gpg --show-keys --with-colons "$key.part" | awk -F: '$1=="fpr" {print $10;exit}') == "$fingerprint" ]] || return 1
    mv "$key.part" "$key"
    cat > "$destination" <<REPO
[uke-desktop]
name=Uke $project desktop
baseurl=https://download.copr.fedorainfracloud.org/results/mcc45tr/$project/fedora-rawhide-\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file://$key
skip_if_unavailable=False
includepkgs=$allowed
REPO
}
