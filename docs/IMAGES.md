# Fedora Rawhide Core filesystem candidates

The Uke workspace entry is `ukelinux.sh`. Its implementation belongs to this
repository; it has no dependency on private documentation or a local root export.

```sh
git clone --recurse-submodules https://github.com/MCC45TR/uke-linux.git
cd uke-linux
./ukelinux.sh --build core --distro=fedora --test
./ukelinux.sh --build core --distro=fedora --offline --test
./ukelinux.sh --self-test
```

The initial target is Fedora Rawhide AArch64 Core. Other distributions and
desktop targets fail explicitly. The host entry prepares official prerequisites
on Fedora, Debian/Ubuntu, openSUSE, Arch and Alpine/postmarketOS, selects working
Podman/Docker and limits jobs to two CPUs and 3 GiB per container. Native
AArch64 and x86_64 with official QEMU binfmt are supported code paths; current
end-to-end validation is on the Fedora Rawhide x86_64 host. Builds wait for other
compilers and pause their own active container when another build starts.

## Locked inputs and audit boundaries

The runtime starts from an immutable official Fedora AArch64 OCI digest, then
replays the signed 57-input console closure, 13 signed system/identity inputs
and two signed boot/CDC RPMs. `manifests/images/core-*.json` record SHA-256,
architecture, source RPM identity and immutable Koji/COPR URLs. Both signing-key
fingerprints are checked before use. Package workers have networking disabled.
The GNU runtime vendor transition is explicitly allowed for the reviewed source.

Initial assembly uses dracut on the emulated host, then removes its assembly
packages and optional format/graphics/keyring payloads through DNF dependency
checks. RPM-owned files are never redacted to bypass an audit. No Python runtime,
Python scripts, private build paths, SSH keys, machine ID or random seed are
admitted into the complete target root or initramfs. Exact public SELinux
namespace rules have a six-file hash-pinned exception; modified files and host
identities are rejected. Target SELinux remains enforcing.

The image-host container uses GNU objcopy instead of target `systemd-ukify`,
plus native C/C++ e2fs/SELinux helpers. Fedora package-management tools can have
upstream host dependencies inside that disposable container; none of those
host tools are copied into tablet payloads. The OCI ID and recipe identify the
host environment. No project-owned Python build tool is introduced.

## Development shell and ESP32-S3

Core explicitly enables the original systemd development shell on VT2 and masks
`getty@tty2`. **This is an unauthenticated local root development shell**, selected
only by `senemos.debug=esp32-cdc` in this Core profile. It is not a general-purpose
or desktop security default. Root password login and SSH root access are disabled.

The tablet acts as USB host; the ESP32-S3 supplies CDC and HID interfaces. The
single C++ journal writer configures the explicitly selected `/dev/ttyACM0` at
115200 raw, asserts DTR/RTS and streams the current boot journal. HID types into
VT2; shell stdout/stderr go to journald. No logger is included in initramfs.
RPM installation alone enables neither this service nor the optional tablet
USB-gadget service. The old ESP32 firmware remains untouched and its exact
HID/control protocol is still unverified. PTY fixtures do not establish USB
hardware compatibility.

## Outputs and release gates

The compositor writes regular files only: a 4096 MiB EXT4 Linux candidate,
256 MiB FAT32 ESP candidate with 512-byte sectors, compressed copies, a UKI,
package list and checksums. These are **logical assembly sizes**, not measured
Uke GPT geometry. Partition roles are `uke_linux` and `uke_esp`; actual partition
creation and flashing remain separate recovery operations.

Every composition verifies complete root/initramfs payloads, kernel/config
identity, all-inode SELinux/owner/mode/capability preservation, EXT4 integrity,
complete readback, exact six-section UKI inputs, FAT integrity and ESP UKI
readback. No default loader, EFI variable update, Android binary or Nabu offset
is introduced. On-device kernel RPM updates do not yet regenerate/activate the UKI.

Current kernel DT lacks enabled Uke USB/UFS nodes and a static RAM map. A Uke
UEFI handoff, measured geometry, bridge enumeration, actual kernel boot and
rollback are unresolved release gates. Passing filesystem/package checks is a
local candidate result and cannot establish a bootable tablet image. Accepted
future release assets belong to `uke-linux-images`.
