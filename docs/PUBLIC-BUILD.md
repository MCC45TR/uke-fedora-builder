# Public source and image builds

23 October 2026. This host workflow starts from public source and an empty Fedora
Rawhide AArch64 root. It does not consume a prepared private root, historical
Core cache, a stock boot dump or a pre-existing local container ID.

The native x86_64 worker and a resumed testing/singleboot/EXT4/KDE composition
passed host checks on 23 October 2026. The image uses the signed testing
`7.2.12-22` kernel family. Host-tooling corrections required stage resumption;
an independent clean execution of the final recipe remains untested. No image
selection has new physical acceptance. Mutable Rawhide/COPR repositories also
prevent a promise of identical bytes on future builds.

## Start

Use a Linux host running Ubuntu, Fedora, openSUSE, Arch Linux or Alpine, with
x86_64 or AArch64 architecture. Install Git using the host package manager to
obtain the source. On minimal Alpine, invoke the entry with `sh`; it offers to
install Bash before opening the menu.

```sh
git clone --recurse-submodules https://github.com/MCC45TR/uke-linux.git
cd uke-linux
./ukelinux.sh --build image --touch-reference ./reference.bin
```

The menu asks for image or kernel, boot mode, filesystem, desktop, package
channel and output directory. Explicit CLI selections are retained. The default
output parent is `out` below the directory from which the command was invoked,
including when the entry is invoked by an absolute path from elsewhere.
Each invocation creates a new private run directory and preserves older output.
The output filesystem must enforce a user-owned mode-0700 directory; otherwise
the build refuses before copying any private input. A filesystem that ignores
Unix permissions is unsuitable even if it has enough free space. Temporary
package roots and reference extraction use the container's Linux storage;
large archives, images and receipts remain below the selected output parent.

For actual image builds, replace `./reference.bin` with that device's already
qualified private touch reference. Its required size is 5432 bytes and its mode
must be 0600. Kernel builds and dry-run planning need no reference.

```sh
./ukelinux.sh --build image --mode multiboot --filesystem ext4 \
  --desktop kde --channel testing --touch-reference ./reference.bin --out ./out

./ukelinux.sh --build image --mode singleboot --filesystem f2fs \
  --desktop gnome --channel stable --touch-reference ./reference.bin --out ./out

./ukelinux.sh --build kernel --channel testing --out ./out

./ukelinux.sh --build image --mode singleboot --filesystem btrfs \
  --desktop kde --channel unstable --dry-run
```

Parallelism defaults to the host's available CPU count. Use `--jobs 16` or
`--j16` to override it; `--j4` selects four workers. `--linux-size` accepts 8192 through 65536 MiB and
defaults to 16384. The sparse codec has a 64 GiB raw-image bound. Allow at least
64 GiB for kernel/tool work plus three times the selected root size. x86_64
hosts compile the native AArch64 kernel under QEMU user emulation, which can
be slow. No generic ARM64 kernel is substituted.

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

Testing image builds retrieve the latest signed mainline kernel family from
`mcc45tr/uke-linux-test`, verify its signing key, every RPM signature, matching
versions, module hashes and both boot payloads. The exact RPMs and checksums are
retained. These builds use native host package tools and an AArch64 installroot;
on x86_64, scriptlets use an isolated container-local binfmt table and the original
Fedora QEMU interpreter. No host binfmt registration is changed.

Kernel-only builds and the other image channels build the explicit source selected in
[`configs/public-build.json`](../configs/public-build.json). An unstable selection
does not silently replace it with an unported kernel.org release candidate.
Kernel-only output uses that same source/spec and produces both root profiles.
For historical source pins, the builder removes the spec's eight-worker limit
before SRPM generation and retains that exact build-policy diff beside the RPMs.
The cached checkout is restored after source generation; kernel/DT inputs are unchanged.
The stable repository predates the current source families. Stable image builds
therefore also compile `uke-additional`, `uke-sensors`, `uke-hw`, `uke-power`,
`uke-core` and `uke-metas` from the exact public hardware commit in that policy.
Their source RPMs and unsigned local binary RPMs are retained. Only that local
source-build repository accepts unsigned RPMs; remote RPM signatures remain
mandatory. No testing repository is enabled for a stable image.
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
output. The base digest is pinned; resolving live packages when creating a new
worker can still change its contents. Before any build stage, the builder saves
each actual worker under `inputs/worker-<image-ID>.tar`, records archive checksums
and uses that immutable image ID for execution. Identical workers share one
archive. `recipe.SHA256SUMS` binds the copied recipe bytes independently of the
Git commit. Retain these host inputs with the private run directory; they are
not tablet payloads. Worker archives require additional disk space.

