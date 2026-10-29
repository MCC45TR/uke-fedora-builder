# Public source and image builds

23 October 2026. This host workflow starts from public source and an empty Fedora
Rawhide AArch64 root. It does not consume a prepared private root, historical
Core cache, a stock boot dump or a pre-existing local container ID.

The implementation has shell syntax, CLI and source-integrity checks. Kernel,
container and image builds were not run for this change. None of the 48 image
selections has new physical acceptance from this work. Mutable Rawhide/COPR
repositories also prevent a promise of identical bytes on future builds.

## Start

Use a Linux host running Ubuntu, Fedora, openSUSE, Arch Linux or Alpine, with
x86_64 or AArch64 architecture. Install Git using the host package manager to
obtain the source. On minimal Alpine, invoke the entry with `sh`; it offers to
install Bash before opening the menu.

```sh
git clone --recurse-submodules https://github.com/MCC45TR/uke-linux.git
cd uke-linux
./ukelinux.sh
```

The menu asks for image or kernel, boot mode, filesystem, desktop, package
channel and output directory. Explicit CLI selections are retained. The default
output parent is `out` below the directory from which the command was invoked,
including when the entry is invoked by an absolute path from elsewhere.
Each invocation creates a new private run directory and preserves older output.

```sh
./ukelinux.sh --build image --mode multiboot --filesystem ext4 \
  --desktop kde --channel testing --out ./out

./ukelinux.sh --build image --mode singleboot --filesystem f2fs \
  --desktop gnome --channel stable --out ./out

./ukelinux.sh --build kernel --channel testing --out ./out

./ukelinux.sh --build image --mode singleboot --filesystem btrfs \
  --desktop kde --channel unstable --dry-run
```

Every kernel build is cached under `out/cache/kernel-builds/` by source commit, exact Linux version and producer. The producer includes the build route, worker configuration, executable kernel build scripts and exact worker image IDs. A changed helper compilation rule or worker therefore selects a different cache entry. After `--build kernel`, an image build with `--reuse-kernel` checks the entry's checksums, source and producer before restoring it. The manifest retains the original producer and the current requested kernel selection. A damaged entry is replaced by the next kernel build.

`--jobs` accepts 1 through the number of online CPUs and defaults to all of them. `--linux-size` accepts 8192 through 65536 MiB and
defaults to 16384. The sparse codec has a 64 GiB raw-image bound. Allow at least
64 GiB for kernel/tool work plus three times the selected root size. No
generic ARM64 kernel is substituted.

x86_64 hosts run every step that executes no AArch64 code in a native worker:
the kernel is cross-compiled with LLVM, and the root is installed with native
`dnf5 --forcearch=aarch64`. QEMU user emulation, through the host binfmt handler,
runs only the initramfs base, the stable-channel hardware packages, RPM
scriptlets and three `chroot` commands. A root stage fails if any scriptlet
failed under emulation. Set `UKE_CROSS=0` to emulate every AArch64 step instead.

`--kernel VERSION|latest|lastest` selects the Linux version. The default is `kernel.default_version` in the policy. `latest` is kernel.org's newest stable release; it is resolved once per build, before any worker starts, and `lastest` is accepted as an alias. The selected source must pass its actual SRPM producer's `make validate version=VERSION` checks before source downloads. A profile accepted by another host build route does not admit this native RPM route. Unsupported versions stop explicitly without substituting a generic or older kernel. The kernel release (for example `7.2.12-20`) is read from the selected source's spec, so the initramfs, RPMs and module paths match. `manifest.json` records the requested selection, the resolved version, the source commit and the release.

24 October 2026: the current native SRPM producer admits Linux 7.2.12. Kernel.org
`latest` resolves to 7.3, which needs a reviewed native Uke profile and producer
update before this route can build it. Older profiles in the standalone kernel
entry do not establish support in this producer.

The kernel source is the head of `kernel.ref` in the policy repository, resolved once when the build starts. `UKE_KERNEL_REPO=PATH` uses a local checkout at its committed `HEAD` instead (`none` keeps the policy repository). Git validates the path, so a linked worktree is accepted; an invalid path or a checkout with uncommitted changes stops the build. Workers receive a snapshot of that commit. Offline builds use the newest cached source and kernel.org list unless a checkout is given.

## Selections

