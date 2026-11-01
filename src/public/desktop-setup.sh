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
            rpm --root "$root" -q plasma-setup plasma-login-manager kde-settings-plasmalogin >/dev/null
            [[ ! -e $root/etc/plasma-setup-done ]]
            chroot "$root" /usr/bin/kwriteconfig6 --file /etc/xdg/plasmasetuprc --group Accounts --key UserGroups wheel
            chroot "$root" /usr/bin/systemd-sysusers /usr/lib/sysusers.d/plasma-setup-sysuser.conf
            systemctl --root="$root" enable plasma-setup.service plasmalogin.service
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
            rpm --root "$root" -q gdm cutefish-desktop >/dev/null
            [[ -f $root/usr/share/wayland-sessions/cutefish-wayland.desktop && -x $root/usr/bin/cutefish-wayland-session ]]
            # GDM supports PAM_NEW_AUTHTOK_REQD and a multi-prompt password
            # change conversation. Do not use SDDM for this expired test account.
            chroot "$root" /usr/sbin/useradd --create-home --groups wheel senemos
            printf 'senemos:fedora\n' | chroot "$root" /usr/sbin/chpasswd
            chroot "$root" /usr/bin/chage -d 0 senemos
            # shellcheck source=gdm-password-probe.sh
            # shellcheck disable=SC1091
            source /builder/src/public/gdm-password-probe.sh
            public_gdm_password_probe "$root"
            mkdir -p "$root/etc/gdm" "$root/var/lib/AccountsService/users" "$root/etc/ssh/sshd_config.d"
            printf '[daemon]\nInitialSetupEnable=false\nAutomaticLoginEnable=false\nTimedLoginEnable=false\n' > "$root/etc/gdm/custom.conf"
            printf '[User]\nSession=cutefish-wayland\nXSession=cutefish-wayland\nSystemAccount=false\n' > "$root/var/lib/AccountsService/users/senemos"
            chmod 600 "$root/var/lib/AccountsService/users/senemos"
            printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' > "$root/etc/ssh/sshd_config.d/00-uke-test-image.conf"
            # Fedora's normal wheel policy asks for the new password; add no sudo rule.
            systemctl --root="$root" enable gdm.service
            awk -F: '$1=="senemos" {if ($3!=0 || $2=="" || $2~/^[!*]/) exit 1; found=1} END {if(!found)exit 1}' "$root/etc/shadow"
            printf '{"account_setup":"gdm-expired-public-test-account","credentials_included":true,"public_test_account":"senemos","password_change_required":true,"password_change_backend_tested":true,"graphical_login_hardware_tested":false,"autologin_enabled":false,"remote_password_login":false,"passwordless_sudo":false}\n' > "$receipt";;
        *) return 1;;
    esac
    if [[ $desktop != cutefish ]]; then
        # Account setup users are system accounts. Never precreate a normal user.
        awk -F: '$3>=1000 && $3<65534 {exit 1}' "$root/etc/passwd"
    fi
    systemctl --root="$root" set-default graphical.target
}