The native kernel producer verifies the upstream archive hash, detached
OpenPGP signature, adaptation manifests and boot-source hashes. Its original
Fedora `python3` BuildRequires supports upstream Kbuild on the host only; it is
not copied into the initramfs or installed as a project tablet service.
Source-built local kernel RPMs are unsigned and identified as such. Remote RPM
signatures are verified, and the selected COPR key fingerprint is
checked before import. Original Fedora desktop Python dependencies are admitted
only when their payload bytes match separately signature-verified Fedora RPMs.

Target installation uses all RPM languages; the worker's container language
filter is not inherited. KDE roots must pass the existing native locale-file
audit against every installed RPM's file inventory.

Root installation and every static/dynamic platform BuildRequires pass first
store the resolved DNF5 transaction and its RPM bytes under
`artifacts/transactions/`, then replay that captured transaction with external
repositories disabled. Command-line kernel RPMs are copied into the store as
well. A successful dependency pass with no changes has a `NO_CHANGES` marker.
Each nonempty store has checksums for its transaction and package bytes.
The source-build repository excludes captured dependency packages, so they do
not gain the unsigned local-source exception on later passes.

Stored DNF5 transactions omit the original per-repository key settings. Before
replay, the host helper checks stored bytes and verifies every remote RPM
against the target RPM key database. Only the original local command-line and
`uke-source-build` inputs retain the existing unsigned exception. DNF's later
replay signature pass is disabled after these explicit checks. A missing key,
unsigned remote RPM, changed store or incompatible installed version fails;
no permissive replay option is used. The [DNF5 replay contract](https://dnf5.readthedocs.io/en/latest/commands/replay.8.html)
requires matching package operations and versions.

On 23 October 2026, an isolated Fedora x86_64 SDK test installed a signed remote
fixture and an unsigned local fixture into two empty roots. After removing the
source repository, replay produced matching RPM inventories and payload bytes.
The test also exercises the actual BuildRequires plugin, package replacement
and signature, version, missing-input and duplicate-store refusals. A separate
Podman scratch-image round trip removes the original image, restores its archive
and verifies its exact image ID and payload. These are host fixtures; Docker CI
execution, complete AArch64 worker/root reconstruction and an independent kernel
or release comparison remain open. The manifest keeps
`release_reproducibility_tested: false` until that comparison has a receipt.

`--dry-run` validates choices and prints the plan without installing anything,
creating output or running containers; it does not require `jq`. `--offline`
requires previously prepared worker images, upstream kernel inputs, repository
metadata, package caches and signing keys under the same output parent. A cold
offline run fails. Cache files still undergo the same verification. The script
never substitutes an unsigned download for a missing signed package.

## Device-local inputs

Image builds require the target device's accepted touch reference for first
account setup. A missing reference stops before host preparation. Dry-run
planning and kernel-only builds need no reference. Generic OEM firmware is
installed from the public signed firmware package. Its notices and
redistribution review remain separate from source availability.

Touch startup is conditional on that device's own reference. The required
`--touch-reference FILE` accepts a regular, non-symlink file of exactly 5432
bytes and mode 0600. It is copied only into the local root, and the output
manifest records that private data are included. These checks establish shape
and permissions, not calibration quality or panel compatibility. Use only an
already qualified local CSOT capture. Do not copy another device's reference.
The public probe source is in `uke-sensors/src/touch-normal-probe.cpp`; its
panel/GPIO admission and physical capture acceptance remain prerequisites.
This workflow does not assert that a new device has completed them.

The resulting image contains private data and is only for that device; do not
publish it as a generic image. USB keyboard/mouse setup remains unavailable
until the exact host/VBUS profile passes physical acceptance. A public image
without private touch data still requires that separate input work and is not
provided by this path. File shape/permission checks do not qualify actual
touchscreen account setup. No password, human account, SSH host key or remote root
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

The delivered root starts at the selected raw size. F2FS has an early offline
growth path; current Uke packages also enable the completion-gated
`uke-root-grow.service` for admitted non-F2FS userdata. Physical growth is not
qualified by host image checks. Complete original desktop account setup, then **run
`sudo dnf update --refresh` after the first Fedora boot**. This is required.
A package update does not authorize a kernel slot write; activation remains a
separately guarded operation.

## Validation scope

The public shell fixtures cover all 48 selections, three kernel channels,
invalid input, package-consent refusal, missing-`jq` planning and output paths.
The source change also extends parser fixtures for the explicit Linux profile.
On 23 October, the testing/singleboot/EXT4/KDE image passed original-Fedora helper
and locale audits, full filesystem content and capability/ACL readback, offline
SELinux policy-label verification, and byte comparisons after decoding with
both the project codec and AOSP `simg2img`. A native x86_64 worker executed the
AArch64 package transaction through QEMU. The signed kernel RPMs were retrieved,
not compiled locally. The run used 16 workers and resumed standard stages after
host-tooling corrections. Other image combinations, a clean repeat build, source
kernel compilation, desktop setup, filesystem growth and recoverable tablet
boot remain untested by this run. Historical `core`, `boot` and `boot-pair`
commands remain available for their dated frozen contracts; their old caches
are not prerequisites here.
