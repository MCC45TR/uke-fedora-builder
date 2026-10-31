# Public source and image builds

29 October 2026: the public builder accepts Fedora 44, Fedora 45 and Rawhide as
separate targets, and Bash, Fish or Zsh as the new normal user's login shell.
The default remains Rawhide, KDE and Bash. Fedora 44/45 image composition stops
before host preparation until signed Uke family builds and dependency resolution
are validated. Cutefish image composition also stops: its graphical login and
secure first-account flow are unvalidated. Dry-run selection is not image support.

The three targets use reviewed per-architecture Fedora image digests in
`configs/build-rules.json`. Public RPM stages derive the dist tag from that
worker, use release-specific Fedora/COPR repositories and segregate package and
kernel caches by release and channel. The default kernel is pinned to the
reviewed Uke Linux 7.3.0-33 source commit; no generic Fedora kernel is substituted.
The legacy Core command retains its original Rawhide-only contract.

`--shell` installs the original Fedora shell, validates the executable from the
target RPM and `/etc/shells`, and updates `useradd -D` in the new root.
AccountsService 26.27.3 calls useradd without a shell override. Existing accounts
and root keep their shells. Graphical setup and AArch64 first-user acceptance
remain separate from native x86_64 container user-creation tests.

`--release` (alias `--fedora-version`) selects Fedora, independently of
`--channel`. Explicit desktop/shell flags are rejected for kernel-only builds.
Testing and unstable share `uke-linux-test`; they are not separate repositories.
Builds never flash a device. Singleboot flashing destroys Android userdata;
multiboot requires an existing physical `linux` partition.

```sh
./ukelinux.sh --build image --release 44 --desktop kde --shell bash --dry-run
./ukelinux.sh --build image --release 45 --desktop cutefish --shell fish --dry-run
./ukelinux.sh --build image --release rawhide --desktop gnome --shell zsh --dry-run
./ukelinux.sh --build kernel --release 45 --channel testing
./ukelinux.sh --self-test
```

All 648 release/desktop/shell/layout/filesystem/channel plans are checked without
network or host preparation. The Cutefish meta package selects the real,
separately packaged upstream desktop; it enables no display manager and cannot
establish image or tablet support. Fedora 44/45 chroots were enabled in
`mcc45tr/uke-linux`, `mcc45tr/uke-linux-test` and `mcc45tr/cutefish`.
Compatibility builds 11222490 and 11222501–11222510 failed after source preparation,
without published binary logs. No Fedora 44/45 stable RPM promotion was performed.

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
The output filesystem must enforce a user-owned mode-0700 directory; otherwise
the build refuses before copying any private input. A filesystem that ignores
Unix permissions is unsuitable even if it has enough free space.

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

The policy source is pinned to Uke Linux 7.3.0-33. `UKE_KERNEL_REPO=PATH` uses a
committed local checkout instead; an invalid or modified checkout is refused.
Offline builds require the exact pinned source, or that explicit local checkout.
Workers receive an immutable source snapshot. `latest` still needs a profile
admitted by the selected SRPM producer.

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
| `unstable` | Signed individual packages from `mcc45tr/uke-linux-unstable`; Fedora Rawhide AArch64 only. |

The stable/testing source routes use the kernel policy in
[`configs/public-build.json`](../configs/public-build.json) and `--kernel`.
Unstable consumes matching signed kernel RPMs, defaults to `--kernel-rpm latest`
and refuses local source substitution. Kernel-only output retains both root
profiles for the selected source or signed RPM set.
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
bytes. The three current Uke COPR channels are `uke-linux`, `uke-linux-test` and
`uke-linux-unstable`; retired archive projects are not build inputs.

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

The public shell fixtures cover all 648 selection plans, three kernel channels,
invalid input, package-consent refusal, missing-`jq` planning and output paths.
The source change also extends parser fixtures for the explicit Linux profile.
Native x86_64 Fedora 44, Fedora 45 and Rawhide container user-creation checks
passed for Bash, Fish and Zsh. Fedora 44 libdnf5 5.4.6 compilation and signed local
repository fixtures passed. These checks do not validate AArch64 execution, a
graphical first-account flow, image composition or tablet hardware. Those remain
required acceptance checks. Historical `core`, `boot` and `boot-pair` commands remain available for
their dated frozen contracts; their old caches are not prerequisites here.

## Explicit EL2/KVM profiles

25 October 2026: source preparation only; the profile changes below have not
been tested. `--kernel-profile normal` remains the default and keeps the existing
ordinary source/family policy. `--kernel-profile el2-require --channel testing`
selects the isolated Linux 7.3 KVM producer. Linux `7.3` is normalized to package
version `7.3.0`. `--kernel` selects a version; `--channel` selects the RPM
repository; neither substitutes for a kernel profile.

```bash
./ukelinux.sh --build kernel --kernel 7.3 --kernel-profile el2-require --channel testing --skip-tests
```

