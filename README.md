# Fedora for POCO Pad X1 and Xiaomi Pad 7

Fedora Rawhide AArch64 build, package and update infrastructure for POCO Pad X1 and Xiaomi Pad 7 (`uke`, SM7675). The first delivery is a verified Senemos Linux 7.2.9 kernel package set. A console-first system image needs independently qualified firmware and Uke boot profiles.

[Uke Linux](https://github.com/MCC45TR/uke-linux) · [Build architecture](docs/ARCHITECTURE.md) · [Test COPR](https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/) · [Releases](https://github.com/MCC45TR/uke-fedora-builder/releases)

The owner's existing root reaches real Fedora, Wi-Fi SSH and the original KDE
desktop through matched stock-ABL RAM starts. The 13 October 1.27 trial starts
ADSP automatically, but charger services appear only after a controlled DSP
restart. The early-firmware recipe now preloads QRTR transport and the native
domain mapper before coldplug, and audits their actual initramfs order. This is
a startup correction candidate; fresh automatic charger readiness is unverified.
Historical host/VM records below retain their original dates and limits. Clean
released roots, UEFI and dependable normal slot-B boot remain separate gates.

## Outputs

- `senemos-uke-linux-kernel-mainline` RPMs with core, modules and DTB subpackages,
  plus the complete source RPM. Development headers are a later milestone.
- Matching ARM64 Image, independent Uke DTB, modules, config and build manifest.
- Module ABI, dependency closure, checksums and package lifecycle reports.

A local Rawhide AArch64 Core filesystem candidate has passed composition checks.
Firmware-specific boot and physical rollback validation remain open.

The first user experience is a Fedora Core development console. Desktop, graphics and media packages follow working kernel and boot paths. Core and early-initramfs payloads reject Python. The owner permits a separate exception only for original signed Fedora KDE dependencies; project startup, services and tests remain native or shell.

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
applications. The owner-authorized original KDE dependency exception is audited
separately and does not relax Core or early-initramfs payload checks.
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
The [October 9 paired-image result](reports/FEDORA-BOOT-PAIR-2026-10-09.json)
records completed EXT4 labeling/readback, independent Android sparse decoding
and verified cache reuse. The exact Image reached the real enforcing Fedora
root in generic ARM64 QEMU and executed a local TTY keyboard command. Separate
wrong-partition-name and wrong-UUID cases were rejected. The local owner-test
delivery contains a 96 MiB boot image and a 556.23 MiB sparse system image
representing a 3 GiB filesystem. Physical ABL, UFS, screen and input acceptance
remain separate owner-test gates; no public binary release is claimed.
See the [paired-image operator guide](https://github.com/MCC45TR/uke-linux-docs/blob/main/docs/testing/FEDORA-BOOT-PAIR.md)
for the root selector, separate GPT `linux` prerequisite and rollback.
Do not substitute the older initramfs-only image for this root-capable pair.

The October 11 recipe selects `root=PARTLABEL=linux`: exactly one physical
GPT partition named `linux`, containing ext4. Its filesystem UUID is recorded
as image metadata and is not an admission requirement. The historical October
9 pair retains its original UUID contract and immutable receipts. The current
initramfs also retains the local debug shell in emergency mode and reuses the
CDC shell before root transition; early-initramfs CDC remains a separate physical gate.

Before the owner's manual trial, run
`./ukelinux.sh --check-device --pair DELIVERY_DIRECTORY` from the workspace.
This verifies all nine delivery checksums, manifest/VM agreement, coordinated
root-selection contract and 3 GiB sparse header, then performs bounded read-only inventory
on one ADB or fastboot transport. Bootloader inventory checks Uke identity,
slot A, unlock state, `boot_b`/`linux` capacity and a non-logical `linux` target.
ADB can inspect physical-partition sysfs but still requires the bootloader
check. `--offline` only verifies local files; `--report NEW_FILE` saves a private
JSON result without unit identifiers or raw output. Exit 2 means device
prerequisites are unavailable. The check performs no device writes and cannot
establish backups, working Android return, physical boot or screen output.

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
The ARM64 configuration comparison permits the C user-link and pahole host
probes to differ only with Rust, debug information/BTF and samples disabled.
All module bytes and exported symbols still require exact equality.
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

## First physical development console, 2026-10-11

The host sparse codec accepts logical images up to 64 GiB for the existing
Uke Linux partition. It includes sparse chunk overhead in the encoded input
bound and still rejects DONT_CARE chunks, partial coverage, devices, symlinks
and existing outputs. This limit does not authorize a partition write.

The separate stock-ABL pair profile now selects the unique physical
`PARTLABEL=linux` EXT4 root, preserves the bootloader's RAM/reservations and
adapts the reviewed UFS/USB suppliers. The owner observed a sustained screen
TTY with the v5 Image plus scoped CoreSight autoload containment. Actual CDC,
authenticated USB ECM SSH and a 16-MiB byte-matched round trip completed.
The existing 64-GiB root was expanded without GPT changes. Wi-Fi, native GPU,
touch, battery telemetry, USB host power and repeated cold boot remain open.

The pair composer pins signed `uke-boot-integration` and `uke-esp32-cdc`
0.1.0-5 from COPR build 11108587. It explicitly applies the owner-requested
Xiaomi Pad 7 presentation and isolated USB debug profiles, including Fedora's
required NetworkManager managed-device override. The root enables only the
composite gadget units; serial-only units remain available as failure fallback
and in the initramfs. This avoids scheduling conflicting root units together.
Packages themselves enable no service and contain no credentials or SSH keys.

The NVMEM reboot-reason overlay has native host trust-boundary tests and one
physical `reboot bootloader` transition into bootloader fastboot. The matching
candidate passed two RAM starts with automatic USB SSH; its `boot_b` write was
read back byte-for-byte. Stock slot A and the existing root remain preserved.
These results do not qualify unattended slot-B boot or all reboot modes.
The original systemd command needs no wrapper. The ordinary COPR kernel RPM
does not contain this embedded-initramfs stock-ABL boot profile, and DNF never
writes `boot_b`. See the private
[hardware audit](https://github.com/MCC45TR/uke-linux-docs/blob/main/docs/testing/FEDORA-HARDWARE-AUDIT-2026-10-11.md)
for exact observed functions and remaining work.
