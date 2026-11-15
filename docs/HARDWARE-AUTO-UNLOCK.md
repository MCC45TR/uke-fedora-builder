# Hardware-protected automatic unlock

15 November 2026. The primary target is hardware-protected automatic release
during an accepted boot, with the selected password available for recovery.
Userdata and persistent swap/hibernate must share that policy. Disposable
hardware-key generation, preparation and reuse across a normal reboot are now
verified. Production boot-bound release and encrypted storage remain open.

## Current device result

The [signed cumulative kernel27 qualification][kernel27] includes actual
27/A boot acceptance and preserved 26/B recovery. Its forced embedded
initramfs enables HWKM before the first ICE probe. The fitted profile now
advertises hardware-wrapped keys, excludes raw keys and retains 64 keyslots
and AES-256-XTS with 4-KiB units. SELinux Enforcing, automatic staging and
the existing rollback preference remain intact.

The diagnostic generated a disposable hardware key, prepared two copies and
required rejection of an altered copy. A private 128-byte wrapped record then
survived a second observed normal reboot and prepared without regeneration:
one key ioctl, status 0 and 4,744 KiB peak RSS. This is a normal-reboot result;
a physical power-cycle and encrypted data I/O have not been tested.

Two initial record commands returned generic refusals despite a committed
record; the cause remains unresolved. [Diagnostic14][stage-native] adds fixed
failure-stage labels, preserving every ownership and key guard. Its native
49 HWKM and 30 record refusal cases pass. The actual worker, 30 project pins,
27 native hashes, 43 upstream hashes, archives, recipe and both signatures
were audited before signed DNF delivery. On the device, it refused an existing
record at the presence guard, prepared that record and removed it. A separate
new disposable record then completed create/prepare/remove with status 0.
All test-key records were removed; no production key, block or mapping was
written. These later successes do not identify the earlier refusals' cause.

Fresh kernel27 boot configuration still reports secureboot 1 and AVB orange.
Hibernate remains disabled under the existing protection. Trusted key release,
authenticated resume, actual encrypted I/O and data-preserving conversion are
required before enabling production encryption.

## Kernel26 baseline before the opt-in

Read-only SSH inspection of Uke/SM7675 running `7.3.3-26-unstable` found ICE
4.0.2, HWKM v2 and the exact message `Not using HWKM. Supporting raw keys only.`
The parameter `qcom_ice/use_wrapped_keys` is N. Both observed UFS LUNs expose
64 keyslots and `raw_keys=supported`; `hw_wrapped_keys` is absent. The kernel
also reports QTEE version 5.2.0, and original Fedora quic-teec is installed.
These observations do not establish a storage-sealing or KeyMint operation.

The installed ICE module was copied read-only as an 8,380-byte compressed
software reference and inspected on the PC without executing it. The actual
`qcom_ice_create` branches call `qcom_scm_has_wrapped_key_support`, reject a
false result, then check the module parameter before reaching the exact message
observed on this controller. AArch64 branches, relocations and string offsets
match the relevant upstream control flow. This strengthens the inference that
the fitted firmware **advertises** the wrapped-key ABI; it does not prove that
key generation, preparation, persistence or encrypted I/O succeeds.

The corresponding Linux [v7.3.3 ICE source][ice], blob
`e256595b9826f3effa0ec7e85980d01d10079a20`, emits that message only under
`hwkm_version && qcom_scm_has_wrapped_key_support()` when the opt-in is false.
The [SCM source][scm], blob `3eaa4c9ccf3cc7db30257a41a4c2df027349ed52`,
checks all four firmware services: derive software secret, generate key,
prepare key and import key. Availability and successful execution are separate
gates. The source-defined HWKM v2 wrapped blob size is 100 bytes.

Trusted Keys is disabled; OP-TEE and QCOMTEE are configured. Compiled providers
do not identify a sealing service. The generic [Trusted Keys TEE backend][tee]
matches OP-TEE specifically. Enabling that option alone cannot supply a
Qualcomm object-ABI service. Existing Control already links original Fedora
quic-teec for its separately gated accessory client; reuse original providers
where appropriate without creating another runtime hardware bridge.

That initial read-only investigation changed no parameter, controller, key,
mapping, bootloader or lock state and installed no diagnostic. A TEE version
ioctl or trusted-application session was not used at that stage.

## Intended native lifecycle

The existing [block-crypto UAPI][uapi] provides a concrete route:

