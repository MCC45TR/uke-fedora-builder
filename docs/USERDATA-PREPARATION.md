# Fedora userdata F2FS preparation

Date: 18 October 2026. Environment: Fedora Rawhide AArch64 RPM composition and
offline host/VM validation for Xiaomi Pad 7 / POCO Pad X1 (`uke`). No tablet
installation or new hardware acceptance is established by this recipe.

## Image profile

The new profile is `configs/images/userdata-rawhide.json`. Compose a fresh root
with original Fedora Plasma applications; do not reuse a pruned Alpha root.
It selects Plasma Login Manager, Plasma Setup, Discover's PackageKit offline
updates, all packaged translations, multilingual fonts/input methods and basic
console tools including `clear`. Documentation and weak dependencies are omitted.
Root is locked and there is no ordinary pre-created user. The original Setup
service creates the first account before the display manager starts.

The installed device repository is `mcc45tr/uke-linux`. Its package allowlist
keeps ordinary KDE applications on their original Fedora packages. Candidate
kernel 7.2.10-31 and installation-profile 0.1.0-30 are selected explicitly from
the isolated `uke-linux:custom:userdata-rc1` build results. This does not promote
them to the main channel. Source packages, signing keys and archive hashes must
be retained with the build record.

One kernel Image supports both root profiles. The userdata boot-v4 container
adds `senemos.root=userdata`; the Linux container uses the existing default.
There is no separate `-up` RPM family. F2FS, security labels, xattrs and ACLs are
built into the kernel. The first system boot classifies the actual mounted
physical root, writes the root-owned installation marker and masks its own
oneshot. Login-account changes do not re-run it.

Secure Boot is off. Kernel debug instrumentation, debug packages and development
shell services are excluded or disabled. Existing board handoff settings remain necessary and
are not newly qualified power-management behavior.

## Host stages

The scripts are host automation, not recovery entrypoints. `/job` is a dedicated
container mount of the build directory; `/builder` is this source tree read-only.
Use an AArch64 Fedora DNF SDK for package transactions. On an x86_64 host, run
the SDK through the explicitly selected `qemu-aarch64-static` interpreter.

1. Supply reviewed Fedora 46/COPR public keys, `compose.repo` and the package
   list under `/job/inputs`. Run `compose-userdata-root.sh solve`, then `install`.
   The container RPM macro must request all languages before the transaction.
2. Download the stable device packages with
   `download-userdata-device-packages.sh`. Obtain the exact candidate RPMs from
   COPR builds 11167317 and 11167080. Run
   `install-userdata-device-packages.sh`; it verifies local signatures, pins the
   matching kernel tuple and checks dependencies. Do not install SRPMs or debug
   integration subpackages into the target.
   `uke-ssc-fileservice` and `uke-adaptive-display` are delivered as deferred
   signed RPMs: their real OEM firmware-file dependencies cannot be satisfied
   by the public root. Install them after validated device-local provisioning;
   no dummy provider or dependency bypass is permitted.
3. Run `finalize-userdata-root.sh`. Regenerate hwdb with a recorded native host
   `systemd-hwdb --root=/job/root update`; the emulated tool must not leave an
   empty database. Run `audit-userdata-policy-sources.sh` to prove that generated
   contexts contain only the original Fedora text plus the signed Uke power
   backend's exact file context. Rebuild caches from that proven text with the
   target `sefcontext_compile`. Remove unmounted bootstrap runtime-tree contents;
   the final root does not carry the install transaction's `/dev/null` stub.
4. Run `audit-userdata-root.sh`, `audit-languages`, and
   `audit-userdata-kernel.sh`. The latter compares both boot containers with the
   installed Image, verifies every module digest, extracts the embedded initramfs
   using its System.map and audits the actual extracted payload.
5. Record every installed payload package's origin with `query-userdata-origins.sh`
   in the native host container. The two RPM key records are separate from the
   package count; query-time exclusions must not hide the installed kernel tuple.
   Independently verify original Fedora RPM signatures and extract their payloads
   using `audit-original-fedora.sh`. Byte-check permitted original Fedora Python
   helpers with `src/audit/check-target-payload.sh --original-kde-payload`.
   Project helpers and early userspace remain Python-free. Run privacy checks
   with an exact, proven namespace policy from `review-userdata-namespaces.sh`.
   No unverified path is admitted merely because it looks like a distro example.
6. Only after those checks pass, record `root-audit.complete`. Build the native
   composition initramfs with `prepare-f2fs-vm.sh` and invoke
   `create-userdata-f2fs.sh JOB NATIVE_VM_CONTAINER`. It creates a 14 GiB regular
   F2FS image labelled `UKE_LINUX`, preserves numeric ownership, ACLs and file
   capabilities, applies the target SELinux policy, compares all archived files
   and metadata, explicitly compares capabilities/ACLs with `getfattr`, checks
   labels again and runs fsck. GNU tar's compare mode alone does not detect a
   missing capability; the separate manifest is required. The VM has no network and
   attaches only that newly created regular image, never a host disk.
7. Verify the compressed root and userdata boot payload with the native C++
   checker. Record expanded/compressed sizes, SHA-256, source commits, RPM list,
   key identities and validation limits in the delivery manifest. The Zstandard
   decoder bounds its window to 32 MiB and refuses extra frames and special files.

The GNU/Linux AArch64 checker is not an Android/Bionic executable. A direct
OrangeFox invocation requires a separately reviewed runtime or native recovery
build. Host checks do not establish recovery runtime compatibility.

## Recovery continuation

Delivery at this stage is a data payload, not a flashable installer. It has no
legacy `update-binary` and must not bypass `recovery-uke-ofox` write controls.
The current recovery source has zero accepted live firmware profiles and rejects
legacy ZIP/sideload dispatch. Finish its reviewed native route when that project
is ready, then test both sideload and local-file installation.

Public firmware admission currently contains no OEM firmware. Device-local
WPSS/ADSP/GPU inputs and the three private touchscreen inputs must be provisioned
from a validated source on the same device before activation. They are not
included in the distributable root. Preserve dedicated recovery and stock early
firmware. An installer must reject a source bundle stored on userdata when it
would overwrite that same storage, validate capacity and F2FS compatibility,
resize the new filesystem, verify write readback and record recovery progress.
The payload does not define or authorize a new partition layout.

Automatic kernel installation is held in DNF until the userdata slot writer,
both slot directions, success acknowledgement and failed-boot fallback are
qualified. The current native updater still refuses userdata. Installed
offline-update components do not establish automatic boot-slot updating or
rollback of the shared root filesystem.

After the recovery continuation, validate firmware provisioning, userdata boot,
Plasma Setup account creation, login, application offline updates and recovery
under interruption. Android restoration requires its original boot stack and
Android-compatible userdata initialization; retaining F2FS alone does not retain
Android encryption metadata or guarantee that a subsequent ROM will start.
