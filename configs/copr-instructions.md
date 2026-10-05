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
./senemeos.sh --build 7.2.9 --distro=fedora --test
./senemeos.sh --build latest --distro=fedora
./senemeos.sh --help
```

`lastest` is a `latest` alias. Offline builds reuse verified caches and prepared
containers. The script installs missing official host prerequisites, limits
resources and queues behind active native/recovery work. Other target formats
and unreviewed stable versions fail explicitly. See the
[package/update hub](https://github.com/MCC45TR/uke-linux/blob/main/docs/PACKAGE-HUB.md)
for all component repositories and their readiness gates.

COPR/package, emulated userspace and physical tablet acceptance remain separate.

A signed, tested console selection is also available:

```sh
sudo dnf install uke-core-meta
sudo dnf upgrade uke-core-meta
```

Its release 2 refuses Python interpreter/ABI dependencies. Optional
`plymouth-uke` delivers theme data without activation. The native Material
Decoration RPM and Plasma meta packages are built; consult the current
[desktop acceptance record](https://github.com/MCC45TR/uke-fedora-builder/blob/main/reports/DESKTOP-RAWHIDE-2026-10-05.json)
before full desktop evaluation. The corrected selection requires six native
runtime capabilities. Never bypass the Python policy with nodeps or unsafe
solver overrides. A successful graphical dependency transaction still does not
establish a working Uke display/session.

`xiaomi-uke-firmware` is not admitted until file-level source/license/hash and
kernel-request gates pass. Initial hardware component repositories are listed
in the package catalog; they do not advertise unsupported binaries.
