# Fedora for POCO Pad X1 and Xiaomi Pad 7

Fedora Rawhide AArch64 image recipes and validation tools for `uke` / SM7675.
Kernel sources and RPM rules are maintained in the [Senemos repository](https://github.com/MCC45TR/senemos-uke-kernel-mainline).

[Project status](https://github.com/MCC45TR/uke-linux) · [Architecture](docs/ARCHITECTURE.md) · [Development COPR](https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/) · [Image releases](https://github.com/MCC45TR/uke-linux-images/releases)

The [Plasma first-run recipe](docs/PLASMA-FIRST-RUN.md) prepares the full original
Fedora desktop selection, user-created accounts and the enabled development
COPR. Offline checks are separate from first-run GUI and tablet acceptance;
the currently published Alpha image is not replaced by this source change.

## Public build entry — 26 October 2026

Run `./ukelinux.sh` from the [workspace](https://github.com/MCC45TR/uke-linux)
for image or kernel builds. The [public build guide](docs/PUBLIC-BUILD.md) covers
Ubuntu/Fedora/openSUSE/Arch/Alpine hosts, both boot layouts, four filesystems,
KDE/GNOME, three package channels, prerequisite consent and output selection.
The 24 October KDE EXT4 singleboot export passes host image checks; exact-export
tablet acceptance remains open. A Linux 7.3 replacement is building on the
[release branch](https://github.com/MCC45TR/uke-fedora-builder/tree/release/kde73-20261026).
Its explicit deferred-touch option omits private data and requires local
provisioning before account setup. Both CI jobs pass at `c23bfbb`; no completed
new image follows from that result. The earlier testing release currently has
no attached assets. Historical recipes below retain their dated scope.

## Status — 14 October 2026

This section describes the historical 14 October profile. Current normal
development boots reach original KDE on signed Linux 7.3.0-15; see the
[current hardware table](https://github.com/MCC45TR/uke-linux#hardware-support).

Matched RAM boots reached the tablet console, the existing 64 GiB Fedora root,
software KDE and Wi-Fi SSH. The revised initramfs starts ADSP charger services
and exposes battery readings in a fresh RAM boot. Repeated cold boots, normal
slot-B startup and automatic charging still need testing.
Finger input and ten simultaneous touch contacts also worked in the
14 October tablet test; stylus and touch lifecycle checks remain open. Power
and volume buttons and manual backlight control also worked. Backlight
adjustment is linear and difficult to use comfortably; a logarithmic curve is
planned.

Published Core and KDE prebuild roots have separate host/filesystem checks;
those exact root images have not been booted on the tablet. Current device
results come from a different development installation. See the
[hardware table](https://github.com/MCC45TR/uke-linux#hardware-support).

Core and early-initramfs payloads reject Python. The Fedora root may retain
Python supplied by unmodified original Fedora desktop dependencies, under the
14 October exception. Those files must match separately verified signed RPMs.
Project device helpers remain native code or shell. KDE applications are not
cloned, forked or rebuilt as Uke variants.

The [18 October userdata F2FS preparation](docs/USERDATA-PREPARATION.md) uses
Plasma Login Manager, preserved translations and the `uke-linux` COPR channel.
Its offline payload preparation is separate from OrangeFox installation,
firmware provisioning and physical acceptance. Automatic userdata kernel-slot
activation remains gated; this does not replace the published Alpha installer.

## Build commands

Run image commands from the [Uke workspace](https://github.com/MCC45TR/uke-linux):

```sh
./ukelinux.sh --build core --distro=fedora --test
./ukelinux.sh --build boot-pair --distro=fedora --help
./ukelinux.sh --build boot --distro=fedora --help
```

| Target | Output / purpose |
|---|---|
| `core` | Console filesystem and separate UEFI/ESP development outputs |
| `boot-pair` | Root-capable `fedora_boot.img` and `system.img` for the stock Android bootloader |
| `boot` | Older initramfs-only debug image; does not switch to the Linux root |

For the current public kernel workflow, use the workspace entry point:

```sh
./ukelinux.sh --build kernel
```

Build scripts support dry-run, offline and self-test modes. They do not create
partitions, flash images or select slots. Other compiler jobs retain priority;
source and completed build caches are reused.

## Stock bootloader route

The historical pair recipe selects exactly one physical ext4 GPT partition named
`linux` through `root=PARTLABEL=linux`. A fixed filesystem UUID is not required.
The boot image targets `boot_b`; no ESP is needed. Runtime device-tree changes
preserve the bootloader's RAM map and reserved regions. Android userdata,
`init_boot`, `vendor_boot` and `dtbo` are not changed by the builder.

Image, initramfs, device tree and modules must come from a matching build.
Installing a kernel RPM through DNF does not update the embedded boot image or
write `boot_b`. Older package revisions sharing the same kernel release can
replace its modules, so updates need a reviewed boot/module set and rollback.

The public image route also supports singleboot on `userdata`, with its matching
boot profile. Writing userdata destroys Android data. Preserve stock early
firmware and a verified rollback. After first boot, run `sudo dnf update --refresh`;
automatic slot activation remains disabled.

Before a device trial:

```sh
./ukelinux.sh --check-device --pair DELIVERY_DIRECTORY
```

This read-only check verifies delivery files, root selection, Uke identity,
slot/unlock state and target capacities. `--offline` checks local files only;
`--report NEW_FILE` saves a private result. Exit 2 means device prerequisites
are unavailable. Passing the check does not establish a backup or successful boot.

The recipe mounts `persist` read-only to preserve OEM calibration. Sensor tests
must not turn it into a writable registry. The current debug profile can provide
local and USB shells; they are development features, not secure release defaults.

See the [image guide](docs/IMAGES.md), [private boot-pair instructions](https://github.com/MCC45TR/uke-linux-docs/blob/main/docs/testing/FEDORA-BOOT-PAIR.md)
and [boot-B instructions](https://github.com/MCC45TR/uke-linux-docs/blob/main/docs/testing/FEDORA-BOOT-B.md)
for exact profiles and rollback requirements. The UEFI/ESP32-S3 host route is
separate work; it does not inherit stock-bootloader test results.

## Validation records

Dated reports retain their original test scope. The October 9 pair used a UUID
contract; later recipes use the partition name. A VM boot or package installation
does not establish tablet UFS, screen, USB or sleep behavior.

- [Image construction](reports/CORE-FILESYSTEM-2026-10-05.json)
- [Stock-bootloader pair](reports/FEDORA-BOOT-PAIR-2026-10-09.json)
- [Kernel lifecycle](reports/KERNEL-7.2.9-RAWHIDE-2026-10-04.json)
- [Host bootstrap](reports/HOST-BOOTSTRAP-2026-10-04.json)
- [COPR automation](reports/COPR-AUTOMATION-2026-10-04.json)
- [Recovery packages](reports/RECOVERY-RAWHIDE-2026-10-04.json)
- [Private engineering records](https://github.com/MCC45TR/uke-linux-docs)

Firmware redistribution and licenses are reviewed separately from kernel source
packages. Public releases include checksums and installation limits; physical
results are reported separately for each tested build and device variant.

### Root mount policy — 19 October 2026

New Core and boot-pair roots use noatime and errors=remount-ro on ext4. This
matches the boot integration template while preserving the existing filesystem
identity, normal ordered journaling, write barriers and commit interval. The
first option avoids access-time writes; the second protects an errored root
from further writes. Periodic trimming remains separate from continuous
mount-time discard. Source checks do not qualify a newly exported image.
