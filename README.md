# Fedora for POCO Pad X1 and Xiaomi Pad 7

Fedora Rawhide AArch64 build, package and update infrastructure for POCO Pad X1 and Xiaomi Pad 7 (`uke`, SM7675). The first delivery is a verified Senemos Linux 7.2.9 kernel package set. A console-first system image needs independently qualified firmware and Uke boot profiles.

[Uke Linux](https://github.com/MCC45TR/uke-linux) · [Build architecture](docs/ARCHITECTURE.md) · [Test COPR](https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/) · [Releases](https://github.com/MCC45TR/uke-fedora-builder/releases)

## Outputs

- `senemos-uke-linux-kernel-mainline` RPMs with core, modules and DTB subpackages,
  plus the complete source RPM. Development headers are a later milestone.
- Matching ARM64 Image, independent Uke DTB, modules, config and build manifest.
- Module ABI, dependency closure, checksums and package lifecycle reports.

A Rawhide AArch64 root filesystem, firmware-specific boot artifacts and physical
rollback validation are later milestones.

The first user experience is a Fedora console. Desktop, graphics and media packages follow working kernel and boot paths. The target package closure is checked so no Python script or runtime runs on the tablet.

## Local kernel builds

The workspace root contains the single host entry `senemeos.sh`. Its first
implemented target is Fedora Rawhide AArch64 using the reviewed Linux 7.2.9
Uke adaptation. Run `./senemeos.sh --build 7.2.9 --distro=fedora --test` from the
workspace root. See [build rules and testing](docs/BUILDING.md) for prerequisites,
offline caching, recovery-build priority and the exact limits of compile/package
evidence. Other distribution targets have explicit planned profiles.

## Downloads

The [development COPR](https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/)
now publishes kernel packages and DNF-managed recovery image data. First kernel
job [11074297](https://copr.fedorainfracloud.org/coprs/build/11074297) and recovery
SCM job [11074373](https://copr.fedorainfracloud.org/coprs/build/11074373) succeeded.
The [package hub](https://github.com/MCC45TR/uke-linux/blob/main/docs/PACKAGE-HUB.md)
maps the additional initial repositories and their readiness gates.
There is no bootable Fedora Uke system image or physical acceptance claim.

See [local kernel acceptance](reports/KERNEL-7.2.9-RAWHIDE-2026-10-04.json),
[host-family bootstrap tests](reports/HOST-BOOTSTRAP-2026-10-04.json),
[COPR source automation](reports/COPR-AUTOMATION-2026-10-04.json) and
[recovery delivery](reports/RECOVERY-RAWHIDE-2026-10-04.json).

See the [100-step platform plan](https://github.com/MCC45TR/uke-linux/blob/main/PLAN.md), [hardware status](https://github.com/MCC45TR/uke-linux/blob/main/DEVICE-STATUS.md) and [contribution rules](AGENTS.md). Firmware redistribution and licenses are handled separately from kernel source packages.
