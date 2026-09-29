# Fedora for POCO Pad X1 and Xiaomi Pad 7

Reproducible Fedora Rawhide AArch64 packages and system images for POCO Pad X1 and Xiaomi Pad 7 (`uke`, SM7675). This builder connects the Senemos mainline kernel, device firmware and model-specific Uke boot profiles to a console-first Fedora system.

[Uke Linux](https://github.com/MCC45TR/uke-linux) · [Build architecture](docs/ARCHITECTURE.md) · [Test COPR](https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/) · [Releases](https://github.com/MCC45TR/uke-fedora-builder/releases)

## Outputs

- `senemos-uke-kernel-mainline` RPMs with core, modules and development subpackages.
- A pinned Rawhide AArch64 root filesystem and package manifest.
- Boot artifacts matched to a kernel, device tree and firmware profile.
- Reproducibility, image-size, module-ABI, package-solver and rollback reports.

The first user experience is a Fedora console. Desktop, graphics and media packages follow working kernel and boot paths. The target package closure is checked so no Python script or runtime runs on the tablet.

## Downloads

**No packages or images have been published.** The `uke-linux-test` COPR project currently has no builds. When development packages exist, each build will provide source revisions, checksums, supported firmware/SKU scope and validation results. Package success alone does not establish tablet boot or hardware support.

See the [100-step platform plan](https://github.com/MCC45TR/uke-linux/blob/main/PLAN.md), [hardware status](https://github.com/MCC45TR/uke-linux/blob/main/DEVICE-STATUS.md) and [contribution rules](AGENTS.md). Firmware redistribution and licenses are handled separately from kernel source packages.
