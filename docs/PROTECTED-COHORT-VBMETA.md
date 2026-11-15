# External AVB cohort carrier

15 November 2026. Native qualification passed in [COPR 11328931][qualification].
This layer keeps the signed
manifest outside the kernel/rescue self-reference. `protected-cohort-vbmeta.cpp`
uses unmodified upstream libavb to verify the outer AVB signature and known-key
pin before walking descriptors. It then invokes the existing PSS verifier and
typed manifest consumer on owned property bytes. It performs no mapping, key
release, rollback write or physical boot operation. The protected dracut profile
still requires the missing complete admission policy.

## Original providers

The libavb revision is AOSP
[`ba2dec4b035b0a3b61c5f8f8a74d86bcd450b1ee`][upstream], the `vendor/avb`
gitlink in original android-tools 37.0.0p1. Fedora's avbtool 1.4.0 body matches
that source byte for byte; only its shebang differs. `packaging/libavb-source.json`
pins all 43 upstream file digests and Git blob identities, the license and
original Fedora script digest. The source worker downloads and verifies each
pinned blob, then creates the canonical archive used by RPM. No reference source
is patched. Original upstream C is compiled as C, with its portable SHA/RSA
and POSIX backend. The supplied unsupported ML-DSA backend returns failure;
this profile accepts only SHA256_RSA4096, without replacing a verification
routine or accepting an unsupported algorithm.

The Fedora android-tools package provides the avbtool formatter but no native
libavb development/shared-library API. This narrowly scoped upstream component
is therefore linked into the existing project verifier rather than rebuilding
android-tools or introducing a runtime bridge package. Original C source and
its MIT/BSD attribution are retained in the SRPM. The fixture RPM contains
only license/provenance/test text, without the compiled executables/library.

The host fixture uses **original Fedora avbtool** to encode and sign disposable
AVB images. That formatter is upstream Python; its script SHA-256 is
`87a5708a7e697c13b6b960c6bb5b695aff2689514d552aee0221b56463b0cef8`.
The practical original Fedora producer is this tool; replacing it with a
project format/signature generator would remove the independent upstream
implementation being tested. This is a documented upstream-build-tool
exception on the COPR builder only. Python/avbtool is not shipped or run in
the tablet, initrd or rescue, and no project Python script is introduced.

## Bounded metadata policy

The original [slot loader][slot] caps VBMeta at **64 KiB**, even when the
physical partition is larger. This cap includes all properties, public keys,
hash descriptors and both outer authentication/auxiliary blocks. A 64-KiB
inner signature payload limit does not imply that such a payload fits here.

The consumer copies at most 65,536 bytes into aligned owned storage. It accepts
only a known pinned AVB public key, AVB-1.0-required RSA-4096/SHA-256 metadata,
zero flags, rollback location zero and the formatter's canonical authentication
layout. Reserved bytes, authentication padding and any trailing bytes must be
zero. Descriptor ranges must be inside the authenticated auxiliary block and
disjoint from the public key, with overflow-safe bounds. Header signature
success alone does not validate those policy constraints.

Exactly six descriptors are required:

- `com.uke.protected.cohort`, `com.uke.protected.signature` and
  `com.uke.protected.public_key` properties;
- SHA-256 hash descriptors for `boot`, `vendor_boot` and `dtbo`, with a 32-byte
  public salt, 32-byte digest and normal A/B suffix handling.

Duplicate/unknown properties, extra or unsupported descriptors, command-line
injection, flags, bad terminators and nonzero padding are refused. The consumer
walks every descriptor; it does not use the upstream first-match convenience
lookup. Binary property values are length-delimited, including the 512-byte
inner PSS signature. Every C++ exception is contained within the C callback.

The inner PSS key uses a separate immutable DER-SPKI pin; the outer pin covers
the exact AVB-encoded public key. Neither comes from the candidate. After both
signatures, the existing [manifest rules](PROTECTED-COHORT-MANIFEST.md) bind the
immutable kernel context and exact observed geometry. Each AVB hash record's
image size must equal the corresponding manifest payload size. The private
result exposes const expected parameters; it cannot be default-constructed
or filled with arbitrary bytes by callers.

## Remaining admission

This verifies metadata signatures and their cross-field contract. It does
**not** read actual boot partition contents or establish their physical identity.
The next admission layer must compare actual bytes against both the plain
manifest digest and AVB's salted digest using pinned physical descriptors.
Both hashes cover the exact `image_size` data prefix; an optional AVB footer
or sparse transport padding belongs to the separate complete flash-file audit.
Using an external hash descriptor does not require padding each boot input
to the full physical partition size.
The signed rollback value is returned as a claim; protected stored-state
comparison, OEM trust, hardware keys and actual role authorization remain open.
CLI pins and capacities are test inputs, not a substitute for immutable policy.

The native source fixture uses small dummy images, original avbtool and real
signatures. It tests correctly signed invalid headers, descriptor regions,
duplicates/unknowns, independent key pins, inner-signature/schema mismatches,
the 64-KiB boundary, padding and special-file refusal. It never boots an OS.
No successful source test qualifies the current tablet kernel, a common
256/512-GB installable ZIP or the complete OEM-to-Linux chain.

Source `7cdbe21697b72724d5dc4b8bb65f6370fd85f373` completed the Rawhide AArch64
build in 116 seconds, including the original upstream C library, production
C++ objects and all 35 carrier refusal cases. The prior 27 PSS and 64 manifest
refusal cases also passed. Original OpenSSL 4.0.3, json-devel 3.12.0, GCC 16.2.1
and android-tools 37.0.0p1-2 were used; upstream Python ran only as that COPR
host formatter. Project C++ retained Fedora hardening/LTO and `-Werror`.

The downloaded signed `uke-protected-cohort-source-check-1.0-6.fc46.noarch`
contains nine license/text/JSON files totaling 22,477 bytes, without ELF,
package scripts or a Python/runtime dependency. The pinned COPR key verified
its signature. All 17 project source-archive pins, 43 original upstream files,
11 native project-source hashes, 43 native upstream hashes, both archive
identities and the published spec matched. These are reproducible source and
native metadata-verification results, with the admission limits above intact.

[upstream]: https://android.googlesource.com/platform/external/avb/+/ba2dec4b035b0a3b61c5f8f8a74d86bcd450b1ee/libavb/
[slot]: https://android.googlesource.com/platform/external/avb/+/ba2dec4b035b0a3b61c5f8f8a74d86bcd450b1ee/libavb/avb_slot_verify.c#41
[qualification]: https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/build/11328931/
