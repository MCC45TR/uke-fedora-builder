#!/usr/bin/env bash
# One package policy for actual root installation and COPR input resolution.
public_root_packages() {
    local -n selection=$1
    local release=$2 channel=$3 desktop=$4 login_shell=$5 package
    case $release in 44|45|rawhide) ;; *) return 1;; esac
    case $channel in stable|testing|unstable) ;; *) return 1;; esac
    case $desktop in kde|gnome) ;; *) return 1;; esac
    case $login_shell in bash|fish|zsh) ;; *) return 1;; esac
    selection=(fedora-release fedora-repos bash "$login_shell" coreutils dnf5 dnf5-plugins glibc-all-langpacks
        systemd systemd-udev systemd-pam NetworkManager NetworkManager-wifi bluez chrony
        firewalld openssh-server sudo shadow-utils selinux-policy-targeted policycoreutils
        e2fsprogs f2fs-tools btrfs-progs xfsprogs util-linux kbd less nano fastfetch
        pipewire pipewire-pulseaudio wireplumber
        uke-core uke-hw uke-power uke-sensors uke-additional uke-firmware
        uke-touchscreen uke-ssc-fileservice uke-adaptive-display uke-battery-observer
        uke-charge-control uke-offline-charge)
    [[ $release != rawhide ]] || selection+=(fedora-repos-rawhide)
    if [[ $channel == unstable ]]; then
        local individual=()
        for package in "${selection[@]}"; do
            case $package in
                uke-core|uke-hw|uke-power|uke-sensors|uke-additional) ;;
                pipewire) individual+=(uke-pipewire);;
                pipewire-pulseaudio) individual+=(uke-pipewire-pulseaudio);;
                *) individual+=("$package");;
            esac
        done
        selection=("${individual[@]}" uke-core-meta)
    fi
    if [[ $desktop == kde ]]; then
        selection+=(uke-kde-plasma-meta plasma-setup kde-settings-plasmalogin)
    else
        selection+=(gnome-shell gnome-session-wayland-session gdm gnome-initial-setup
            gnome-control-center gnome-software gnome-console nautilus)
    fi
}

public_root_exclusions() {
    local profile=$1 component
    case $profile in normal|el2-require) ;; *) return 1;; esac
    local excluded='kernel,kernel-core,kernel-modules*,*-debuginfo,*-debugsource,uke-local-touch-data,uke-video-firmware-local,senemos-uke-linux-kernel-mainline-unstable*'
    if [[ $profile == normal ]]; then
        excluded+=',senemos-uke-linux-kernel-mainline-kvm*'
    else
        for component in '' -core -modules -dtbs -boot -singleboot; do
            excluded+=",senemos-uke-linux-kernel-mainline$component"
        done
    fi
    printf '%s\n' "$excluded"
}
