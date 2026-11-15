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

The kernel coordinator must qualify the cumulative kernel/initramfs opt-in
before the first ICE probe, preserving existing features, hardening, recovery,
staging and preferences. The initial root remains unencrypted EXT4. Writing
the live module parameter would not rebuild the existing crypto profile;
the mounted-root controller must not be reset to attempt this transition.

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
