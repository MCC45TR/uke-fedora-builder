Enable this development repository on **Fedora Rawhide AArch64**:

```sh
sudo dnf copr enable mcc45tr/uke-linux-test
```

Install or update the Uke kernel package set:

```sh
sudo dnf install senemos-uke-linux-kernel-mainline
sudo dnf upgrade senemos-uke-linux-kernel-mainline
```

The meta package resolves the matching core, modules and DTBs. Files are under
`/usr/lib/modules/7.2.9-senemos-uke/`; module indexes are updated with POSIX
scriptlets. The source-lock manifest identifies upstream source, patches and
configs. No Android partition write or default boot selection occurs.

Install or update **recovery image delivery** separately:

```sh
sudo dnf install uke-orangefox-recovery
sudo dnf upgrade uke-orangefox-recovery
```

Delivered IMG/ZIP and manifest/source/license/checksum records are under
`/usr/share/senemos/recovery/uke/RPM_VERSION/`. The RPM has no scriptlets,
service, flashing operation or automatic ZIP installer. DNF updates files;
device evaluation is a separate, explicitly authorized procedure. The initial
`12.0~alpha1.20260930` images retain Global OS3.0.303.0.WOZMIXM scope. The stock
OS2 inventory does not prove compatibility. Read each installed lock/manifest
and the exact release's installation/rollback document before evaluation.

The repository signs RPMs with its COPR project key. Independently observed key
fingerprint: `DAFC3C5A881FB49C7167EE2D6F772E3D487BD13E`. Verify source RPMs,
package identities and build logs rather than treating a package label as
hardware support. Preserve stock early firmware and the recovery route.

For local signed-source builds:

```sh
git clone --recurse-submodules https://github.com/MCC45TR/uke-linux.git
cd uke-linux
./senemos-uke-kernel/senemos.sh --build 7.2.9 --distro=fedora --test
./senemos-uke-kernel/senemos.sh --build latest --distro=fedora
./senemos-uke-kernel/senemos.sh --help
```

`lastest` is a `latest` alias. Offline builds reuse verified caches and prepared
containers. The script installs missing official host prerequisites, limits
resources and queues behind active native/recovery work. Other target formats
and unreviewed stable versions fail explicitly. See the
[package/update hub](https://github.com/MCC45TR/uke-linux-docs/blob/main/docs/PACKAGE-HUB.md)
for all component repositories and their readiness gates.

COPR/package, emulated userspace and physical tablet acceptance remain separate.

Console selection packages are also available:

```sh
sudo dnf install --allow-vendor-change uke-core-meta
sudo dnf upgrade uke-core-meta
```

Release 2 passed bounded package lifecycle tests and refuses Python interpreter
dependencies. The complete inherited base failed its file audit on optional
libstdc++ Python GDB helpers. Release 3 requires the source-built GNU C++ runtime
and passed independent complete-console-root acceptance in isolated AArch64
userspace: all 52 selected inputs, offline fresh installation, actual earlier
console metadata upgrade and removal. The initial installation
explicitly allows the reviewed library's vendor to change from Fedora to this
signed COPR; ordinary interpreter conflicts and dependency checks remain active.
Consult the current
[test records](https://github.com/MCC45TR/uke-fedora-builder/tree/main/reports)
before treating a root as an admitted target image.

`uke-desktop-metas` release 3 carries readiness/policy data and installs no
graphical session. KDE applications must come from the original distribution;
cloning, forking or rebuilding them as Uke variants is prohibited. Derivative
Plasma/Dolphin COPR source records and binaries were withdrawn. Original KDE
Python payloads currently block complete graphical admission. Do not bypass
either requirement with nodeps, solver overrides or manual RPM-owned file
deletion. Optional `plymouth-uke` delivers theme data without activation. The
explicitly requested upstream Material Decoration plugin is independently
built and audited; rendering and Uke display/session validation remain open.

`xiaomi-uke-firmware` is not admitted until file-level source/license/hash and
kernel-request gates pass. Initial hardware component repositories are listed
in the package catalog; they do not advertise unsupported binaries.

The signed `uke-boot-integration` and `uke-esp32-cdc` packages are Core image
inputs and remain inactive after installation. The explicit development image
selects tablet USB host / ESP32 USB device roles, HID input on VT2 and one CDC
journal writer after switch-root. Native COPR 11080676 and signed release-1 to
release-3 lifecycle checks passed. The existing bridge firmware, enabled Uke
USB/UFS DT, UEFI handoff and physical boot remain unverified. See the
[Core composition guide](https://github.com/MCC45TR/uke-fedora-builder/blob/main/docs/IMAGES.md).