`--skip-tests` records explicit deferral of kernel fixtures and RPM checks;
source signatures, hashes, payload/privacy checks and profile admission remain
mandatory. Sources without explicit test-deferral support are refused. Default
builds retain their tests. This preparation did not invoke the command above or
build an image. The source RPM was produced separately and submitted to COPR.

The request, producer/cache identity and output manifest carry the selected
profile, source commit and native-config hash. The cache also separates builds
with deferred tests from builds with tests enabled. RPM version/release is
read separately from the exact `kernel-uname-r` capability; KVM's `-kvm` suffix
belongs to the Image/module/bundle ABI. Image composition selects only the
matching local family and preserves ordinary composition's KVM exclusions.
Neither profile installation nor this builder activates a connected device.

`el2-require` checks existing EL2 on primary and secondary entry. It parks on
EL1 and never performs a firmware-exit call. The historical EL1 firmware result
therefore remains a physical blocker. `el2-exit-experimental` is explicitly
refused: there is no accepted exact Uke firmware service, all-CPU return or
RAM/DMA/SMMU ownership contract. No allowlist entry was invented. Early debugger
registers do not provide persistent failure logs or recover a non-returning SMC.

The existing native probe and KVM-only Linux guest tools on
`main` retain the isolated EL2/KVM acceptance tools. No guest test
was run. Binder/BinderFS preparation supports a later original-Fedora Waydroid
trial; it does not establish Android, GPU or container acceptance. The upstream
Python container startup service needs a project policy decision before any
Waydroid installation. Preserve the accepted kernel/modules and physical
recovery route before any separately authorized activation.

## Hosted EXT4 singleboot image releases

Use the manual image-release workflow in `MCC45TR/uke-linux`. It selects the
recorded workspace/component revisions and runs natively on `ubuntu-24.04-arm`.
The image path is `--kernel-rpm latest --channel testing`: signed Fedora/COPR
binary packages supply the kernel and hardware userspace. No kernel or hardware
source build is performed. An exact `7.3.x-N.fc46` kernel tuple can replace
`latest`; one selected tuple supplies all six matching RPMs. The kernel key
fingerprint, each RPM signature, module inventory and both embedded boot Images
are checked before composition. The actual source and tuple replace provisional
source defaults in the run receipt. This route cannot combine a local source,
explicit `--kernel`, KVM profile, kernel-only build or kernel-cache reuse.

The hosted job uses Docker (`UKE_CONTAINER_ENGINE=docker`). The binary-package
path needs 16 GiB plus twice the requested root capacity; it uses a smaller
worker and validates one independent sparse decoder output at a time. The source
build path retains its original capacity requirement. Runner capacities can
change: the job checks actual free space rather than assuming a hosted label
provides enough storage. The 29 October probe measured 115 GiB free after unused
SDK cleanup; that observation is not a future capacity guarantee.

No touch reference, account credentials or SSH host keys are supplied. Before
any release is published, artifacts must pass metadata/content readback,
SELinux context verification, both sparse decoders, Zstandard readback and
checksums. Releases are marked as experimental pre-releases; these host checks
do not qualify tablet boot, first-account setup, charging or recovery.

## Independent unstable image inputs

30 October 2026: `unstable` selects `mcc45tr/uke-linux-unstable` and signing
fingerprint `2204A661EA630A5303500085538797E72A3E4ECA`. It supports only the
normal Fedora Rawhide AArch64 kernel profile. The default kernel input is the
latest signed matching RPM set; `--kernel-rpm` can freeze its exact release.
Local source, kernel-cache reuse and foreign-release substitutions are refused.
The signed payload supplies the source commit before root composition.

The unstable root selects individual runtime packages through `uke-core-meta`.
Its image codecs and offline verification helpers come from the separate signed
`uke-image-tools` COPR producer. The assembly worker has no project compiler or
RPM build stage. Existing stable/testing source and KVM routes retain their
separate policies; this change does not qualify those routes or alter their
COPR definitions. Native helper fixtures run in COPR; GitHub checks source only.

The shared EXT4 path passed a 1 GiB COPR guest fixture in
[build 11232234](https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-unstable/build/11232234/).
Normal Fedora RPM scriptlets, numeric owners, SELinux labels, content, exact
mtimes, ACLs and capabilities survived independent image readback. Deliberate
metadata corruptions were rejected; both sparse decoders reproduced the raw
image. The assembly policy pins signed `uke-image-tools-1.0.0-14.fc46.aarch64`.

The same build resolves all 12 complete KDE/GNOME, shell and root-profile goals
from the production package policy. These metadata checks stop before target
RPM downloads or installation. Unstable requests the owning Uke PipeWire
providers directly; normal dependency policy stays enabled.

This fixture does not compose the complete desktop root. Production guest
transport, full image composition and an independent rebuild remain required,
along with installation, growth, boot and recovery acceptance. Physical release
gates and firmware redistribution limits remain open.
