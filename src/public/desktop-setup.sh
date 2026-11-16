#!/usr/bin/env bash
# Runs in the disposable assembly worker, targeting its new root only.
public_plasma_setup_cdc() {
    local root=$1 path unit marker uid mode
    [[ -d $root && ! -L $root && $root != / ]] || return 1
    root=$(realpath "$root") || return
    [[ $root != / && ! -e $root/etc/plasma-setup-done && ! -L $root/etc/plasma-setup-done ]] || return 1
    uid=$(id -u)
    # Reject an old Control package before changing the new image's policy.
    rpm --root "$root" -q --whatprovides 'uke-control(setup-cdc-v1) >= 1' >/dev/null || return
    [[ -x $root/usr/bin/uke-control && ! -L $root/usr/bin/uke-control ]] || return 1
    for unit in uke-control-setup-cdc.service uke-control-setup-console.service uke-control-setup-cdc-finish.service uke-control-setup-cdc-finish.path; do
        [[ -f $root/usr/lib/systemd/system/$unit && ! -L $root/usr/lib/systemd/system/$unit ]] || return 1
    done
    for path in usr/lib/udev/rules.d/91-uke-control-setup-cdc.rules usr/lib/systemd/system-preset/81-uke-control-setup-cdc.preset; do
        [[ -f $root/$path && ! -L $root/$path ]] || return 1
    done
    for path in etc etc/uke-control etc/systemd etc/systemd/system; do
        [[ ! -L $root/$path && ( ! -e $root/$path || -d $root/$path ) ]] || return 1
        if [[ -e $root/$path ]]; then
            [[ $(stat -c %u "$root/$path") == "$uid" ]] || return 1
            mode=$(stat -c %a "$root/$path")
            (( (8#$mode & 0022) == 0 )) || return 1
        fi
    done
    marker=$root/etc/uke-control/first-setup-cdc
    if [[ -e $marker || -L $marker ]]; then
        [[ -f $marker && ! -L $marker && $(stat -c %h "$marker") == 1 && $(stat -c %u "$marker") == "$uid" && $(stat -c %a "$marker") == 600 ]] || return 1
        printf 'v1\n' | cmp - "$marker" || return
    else
        mkdir -p "$root/etc/uke-control" || return
        (umask 077;set -o noclobber;printf 'v1\n' > "$marker") || return
    fi
    systemctl --root="$root" enable uke-control-setup-cdc.service uke-control-setup-cdc-finish.path || return
    for unit in uke-control-setup-cdc.service uke-control-setup-cdc-finish.path; do
        [[ $(systemctl --root="$root" is-enabled "$unit") == enabled ]] || return 1
    done
    # The saved CDC preference belongs to Control and is never written here.
    return 0
}

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
            public_plasma_setup_cdc "$root" || return
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
            printf '{"account_setup":"plasma-setup","credentials_included":false,"temporary_setup_cdc":true,"setup_cdc_commands":["help","status","logs","reboot bootloader"],"setup_cdc_saved_policy_changed":false,"setup_cdc_physical_boot_tested":false}\n' > "$receipt";;
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
