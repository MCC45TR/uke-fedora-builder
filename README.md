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

The [October 7 Core candidate](reports/CORE-FILESYSTEM-2026-10-07.json) repeats
those checks with the signed native COPR 1.4 kernel, boot/CDC release 4,
512 MiB ESP, 8 GiB Linux and 4096-byte FAT sectors. It records all 15,318 SELinux
inode contexts and the stricter RAM inspection. These are recipe sizes;
target capacity, firmware visibility and physical first TTY remain unverified.

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

## Stock ABL boot_b development route

`./ukelinux.sh --build boot-pair --distro=fedora --help` describes the new
two-image development recipe for `boot_b` and a separate GPT partition named
`linux`. It prepares a root-capable built-in initramfs, source-pinned adaptation
of the bootloader-selected DT and a local tablet-screen TTY candidate. The
host builder never changes GPT, Android userdata, slots, init_boot, vendor_boot
or dtbo. Actual Image/modules/DTB compilation, all 1,146 module byte comparisons
against signed COPR release 1.5 and the linked initramfs check have passed.
EXT4 labeling/readback and full sparse decode checks have passed. A generic
ARM64 diagnostic VM reached the enforcing Fedora root and executed a local
TTY keyboard command; the final frozen recipe and negative-root cases are
under revalidation. Physical ABL, UFS, screen and input acceptance are separate
owner-test gates.
See the [paired-image operator guide](https://github.com/MCC45TR/uke-linux-docs/blob/main/docs/testing/FEDORA-BOOT-PAIR.md)
for coordinated UUIDs, the separate GPT `linux` prerequisite and rollback.
Do not substitute the older initramfs-only image for this root-capable pair.

`./ukelinux.sh --build boot --distro=fedora --help` describes the additional
host-only `fedora_boot.img` route. It builds a raw ARM64 kernel with a built-in
Fedora debug initramfs and wraps it in Android boot v4. Aloha and ESP are not
needed by this route. The debug target starts the existing identity-gated
VT2/ESP32 services without mounting or switching to the internal Linux root.

The first profile requires the qualified 13-patch 7.2.9 kernel, reviewed Core
initramfs and an exact reviewed boot template. Android 17 EvolutionX is the
default local template locator; OS3.0.304.0/303.0 global OEM templates remain
separate explicit profiles. Refreshed Android properties and matching OTA
metadata do not establish actual installed firmware bytes. Native C++ packing, linked
initramfs byte checks, module configuration/export checks and payload audits
run locally; no Python packer or tablet Python runtime is introduced.
Other compiler jobs retain priority. `--dry-run`, `--offline` and `--self-test`
are available. The script has no flashing or slot-control operation.

The intended manual target is `fastboot flash boot_b fedora_boot.img` after
separate device admission. The output is unsigned and its 96 MiB template size
is not a live partition measurement. Matching stock vendor_boot_b/dtbo_b still
supply DT. Actual DT/RAM handoff, ABL acceptance and physical ESP32/TTY remain
open. A subsequent private TWRP capture established the live B capacity and
retained its actual boot-chain backups, but found a mixed B firmware tuple.
Its live stock root lacks the project identities required by the VT2/CDC gate;
an unchanged stock DT would skip those services. A separately reviewed DT
handoff is therefore required for first TTY. The independent project DTB stays
separate. See the
[operator guide](https://github.com/MCC45TR/uke-linux-docs/blob/main/docs/testing/FEDORA-BOOT-B.md)
for build inputs, checks and preservation of the pre-test B image.

The [October 7 boot candidate](reports/FEDORA-BOOT-B-2026-10-07.json) records
the actual 96 MiB output, linked initramfs/module checks and matching QEMU
result. The exact Image ignored a poison external ramdisk and conflicting
command line. A foreign DT skipped the shell; a synthetic identity fixture
accepted a VM USB keyboard command on VT2. A cache reuse build reproduced the
same wrapper bytes. [New source DT inspection](reports/BOOT-SOURCE-DT-2026-10-07.json)
keeps OEM 304 and EvolutionX alternatives separate and non-launchable.
Native COPR [11090323](https://copr.fedorainfracloud.org/coprs/build/11090323)
succeeded for the corrected full 13-patch kernel release 1.5. Its
[signed native outputs](reports/COPR-KERNEL-1.5-2026-10-07.json) then passed
all 1,146 module architecture/vermagic/symbol checks, clean 13-patch SRPM
preparation, and actual AArch64 upgrade/removal/fresh-install/removal tests.
The Core filesystem recipe still pins the earlier qualified native 1.4 tuple;
no new full Core composition or tablet boot is implied by these package checks.
