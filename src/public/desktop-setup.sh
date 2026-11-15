#!/usr/bin/env bash
# Runs in the disposable assembly worker, targeting its new root only.
public_desktop_setup() {
    local root=$1 desktop=$2 receipt=$3 unit
    [[ $(id -u) == 0 && -d $root && ! -L $root && $root != / ]] || return 1
    case $desktop in
        core)
            systemctl --root="$root" set-default multi-user.target
            printf '{"account_setup":"deferred-to-desktop","credentials_included":false}\n' > "$receipt"
            return;;
        kde|plasma-mobile|nextkde)
            rpm --root "$root" -q plasma-setup plasma-login-manager kde-settings-plasmalogin kio-admin >/dev/null
            rpm --root "$root" -ql kio-admin > /job/artifacts/kio-admin-files.txt
            grep -E '/kio/.*admin.*\.so$' /job/artifacts/kio-admin-files.txt
            grep -E '/polkit-1/actions/.*kio.*admin.*\.policy$' /job/artifacts/kio-admin-files.txt
            grep -E '/libexec/.*kio.*admin' /job/artifacts/kio-admin-files.txt
            rpm --root "$root" -q polkit >/dev/null
            [[ ! -e $root/etc/plasma-setup-done ]]
            chroot "$root" /usr/bin/kwriteconfig6 --file /etc/xdg/plasmasetuprc --group Accounts --key UserGroups wheel
            chroot "$root" /usr/bin/systemd-sysusers /usr/lib/sysusers.d/plasma-setup-sysuser.conf
            systemctl --root="$root" enable plasma-setup.service plasmalogin.service
            if [[ $desktop == plasma-mobile ]]; then
                rpm --root "$root" -q plasma-mobile plasma-settings plasma-keyboard plasma-lookandfeel-fedora-mobile >/dev/null
                [[ -f $root/usr/share/wayland-sessions/plasma-mobile.desktop ]]
                [[ -f $root/usr/share/plasma/look-and-feel/org.fedoraproject.fedora.mobile/metadata.json ]]
                chroot "$root" /usr/bin/kwriteconfig6 --file /etc/xdg/kdeglobals --group KDE --key LookAndFeelPackage org.fedoraproject.fedora.mobile
                chroot "$root" /usr/bin/kwriteconfig6 --file /etc/plasmalogin.conf --group Greeter --key PreselectedSession /usr/share/wayland-sessions/plasma-mobile.desktop
            fi
            if [[ $desktop == nextkde ]]; then
                rpm --root "$root" -q nextkde quickshell >/dev/null
                for unit in kos-platform kos-data kos-shell; do
                    [[ -f $root/usr/lib/systemd/user/$unit.service ]]
                done
                mkdir -p "$root/etc/xdg/autostart" "$root/usr/local/libexec"
                install -m755 /builder/src/public/nextkde-session.sh "$root/usr/local/libexec/uke-nextkde-session"
                cat > "$root/etc/xdg/autostart/uke-nextkde.desktop" <<'AUTOSTART'
[Desktop Entry]
Type=Application
Name=NextKDE session services
Exec=/usr/local/libexec/uke-nextkde-session
OnlyShowIn=KDE;
X-KDE-autostart-phase=2
AUTOSTART
            fi
            printf '{"account_setup":"plasma-setup","credentials_included":false}\n' > "$receipt";;
        gnome)
            rpm --root "$root" -q gdm gnome-initial-setup gnome-shell >/dev/null
            mkdir -p "$root/etc/gdm"
            printf '[daemon]\nInitialSetupEnable=true\n' > "$root/etc/gdm/custom.conf"
            systemctl --root="$root" enable gdm.service
            printf '{"account_setup":"gnome-initial-setup","credentials_included":false}\n' > "$receipt";;
        cutefish)
            rpm --root "$root" -q cutefish-desktop cutefish-dm uke-cutefish-firstboot uke-cutefish-session-config >/dev/null
            [[ -f $root/usr/share/wayland-sessions/cutefish-wayland.desktop && -x $root/usr/bin/cutefish-wayland-session ]]
            [[ ! -e $root/var/lib/uke-cutefish-firstboot/done && ! -e $root/var/lib/uke-cutefish-firstboot/pending ]]
            chroot "$root" /usr/bin/systemd-sysusers /usr/lib/sysusers.d/cutefish-greeter.conf /usr/lib/sysusers.d/uke-cutefish-firstboot.conf
            chroot "$root" /usr/bin/systemd-tmpfiles --create /usr/lib/tmpfiles.d/uke-cutefish-firstboot.conf
            systemctl --root="$root" enable cutefish-dm.service
            [[ $(readlink "$root/etc/systemd/system/display-manager.service") == /usr/lib/systemd/system/cutefish-dm.service ]]
            [[ -x $root/usr/libexec/uke-cutefish-firstboot && -x $root/usr/libexec/uke-cutefish-firstboot-backend ]]
            # Execute the packaged production validator on the native ARM64 worker.
            chroot "$root" /usr/libexec/uke-cutefish-firstboot-backend --self-test
            printf '{"account_setup":"uke-cutefish-firstboot","credentials_included":false,"firstboot_backend_input_tests":true,"graphical_login_hardware_tested":false,"firstboot_hardware_tested":false,"autologin_enabled":false,"remote_password_login":false,"passwordless_sudo":false,"validation_status":"build-verified-hardware-untested"}\n' > "$receipt";;
        *) return 1;;
    esac
    # Setup and greeter users are system accounts. Every image starts without a human account.
    awk -F: '$3>=1000 && $3<65534 {exit 1}' "$root/etc/passwd"
    systemctl --root="$root" set-default graphical.target
}