1. After full admission, use `BLKCRYPTOGENERATEKEY` to generate the production
   storage key in hardware. The raw-key import interface is for separately
   scoped tests, not the primary production path.
2. Persist the returned long-term wrapped blob in qualified readable metadata.
   The durable format, password recovery and interrupted-update transaction
   remain to be implemented and qualified. This is not a plaintext unlock key.
3. At each accepted boot, use `BLKCRYPTOPREPAREKEY` to obtain the per-boot
   ephemerally wrapped form, then pass it directly to the native mapping ioctl.
   Key blobs must not enter command arguments or logs.
4. Require advertised hardware-wrapped keys and the correct 4-KiB encryption
   mode. Upstream [inline encryption][inline] does not support software fallback
   for hardware-wrapped keys; an unsupported operation must remain a failure.
5. Preserve a persistent recoverable key policy for swap/resume. A new random
   swap key each boot cannot recover the previous hibernation image. Snapshot
   authentication and lockdown-compatible resume remain separate requirements.

The wrapped blob can reside on disk while the non-exportable wrapping key stays
inside hardware. ICE keyslots themselves are volatile and are not persistent
key storage. The [AOSP design][aosp] describes this distinction.

Successful storage-key ioctls do not establish which boot identity firmware
authorizes. Their argument structures carry no boot measurement. The fitted boot still
reports AVB orange. The required OEM-to-Linux chain, authenticated running
cohort, normal/rescue role policy and fitted firmware binding remain mandatory;
see [OEM trust investigation](OEM-TRUST-INVESTIGATION.md). No current diagnostic
or frontend preference grants storage/key authority.

The [AOSP KeyMint contract][version-binding] binds keys to the boot verification
key and bootloader lock state, with separate version/patch binding. The fitted
QTEE service, its enforcement and recoverable Linux update behavior still need
qualification; this contract is a research reference, not proof of Uke support.
Normal and rescue boots need distinct admitted roles under that policy.

## Next acceptance

### Native key mechanism

`src/image/hwkm-wrapped-key.cpp` implements the existing Fedora kernel-header
UAPI rather than a private Qualcomm ioctl. `generate_v2` requests a new
hardware-generated long-term wrapped key. `prepare_v2` consumes its long-term
input and returns a distinct per-boot key object. The deliberately narrow
format is the fitted HWKM v2 100-byte blob; other sizes fail. Loading a stored
blob is parsing only and does not authenticate it.

Each operation duplicates an already selected read-only block descriptor with
CLOEXEC, requires 4-KiB logical blocks and uses zeroed reserved UAPI fields.
The native functions neither select a device nor grant boot/role authority.
There is no raw-key import, software fallback or automatic ioctl retry, even
after EINTR: blindly retrying generation could create a different key after an
uncertain outcome. The enclosing transaction must durably preserve the correct
long-term blob before any data conversion or preparation that consumes it.

Move-only key objects use distinct anonymous pages, locked before receiving
bytes, excluded from core dumps and wiped in a forked child. Access from the
child is also refused. The complete page is explicitly zeroed before unmapping
on ordinary completion, response validation failure and syscall failure. This
prevents accidental page sharing between separate locked allocations. There is
no CLI, key serialization, mapping, filesystem conversion or runtime service.

The native COPR fixture links the production implementation with syscall doubles
for block identity, logical geometry and firmware ioctls. Real Linux mapping,
locking, dump/fork flags and fork behavior are exercised. It checks generation
and preparation, consumed inputs, replacement cleanup, five errno paths without
retries, malformed returned sizes/pointers/reserved fields, protection failures,
invalid descriptors and zeroed pages at every intercepted unmap. Synthetic
100-byte values are public fixtures, not hardware-generated keys. The
[native Rawhide AArch64 qualification][native] passed in 163 seconds:
49 refused cases, 49 zeroed unmaps and at most three live key pages. Source
worker, all 26 project source pins, 23 native project hashes, 43 upstream hashes,
source-archive identity and the published recipe match. The signed
`uke-protected-cohort-source-check-1.0-11.fc46.aarch64` RPM was audited with
the pinned COPR key and contains the receipt, preserving the prior disposable
cohort diagnostics; no HWKM executable, package script or Python dependency is
shipped. It was not installed on the PC or target. This fixture cannot establish physical
HWKM operation, persistent reuse or boot binding.

