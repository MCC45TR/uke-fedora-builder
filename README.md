# Uke Fedora Builder

Fedora Rawhide AArch64 image and build tools for the **Xiaomi Pad 7** and **POCO Pad X1** (`uke`, Qualcomm SM7675).

This repository contains the image recipes, boot integration and validation tools used by [Uke Linux](https://github.com/MCC45TR/uke-linux). Kernel sources and RPM packaging are maintained separately in [Senemos Uke Mainline Kernel](https://github.com/MCC45TR/senemos-uke-kernel-mainline).

[Build guide](docs/PUBLIC-BUILD.md) · [Hardware status](https://github.com/MCC45TR/uke-linux#hardware-support) · [Development COPR](https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/) · [Image releases](https://github.com/MCC45TR/uke-linux-images/releases)

> [!WARNING]
> Uke Linux is still experimental. Successful build and image checks do not guarantee a working installation on the tablet. Keep a verified recovery path and backups before flashing.

## Project status

As of **26 October 2026**, the Fedora KDE EXT4 singleboot candidate with signed **Linux 7.3.0-16** and **Uke Control 1.15.0-2** passes host-side filesystem, SELinux, sparse-image and compression checks. The exported image has **not yet been validated on a tablet**. Earlier working desktop and hardware results come from a separate development installation.

See the [frozen build recipe](https://github.com/MCC45TR/uke-fedora-builder/blob/b0fd2380b07dbaaf37403c057b74796faf8f5ed3/docs/PUBLIC-BUILD.md) and [release records](https://github.com/MCC45TR/uke-linux-images/tree/main/releases/prebuild-fedora-kde-singleboot-ext4-20261026-k7.3.0-16-testing) for that exact candidate. The source workflow in this checkout is maintained separately; not every kernel version or build combination has the same validation status.

## Build

Start from the main Uke Linux workspace on an **x86_64 or AArch64 Linux host**. The public builder supports Ubuntu, Fedora, openSUSE, Arch Linux and Alpine.

```sh
git clone --recurse-submodules https://github.com/MCC45TR/uke-linux.git
cd uke-linux
./ukelinux.sh
```

The interactive menu lets you choose a build target, installation layout, filesystem, desktop, package channel and output directory.

| Option | Available selections |
| --- | --- |
| Build target | Fedora image or kernel |
| Boot layout | `singleboot`, `multiboot` |
| Filesystem | `ext4`, `f2fs`, `btrfs`, `xfs` |
| Desktop | Original Fedora KDE Plasma or GNOME |
| Package channel | `stable`, `testing`, `unstable` |

For non-interactive builds:

```sh
# Fedora KDE image using userdata
./ukelinux.sh --build image --mode singleboot --filesystem ext4 \
  --desktop kde --channel testing --out ./out

# Kernel packages and boot profiles
./ukelinux.sh --build kernel --channel testing --out ./out

# Check a configuration without building
./ukelinux.sh --build image --mode multiboot --filesystem btrfs \
  --desktop gnome --channel unstable --dry-run
```

The builder checks source and package inputs, keeps build records and generates checksums. It does **not** repartition the tablet, flash images or switch boot slots. Supported options and prerequisites are documented in the [public build guide](docs/PUBLIC-BUILD.md).

## Boot layouts and installation

| Layout | Root filesystem | Requirements |
| --- | --- | --- |
| `singleboot` | `userdata` | Replaces Android userdata and its contents |
| `multiboot` | Existing Linux partition | Requires a previously created `linux` partition; no boot menu is provided |

Both stock-bootloader layouts use a matching `boot_b` image. Keep the kernel, modules, device trees and initramfs from the same build. UEFI/ESP development is a separate boot path and is not covered by the stock-bootloader results.

> [!CAUTION]
> Flashing a singleboot root image to `userdata` **erases Android apps, files and encryption metadata**. The builder does not create the Linux partition required by multiboot.

Before a device test, the workspace provides a read-only prerequisite check:

```sh
./ukelinux.sh --check-device --pair DELIVERY_DIRECTORY
```

A successful check is not proof that an image will boot. Follow the [manual installation and rollback instructions](docs/PUBLIC-BUILD.md#output-and-manual-installation) and verify the exact files and target partitions before flashing.

Generic public images do not bundle private per-device touch references. If the selected profile needs one, supply the target tablet's own qualified reference locally; never reuse another device's calibration data. The original Fedora desktop is retained, with user account creation handled during first setup.

## Documentation

| Topic | Reference |
| --- | --- |
| Public image and kernel builds | [PUBLIC-BUILD.md](docs/PUBLIC-BUILD.md) |
| Image profiles and earlier Core builds | [IMAGES.md](docs/IMAGES.md) |
| Plasma first-run setup | [PLASMA-FIRST-RUN.md](docs/PLASMA-FIRST-RUN.md) |
| Userdata/F2FS maintenance | [USERDATA-PREPARATION.md](docs/USERDATA-PREPARATION.md) |
| Build architecture | [ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Validation records | [reports/](reports/) |
| Security reporting | [SECURITY.md](SECURITY.md) |

Build results, package installation tests and physical tablet tests are recorded separately. For known hardware limitations, see the [Uke Linux hardware table](https://github.com/MCC45TR/uke-linux#hardware-support).

## License

The builder's original code and documentation are licensed under [MIT](LICENSE). Fedora, Linux and other included components retain their respective licenses.
