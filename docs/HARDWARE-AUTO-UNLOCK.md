# Hardware-protected automatic unlock

15 November 2026. The primary target is hardware-protected automatic release
during an accepted boot, with the selected password available for recovery.
Userdata and persistent swap/hibernate must share that policy. No hardware key
has yet been generated, persisted or prepared by this work.

## Fitted evidence

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

No parameter change, driver rebind/reset, key operation, mapping, partition or
bootloader write, lock-state change or reboot occurred. No diagnostic was
installed. A TEE version ioctl or trusted-application session was not used.

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

Hardware wrapping alone does not authenticate the OS requesting preparation.
The ioctl argument structures carry no boot measurement. The fitted boot still
reports AVB orange. The required OEM-to-Linux chain, authenticated running
cohort, normal/rescue role policy and fitted firmware binding remain mandatory;
see [OEM trust investigation](OEM-TRUST-INVESTIGATION.md). No current diagnostic
or frontend preference grants storage/key authority.

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
No current boot image or installed module configuration changed.

The updated barrier fixture passed on the separate PC with original Fedora
systemd `262.2-1.fc46` and kmod. It verified the config copy/parser, missing-policy
refusal, generator masks, resume conditions, ordering-cycle refusal and missing
executable refusal without starting a manager or accessing a device/key. This
host result is separate from the native AArch64 key-mechanism qualification
above; embedded first-probe ordering and target operation remain unproved.

Then separately establish wrapped-mode advertisement, hardware-generated key
creation/preparation, cold-boot reuse of the long-term blob, refusal of altered
blobs and encrypted write/read on explicitly owned inactive storage. Storage
selection and independent ownership guards remain pending. A disposable imported
test key can support the upstream ciphertext test methodology while remaining
distinct from the hardware-generated production key.

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