The ABI is pinned to [v7.3.3 UAPI][uapi] blob
`97302c6eb6afec00b454422ee808e6f7e17a4f83`, [block implementation][block]
`bc3a9f59574b12318a7eb0a44610bc55af8f4194`, [ioctl dispatch][ioctl]
`64b4e6c0f696513b8c75bfe49c530dc9cf38eadb` and ICE source above. The block
dispatch does not require a write-open descriptor for these key operations;
the mechanism still requires the caller's prior hardware/boot admission.

### Physical and boot qualification

The disposable record commands are a separate test-only extension:
`--create-disposable-key-record`, `--prepare-disposable-key-record` and
`--remove-disposable-key-record`. Create/prepare require the same fitted
wrapped-only profile before opening the private record directory or making a
key call. They never accept a key path or key bytes in arguments. One fixed
root-owned 0700 directory holds a 0600, single-link, 128-byte versioned record
containing only the disposable long-term wrapped blob. The actual wrapping
key remains hardware-managed; this record is not an export of that key.

An exclusive directory lock and atomic no-replace rename prevent overwriting
an existing test key. File and directory synchronization precede success.
Failed uncommitted writes remove only the owned temporary inode; an uncertain
directory-sync result preserves the committed record rather than generating a
replacement. Stored bytes are read directly into the existing locked key
allocation. Header, length, permissions, ownership, symlink and hardlink checks
apply before use or cleanup. No raw block or mapping is written. This helper
is a disposable diagnostic format, not the production FDE metadata or sealing
policy.

Preparation reports that a stored record was used, but cannot itself prove a
reboot occurred. A separate device procedure must create the record, observe a
real restart, prepare the same record and remove it. A normal restart must not
be reported as a power-cycle test. Neither result establishes authenticated
boot release or encrypted I/O.

The [1.0-13 native record qualification][record-native] passed on Rawhide
AArch64 in 242 seconds: 30 refusal cases, eight zeroed key-page unmaps,
cross-process readback, atomic no-replace behavior, short/interrupted I/O,
precommit cleanup and preservation after an uncertain directory sync. The
previous 49 HWKM refusal/cleanup cases still pass. All five frontend commands
refused the non-Uke worker before key or record operations. The actual worker,
rendered spec, 30 project pins, 27 native project hashes, 43 upstream hashes,
archive identities and both pinned-key signatures were audited. The temporary
RPM contains 32 regular files totaling 1,064,507 bytes and the same three
diagnostic executables; there are no package scripts or Python runtime
dependencies. These results do not establish physical key generation or
cross-reboot reuse.

GPG-checked DNF upgraded only the diagnostic on Uke running kernel 26. The
installed files and frontend digest match the audited RPM. Inspection passed;
exercise, create-record and prepare-record returned 77 with zero key ioctls
under the raw-only profile. Cleanup of an absent record passed. The private
record directory was absent both before and after these commands, all owned
handles were released and peak RSS stayed at or below 6,312 KiB. System health,
SELinux Enforcing, automatic staging and the measured preferences remained
unchanged. This qualifies physical refusal behavior, not hardware generation,
persistence, encrypted I/O or production release.

`hwkm-probe --inspect` reports only bounded fitted UFS crypto capabilities.
`--exercise-disposable-key` is a separate explicit diagnostic: it requires the
existing real-Uke ten-role owner, revalidates the userdata descriptor and UFS
disk sequence/geometry, requires a wrapped-only AES-256-XTS/4-KiB profile, then
generates one disposable key, prepares its two locked copies and tests refusal
of one damaged copy. No blob enters output, a file, a mapping or a volume. An
unsupported current profile returns status 77 with zero key ioctls. Generation
and two preparation successes do not establish ciphertext I/O or persistent
reuse.

The [1.0-12 frontend qualification][probe-native] passed in 173 seconds on
Rawhide AArch64, retaining all earlier native tests. Both frontend modes refused
the non-Uke COPR worker before a key operation. The actual source worker,
27 project pins, 24 native project hashes, 43 upstream hashes, source archives,
published recipe and signed RPM were audited. The RPM contains 28 regular files
totaling 1,061,489 bytes, including the temporary diagnostic; it has no package
scripts or Python runtime dependency.