| Selection | Build contract |
|---|---|
| `multiboot` | Stock ABL `boot_b` plus an already provisioned GPT partition named `linux`; Android slot A is preserved. This is the existing two-OS layout, not a new boot menu. |
| `singleboot` | Stock ABL `boot_b` plus `userdata`; writing the root image destroys Android userdata. |
| `ext4`, `f2fs`, `btrfs`, `xfs` | A separately formatted, labeled `UKE_LINUX` filesystem; Btrfs uses one device. Each explicit root selector admits these formats. |
| `kde` | Original Fedora Plasma, Plasma Login Manager and Plasma Setup; no KDE source fork or rebuild. |
| `gnome` | Original Fedora GNOME Shell, GDM and GNOME Initial Setup. |
| `stable` | Packages from `mcc45tr/uke-linux`, plus the pinned local platform-family builds described below. This is not a stable Fedora release or hardware qualification. |
| `testing` | Signed packages from `mcc45tr/uke-linux-test`; the installed control channel is named `test`. |
| `unstable` | The test repository with the installed control channel named `unstable`. |

All three channels build the same kernel source and version, selected by
[`configs/public-build.json`](../configs/public-build.json) and `--kernel`. An unstable
selection does not silently replace it with an unported kernel.org release candidate.
Kernel-only output uses that same source/spec and produces both root profiles.
The stable repository predates the current source families. Stable image builds
therefore also compile `uke-additional`, `uke-sensors`, `uke-hw`, `uke-power`,
`uke-core` and `uke-metas` from the exact public hardware commit in that policy.
Their source RPMs and unsigned local binary RPMs are retained. Only that local
source-build repository has package signing disabled; remote repositories keep
signature verification. No testing repository is enabled for a stable image.
This full source route takes substantially longer than the testing image path.
The source pin is independent of later RPM channel transitions on the tablet.
The pinned source producer's four historical SRPM inputs are cached from the
checksum-locked GitHub archive before composition. This preserves the selected
commit and input bytes after the retired COPR archive projects are removed.
Online builds verify each download; offline builds require the exact cached
bytes. Only `uke-linux` and `uke-linux-test` remain active Uke COPR projects.

## Host preparation and input verification

Missing host tools are offered through APT, DNF, Zypper, Pacman or APK. The
package list is shown before confirmation. Podman is preferred; an operational
Docker engine can also be used. Rootless Podman UID/GID preparation and
AArch64 binfmt registration require their own confirmation when needed.
`--yes` supplies consent for these preparation operations in unattended runs.
No host distribution upgrade is performed except Pacman's required synchronized
`-Syu` transaction when installing missing packages.

Containers install the compiler, RPM BuildRequires, DNF, filesystem tools and
libguestfs. Native build and filesystem workers are built from public Fedora
base digests in `configs/build-rules.json`, rather than assumed local image IDs.
The generated container IDs and exact package inventories are recorded with the
output. The base digest is pinned; packages installed from live repositories
are not a frozen toolchain snapshot.

The native kernel producer verifies the upstream archive hash, detached
OpenPGP signature, adaptation manifests and boot-source hashes. Its original
Fedora `python3` BuildRequires supports upstream Kbuild on the host only; it is
not copied into the initramfs or installed as a project tablet service.
Source-built local kernel RPMs are unsigned and identified as such. Remote RPM
signature verification stays enabled, and the selected COPR key fingerprint is
checked before import. Original Fedora desktop Python dependencies are admitted
only when their payload bytes match separately signature-verified Fedora RPMs.

`--dry-run` validates choices and prints the plan without installing anything,
creating output or running containers; it does not require `jq`. `--offline`
requires previously prepared worker images, upstream kernel inputs, repository
metadata, package caches and signing keys under the same output parent. A cold
offline run fails. Cache files still undergo the same verification. The script
never substitutes an unsigned download for a missing signed package.

## Device-local inputs

Generic composition requires no private touch reference, unit identifier,
backup image or calibration archive. Generic OEM firmware is installed from
the public signed firmware package. Its notices and redistribution review remain
separate from source availability; an image containing it is not automatically
a public release artifact.

Touch startup is conditional on that device's own reference. An optional
`--touch-reference FILE` accepts a regular, non-symlink file of exactly 5432
bytes and mode 0600. It is copied only into the local root, and the output
manifest records that private data are included. These checks establish shape
and permissions, not calibration quality or panel compatibility. Use only an
already qualified local CSOT capture. Do not copy another device's reference.
The public probe source is in `uke-sensors/src/touch-normal-probe.cpp`; its
panel/GPIO admission and physical capture acceptance remain prerequisites.
This workflow does not assert that a new device has completed them.

