# Plasma first-run image preparation

15 October 2026. Offline Fedora Rawhide AArch64 composition; this recipe has
not passed a graphical first-run or tablet boot test. It does not change the
currently published Alpha 1 download.

The package selection in `configs/images/plasma-rawhide.json` references the
original Fedora applications selected for the Nabu desktop, excluding Nabu
hardware packages. It adds original `plasma-setup`, `dnf5-plugins` and
`power-profiles-daemon`. Chromium, Discover with its PackageKit backend,
Dolphin with `kio-admin`, KWrite, Okular, Gwenview, Spectacle, KScreen, KDE
Connect, the virtual keyboard and system settings remain distribution packages.
No KDE application is cloned or rebuilt.

In a disposable AArch64 composer, install the selected signed RPMs into an
offline Alpha root while retaining its matched Uke kernel and Mesa tuple.
Then run these host helpers with that root as the argument:

```sh
bash src/image/prepare-plasma-setup.sh OFFLINE_ROOT
bash src/image/prepare-copr.sh OFFLINE_ROOT
bash tests/plasma-setup-lifecycle.sh OFFLINE_ROOT
```

The first helper removes the generic Alpha account and its automatic login and
passwordless sudo rules. It refuses unexpected ordinary accounts. Root remains
locked. Original Plasma Setup creates the user's account; Fedora's passworded
`wheel` sudo policy applies. The composer explicitly sets `[Accounts] UserGroups=wheel`
in `/etc/xdg/plasmasetuprc` through the original KConfig tool, so the created
account receives administrative access. The reserved `plasma-setup` system account is only
for the setup wizard. The helper deliberately resets the first-run flag and is
for a fresh image, never an installed tablet filesystem.

The original setup service runs before SDDM when `/etc/plasma-setup-done` is
absent. Offline tests cover its boot utility and service condition, including a
retry before completion. They do not prove graphical account creation or
recovery from an account-creation error. Verify those paths in a disposable
guest before replacing the release image, including `id USER`, `visudo -c`
and `sudo -l -U USER` after account creation. The user must be in `wheel`
and the policy must permit password-authenticated administrative commands.

The existing development COPR is enabled with its pinned signing key and a
standard repository ID recognized by `dnf copr list`. Kernel packages remain
excluded: the existing COPR raw Image cannot replace a matched Android boot
image. The native boot updater requires separately versioned modules and a
complete validated boot bundle before a DNF transaction may activate it.

Before publication, repeat original-RPM byte admission, privacy, SELinux,
EXT4/sparse readback and matched boot/module checks. Remove caches, generated
keys, account backups and machine identity. Do not shrink the application
selection silently to meet a hosting limit. Each GitHub release asset must be
under 2 GiB; a larger direct system `.img` needs an agreed delivery method.
Public firmware provisioning and firmware-dependent hardware acceptance remain
separate. Installing a power manager does not establish working power profiles,
charging or suspend.