On Uke running `7.3.3-26-unstable`, GPG-checked DNF installed only this diagnostic,
without a dependency or kernel change. RPM verification and the installed
frontend hash match the audited package. The real ten-role UFS owner and
capability inspection passed: 64 keyslots, AES-256-XTS/4-KiB advertised, raw
keys advertised and hardware-wrapped keys absent. Explicit exercise returned
77 with **zero key ioctls**, correctly refusing that current profile. Peak RSS
was 4,660/4,668 KiB for inspection/refusal; owned descriptors were released.
This is a physical selector/capability/refusal result, not key-generation
success. Kernel 26, module mode N, SELinux Enforcing, healthy system state and
the two measured update-preference digests remained unchanged. No volume,
mapping, firmware, bootloader or key was written, and no reboot was performed
for this test. The small diagnostic remains installed for the next cumulative
HWKM-enabled candidate; its full key-lifecycle, persistence and encrypted I/O
acceptance are still open.

The kernel coordinator must qualify the cumulative kernel/initramfs opt-in
before the first ICE probe, preserving existing features, hardening, recovery,
staging and preferences. The initial root remains unencrypted EXT4. Writing
the live module parameter would not rebuild the existing crypto profile;
the mounted-root controller must not be reset to attempt this transition.

The explicit dracut 96 profile now carries `uke-hwkm.conf`, parsed by original
kmod as `options qcom_ice use_wrapped_keys=1`. Its install function still refuses
assembly when the native boot policy is missing. Copying this configuration is
not enough: the cumulative producer must include it in the **forced embedded**
initramfs, retain `CONFIG_QCOM_INLINE_CRYPTO_ENGINE=m` and the early ICE module,
and qualify the original modprobe/UFS dependency path before the first probe.
The current forced command line does not accept an arbitrary added bootloader
parameter, and a later vendor ramdisk is not a replacement for this integration.
That host-only fixture changed no installed boot image. Kernel27's later
cumulative embedded-image and physical-profile results are recorded above.

The updated barrier fixture passed on the separate PC with original Fedora
systemd `262.2-1.fc46` and kmod. It verified the config copy/parser, missing-policy
refusal, generator masks, resume conditions, ordering-cycle refusal and missing
executable refusal without starting a manager or accessing a device/key. This
host result is separate from the native AArch64 key-mechanism qualification
above; it is not the embedded-image or target proof recorded for kernel27.

Extend the verified lifecycle and normal-reboot result to a physical power-cycle
and encrypted write/read on explicitly owned inactive storage. Storage
selection and independent ownership guards remain pending. A disposable imported
test key can support the upstream ciphertext test methodology while remaining
distinct from the hardware-generated production key.

The original [dm-inlinecrypt documentation][dm-inlinecrypt] explicitly says
cryptsetup cannot create this target. The earlier generic EXT4-to-LUKS loop
test therefore does not qualify ICE conversion. Keep the original Fedora
cryptsetup; production mapping, metadata and interrupted conversion need an
explicit native integration rather than a silent dm-crypt fallback.

Only after these results and boot-policy admission pass should data-preserving
userdata conversion, password recovery, protected swap and authenticated resume
be enabled. Source APIs and driver logs do not mark those behaviors complete.

[ice]: https://github.com/gregkh/linux/blob/v7.3.3/drivers/soc/qcom/ice.c
[scm]: https://github.com/gregkh/linux/blob/v7.3.3/drivers/firmware/qcom/qcom_scm.c
[uapi]: https://github.com/gregkh/linux/blob/v7.3.3/include/uapi/linux/blk-crypto.h
[inline]: https://github.com/gregkh/linux/blob/v7.3.3/Documentation/block/inline-encryption.rst
[tee]: https://github.com/gregkh/linux/blob/v7.3.3/security/keys/trusted-keys/trusted_tee.c
[aosp]: https://source.android.com/docs/security/features/encryption/hw-wrapped-keys
[block]: https://github.com/gregkh/linux/blob/v7.3.3/block/blk-crypto.c
[ioctl]: https://github.com/gregkh/linux/blob/v7.3.3/block/ioctl.c
[native]: https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/build/11329719/
[probe-native]: https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/build/11329763/
[record-native]: https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/build/11330057/
[stage-native]: https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/build/11330110/
[kernel27]: https://github.com/MCC45TR/senemos-uke-kernel-mainline/blob/72270bfc/docs/HWKM-EARLY-QUALIFICATION.md
[version-binding]: https://source.android.com/docs/security/features/keystore/version-binding
[dm-inlinecrypt]: https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/dm-inlinecrypt.html