Without a qualified reference, touch remains unavailable; use USB input for
first account setup. No password, human account, SSH host key or remote root
login is shipped. SSH is installed but disabled. Stock persist is mounted
read-only by the existing explicit fstab policy. Automatic kernel activation
is disabled in both update policies.

## Output and manual installation

The `artifacts` directory contains the source/binary kernel RPM set, both kernel
boot profiles, a manifest and `SHA256SUMS`. An image build additionally produces
`boot.img` and either `linux.img` or `userdata.img` in Android sparse format.
The manifest records raw capacity separately from sparse transfer size. Only
the boot profile matching the selected root is copied to `boot.img`.

The filesystem is created in an isolated libguestfs appliance using a new
regular file. No host block device is passed through. A second read-only
appliance reads the contents, owners, ACLs, capabilities and SELinux label sample
back. Sparse readback compares every raw byte with both the project decoder and the independent AOSP `simg2img` decoder. These checks are host
validation, not evidence that a tablet can boot the result.

`FLASHING.txt` and the terminal show manual commands after successful completion.
Before using them, retain verified backups, an unlocked bootloader, matched
slot-B stock firmware and a working recovery route. Confirm `product=uke`,
current slot and the actual capacities of the selected root and `boot_b` with
`fastboot getvar`. A multiboot `linux` partition must already exist; this builder
does not repartition storage. Never copy another device's partition offsets.

From the exact image output directory, after those checks:

```sh
sha256sum -c SHA256SUMS
# Multiboot only: replaces the existing Linux root.
fastboot flash linux linux.img
# Singleboot alternative: destroys Android apps, files and encryption metadata.
# fastboot flash userdata userdata.img
fastboot flash boot_b boot.img
fastboot set_active b
fastboot reboot
```

Preserve `boot_a`, `init_boot`, `vendor_boot`, `dtbo`, persist, early firmware and
your separate rollback copies. Return to the working stock slot/recovery if boot
fails. Restore only your own verified backups to their original partitions.
The kernel-only output is insufficient for a new installation: install its exact
matched RPM/module set into an existing compatible root before using its boot
images. Never flash a kernel against a different module set.

F2FS userdata is expanded offline by the source initramfs on first boot. Other
formats retain the image size; automatic online growth is not enabled by this
recipe. Complete original desktop account setup, then **run
`sudo dnf update --refresh` after the first Fedora boot**. This is required.
A package update does not authorize a kernel slot write; activation remains a
separately guarded operation.

## Validation scope

The public shell fixtures cover all 48 selections, three kernel channels,
invalid input, package-consent refusal, missing-`jq` planning and output paths.
The source change also extends parser fixtures for the explicit Linux profile.
No new container, kernel, filesystem image, VM boot or tablet run was executed
for the 22 October implementation. First full builds, package resolution on each
channel, desktop setup and recoverable tablet boot remain necessary acceptance
checks. Historical `core`, `boot` and `boot-pair` commands remain available for
their dated frozen contracts; their old caches are not prerequisites here.

## Manual CI source selection

The `Public image build (manual)` workflow requires `workspace_commit`, a full
40-character `MCC45TR/uke-linux` commit, and `kernel_version`, an explicit Linux
version supported by that commit's kernel component. Moving branch names and
`latest` are refused. The workspace is checked out detached and its recorded
submodule commits are initialized without following component branches. The
kernel source comes from that selected workspace through `UKE_KERNEL_REPO`.

The workflow revision controls acquisition; the selected aggregate's builder
revision performs the build. The local `source-identity.txt` receipt names both,
the requested Linux version and every initialized component commit, including
when the later build fails. Retain this receipt beside the produced manifests.
A commit without the builder's local-kernel selection contract is not an
admitted historical build recipe; inspect compatibility before dispatch.

This freezes project source selection, not the entire package universe. Stable
hardware sources retain the builder policy's explicit commit; testing/unstable
RPM repositories and Fedora Rawhide may change. Archive the actual signed RPM
set, repository metadata, container digests and output hashes before claiming
reproducibility. This workflow neither publishes nor proves tablet acceptance.

From this repository, `bash tests/workspace-source.sh` checks selection against
moving aggregate/component branches using disposable local Git repositories;
it also refuses branch aliases, missing commits and occupied destinations.
