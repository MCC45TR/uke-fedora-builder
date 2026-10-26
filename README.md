# Fedora image builder for Uke

Fedora Rawhide AArch64 image composition and validation for Xiaomi Pad 7 and POCO Pad X1 (`uke`, SM7675).

**Updated 26 October 2026.**

[Project status](https://github.com/MCC45TR/uke-linux) · [Public build guide](docs/PUBLIC-BUILD.md) · [Architecture](docs/ARCHITECTURE.md) · [Test COPR](https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/)

## Build and device status

| Scope | Recorded result | Limit |
|---|---|---|
| Public image/kernel entry point | Source, shell and entry-contract checks; explicit kernel source validation and cache identity | Advertised host/selection coverage does not establish a completed build for every combination. |
| KDE EXT4 singleboot composition | Host image, filesystem, sparse conversion, package and metadata checks completed on 24 October | That exact exported image has not completed tablet validation. |
| Native kernel producer | Checked-in source gate and executable build inputs participate in cache identity | Build/package results remain separate from boot and hardware support. |
| User-namespace worker preparation | Host concurrency, identity, AArch64 chroot/query and refusal fixtures | Full image and remote CI coverage of this development branch remain open. |
| Development tablet | Normal Fedora/KDE boots recorded through Linux 7.3.0-15 | This is a separate installed root, not acceptance of each public image. |

The completed 24 October composition is retained on [the KDE testing branch](https://github.com/MCC45TR/uke-fedora-builder/tree/work/kde-singleboot-testing-20261023). [Worker isolation work](https://github.com/MCC45TR/uke-fedora-builder/tree/work/public-worker-userns-20261024) has its own validation scope. Source publication does not create a new downloadable image.

As of 26 October, the main project's [24 October testing release](https://github.com/MCC45TR/uke-linux/releases/tag/prebuild-fedora-kde-singleboot-ext4-20261024-k7.2.12-22-testing) has no attached image assets. [Alpha 1](https://github.com/MCC45TR/uke-linux/releases/tag/fedora-rawhide-alpha-1) remains a historical experimental download. Check the live release page before following an old direct asset link.

## Build from the workspace

```sh
git clone --recurse-submodules https://github.com/MCC45TR/uke-linux.git
cd uke-linux
./ukelinux.sh
# Kernel workflow:
./ukelinux.sh --build kernel
```

The public workflow offers multiboot/singleboot, EXT4/F2FS/Btrfs/XFS, original KDE/GNOME and stable/testing/unstable channels. Output defaults to `out`. Read the [public build guide](docs/PUBLIC-BUILD.md) for supported hosts, prerequisite installation consent, exact source selection, output checks and manual installation.

Older `core`, `boot-pair` and debug profiles retain their dated contracts. Inspect `--help` for the selected route rather than combining instructions from different image generations. The stock-bootloader route and experimental UEFI outputs are separate.

## Image policy

- Keep the boot image, root selector, device tree and modules matched.
- Preserve stock early firmware, Android/recovery access and one verified rollback.
- Use only the intended device's admitted local firmware/calibration inputs; a generic checkout does not supply them.
- Preserve original Fedora KDE applications and their distribution dependencies.
- Keep project Python out of the tablet, recovery, initramfs and installers. The original Fedora desktop dependency exception stays on the Fedora root.
- Review the exact target before any write. Replacing Android userdata destroys its applications, files and encryption metadata.

After the first Fedora boot:

```sh
sudo dnf update --refresh
```

## Documentation

| Topic | Guide |
|---|---|
| Current public workflow | [PUBLIC-BUILD.md](docs/PUBLIC-BUILD.md) |
| Build architecture | [ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Original Plasma first run | [PLASMA-FIRST-RUN.md](docs/PLASMA-FIRST-RUN.md) |
| Historical image contracts | [IMAGES.md](docs/IMAGES.md) |
| Userdata preparation | [USERDATA-PREPARATION.md](docs/USERDATA-PREPARATION.md) |
| Actual device functions | [Hardware status](https://github.com/MCC45TR/uke-linux#hardware-support) |

Source checks, image checks, VM tests, package installation and physical tablet behavior are reported independently. Keep exact source/package identities and checksums with each delivery; keep raw private logs and device identifiers out of public reports.

## License

Project material retains the repository license. Fedora packages, upstream tools and imported source components retain their own licenses and attribution.
