# Fedora for POCO Pad X1 and Xiaomi Pad 7

Fedora Rawhide AArch64 build, package and update infrastructure for POCO Pad X1 and Xiaomi Pad 7 (`uke`, SM7675). The first delivery is a verified Senemos Linux 7.2.9 kernel package set. A console-first system image needs independently qualified firmware and Uke boot profiles.

[Uke Linux](https://github.com/MCC45TR/uke-linux) · [Build architecture](docs/ARCHITECTURE.md) · [Test COPR](https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/) · [Releases](https://github.com/MCC45TR/uke-fedora-builder/releases)

## Outputs

- `senemos-uke-linux-kernel-mainline` RPMs with core, modules and DTB subpackages,
  plus the complete source RPM. Development headers are a later milestone.
- Matching ARM64 Image, independent Uke DTB, modules, config and build manifest.
- Module ABI, dependency closure, checksums and package lifecycle reports.

A local Rawhide AArch64 Core filesystem candidate has passed composition checks.
Firmware-specific boot and physical rollback validation remain open.

The first user experience is a Fedora Core development console. Desktop, graphics and media packages follow working kernel and boot paths. The target package closure is checked so no Python script or runtime runs on the tablet.

## Local kernel builds

The kernel repository owns the standalone host entry `senemos.sh`. Its first
implemented target is Fedora Rawhide AArch64 using the reviewed Linux 7.2.9
Uke adaptation. Run `./senemos.sh --build 7.2.9 --distro=fedora --test` from that
checkout, or `./senemos-uke-kernel/senemos.sh` from the workspace.
See [build rules and testing](docs/BUILDING.md) for prerequisites,
offline caching, recovery-build priority and the exact limits of compile/package
evidence. Other distribution targets have explicit planned profiles.

## Downloads

The [development COPR](https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/)
now publishes kernel packages and DNF-managed recovery image data. Kernel
job [11081958](https://copr.fedorainfracloud.org/coprs/build/11081958) and recovery
SCM job [11074373](https://copr.fedorainfracloud.org/coprs/build/11074373) succeeded.
The [package hub](https://github.com/MCC45TR/uke-linux-docs/blob/main/docs/PACKAGE-HUB.md)
maps the additional initial repositories and their readiness gates.
There is no bootable Fedora Uke system image or physical acceptance claim.

Twelve source families have automatic builds, including five non-KDE native
dependency families. KDE application derivatives were withdrawn after the
owner prohibited cloning, forking or rebuilding them. Use original distribution
applications. Their Python payloads currently block complete KDE admission.
Desktop release 3 carries policy metadata only. The GNU C++ source correction
retained all 6,100 original exports and passed a native AArch64 C++ smoke test.
The [52-input console selection](reports/CONSOLE-RAWHIDE-2026-10-05.json) passed
signatures, complete payloads, offline fresh installation, actual release-2 to
release-3 upgrade, inherited-root audits and removal. The historical 603-input
desktop transaction remains rejected; no graphical session or device boot ran.

See [local kernel acceptance](reports/KERNEL-7.2.9-RAWHIDE-2026-10-04.json),
[host-family bootstrap tests](reports/HOST-BOOTSTRAP-2026-10-04.json),
[COPR source automation](reports/COPR-AUTOMATION-2026-10-04.json) and
[recovery delivery](reports/RECOVERY-RAWHIDE-2026-10-04.json).

See the [100-step platform plan](https://github.com/MCC45TR/uke-linux-docs/blob/main/PLAN.md), [hardware status](https://github.com/MCC45TR/uke-linux-docs/blob/main/DEVICE-STATUS.md) and [contribution rules](AGENTS.md). Firmware redistribution and licenses are handled separately from kernel source packages.

## Core filesystem construction

Run `./ukelinux.sh --build core --distro=fedora --test` from the Uke workspace.
The [image guide](docs/IMAGES.md) describes the immutable base, 72 signed inputs,
logical EXT4/ESP outputs, Core-only VT2/ESP32 debug profile and device release
gates. [Signed boot/CDC package checks](reports/ESP32-CORE-PACKAGES-2026-10-05.json)
cover native binaries, actual upgrades and removal; physical enumeration is open.

The [first local Core candidate](reports/CORE-FILESYSTEM-2026-10-05.json) passed
full EXT4/ESP/UKI and root/initramfs checks. Tablet boot, UEFI, actual geometry
and USB/UFS/ESP32 acceptance remain open; image release assets are unpublished.

[First-TTY preparation](reports/FIRST-TTY-PREPARATION-2026-10-06.json) records
dynamic fastboot-name image inputs, signed boot release 4 lifecycle checks and
an actual gated VT2/CDC initramfs with ARM64 helper/library and payload audits.
Its pre-root shell does not wait for the internal EXT4 mount. The Uke firmware,
USB/UFS board chain and physical first console are still open gates.

[First-console system checks](reports/FIRST-CONSOLE-SYSTEM-2026-10-06.json)
qualify signed native kernel release `7.2.9-1.4.fc46`, its 1,146 modules and a
newly assembled initramfs. The actual Image and initramfs booted in QEMU virt;
a VM USB keyboard entered a command in the gated VT2 shell. A foreign DT
skipped the shell without restarting it. The synthetic identity fixture is
only an identity/service test: it does not emulate Uke's USB, UFS or firmware.
The image recipe now pins these native COPR inputs. Full composition and the
physical ESP32 host path remain separate gates.

Host-only checks are `bash tests/native-kernel-lifecycle.sh BUILDER OUTPUT`
inside the recorded disposable ARM64 console image and
`bash tests/qemu-first-console.sh KERNEL INITRD_ROOT OUTPUT BUILDER` inside
the recorded native QEMU image. Freeze the test script before launching it;
keep writable output separate from read-only source and payload mounts.
