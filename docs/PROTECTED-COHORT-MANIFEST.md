# Signed cohort manifest constraints

15 November 2026. `protected-cohort-manifest.cpp` is the typed manifest layer
after the existing RSA-PSS signature primitive. Native source qualification
passed in [COPR 11328876][native-build]. Neither library is installed as `uke-protected-boot-policy`; the
protected dracut profile still refuses assembly without that complete policy.

The input is the owned `VerifiedCohortBytes` snapshot, including the existing
`UKE-PROTECTED-COHORT-v1` domain line and a schema-1 JSON object. It never
reopens a candidate path. Original Fedora `json-devel` provides nlohmann/json
headers; no project JSON parser, library fork or Python runtime is introduced.
The byte signature covers the exact JSON, so object order need not be canonical.
Parsing uses the original library's [callback API][callback] to reject duplicate
decoded keys before they can be collapsed. Raw NUL, BOM, comments, invalid UTF-8,
trailing input, more than eight levels, 1,024 events or 128-byte string values
are refused. All objects have exact fields and all size values must be unsigned
JSON integers; floating-point, negative and string conversions are disallowed.
The verified-byte class has no public constructor or mutable byte access;
only successful signature verification can construct one. Copying a verified
snapshot preserves that boundary instead of permitting a caller to fill in a
public structure and label arbitrary JSON as verified.

## Contract

The root contains exactly `schema_version`, `platform`, `cohort_id`,
`kernel_release`, `kernel_source_commit`, `payloads` and `geometries`.
Platform is `xiaomi,uke`; kernel ABI must be the cumulative unstable family.
The trusted caller supplies the immutable cohort ID, ABI and source commit.
These cannot come from the candidate or an untrusted command line. Generate
the 128-bit cohort ID before the kernel build and put it in authenticated early
policy. Embedding the Image's own final hash in its initrd would be circular.
That immutable context and the complete OEM trust anchor are not integrated yet.

`payloads` has exactly `kernel_image`, `boot`, `vendor_boot`, `dtbo`, `super_seed`
and `userdata_seed`. Each contains `bytes` and a nonzero lower-case SHA-256.
`kernel_image` denotes the actual kernel payload bytes embedded in the Android
boot image. The boot, vendor_boot and DTBO records cover exactly the raw data
prefix authenticated by their AVB hash descriptor, before any optional footer
or transport padding. Their plain SHA-256 and AVB's salted digest must be
checked over that same prefix. Full flash-file expansion, including any footer,
still requires the independent fastboot before-write capacity check.
Seed sizes/hashes describe expanded raw inputs, not sparse transport encoding.
The boot, vendor_boot and DTBO inputs must fit **both** observed slots;
both seeds must fit **every** listed geometry. Do not add a VBMeta digest here:
VBMeta is the proposed external signed carrier and cannot contain its own hash.
The future producer must make every raw byte covered by a seed digest explicit
in the sparse stream; a DONT_CARE gap cannot guarantee those bytes on a device.

There are one to eight geometries, sorted uniquely by physical super and userdata
capacity. Each contains exactly:

- `super_bytes`, `userdata_bytes`, `logical_block_bytes` (4,096);
- `rescue_start_bytes`, `rescue_bytes`, `swap_start_bytes`, `swap_bytes`;
- `verity`: `data_blocks`, `hash_start_blocks`, `hash_blocks`, `root_sha256`,
  `salt`, `container_sha256`.

The consumer derives the current schema-3 liblp allocation independently:
fixed 1-MiB rescue start, aligned 80% swap/20% rescue and unchanged physical GPT.
It recomputes the largest EXT4 data area that fits with its complete format-1
SHA-256 tree, fixed 4-KiB blocks and no verity superblock. A smaller data area,
overlap, arbitrary offset or corruption-ignore option cannot be signed into
this schema. The public salt may be zero; digest placeholders may not.
All listed geometries must validate, including those not selected at this boot.
Exactly one must match the caller's pinned physical observations. A synthetic
geometry in tests does not qualify a real 256-GB tablet; that measurement is
still required before the common ZIP can be admitted.

## Qualification boundary

The source fixture runs the actual signature primitive before the manifest
consumer, including correctly signed invalid schemas, duplicate/escaped keys,
capacity and both-slot overflows, invalid nonselected geometries, resource
bounds and immutable-context mismatches. The eight-geometry boundary is also
exercised. Every signing key and payload hash in this fixture is disposable.
The existing 27 signature refusal cases remain part of the same COPR build.

Source `224834240b5ccb2992017d6416759db28d928404` passed native AArch64
compilation, library-object compilation and all 64 manifest refusals in 125
seconds on Rawhide. Original OpenSSL 4.0.3, json-devel 3.12.0 and GCC 16.2.1
were used with Fedora hardening/LTO and warnings treated as errors. Both the
measured capacity tuple and synthetic tuple selected correctly; the exact
eight-geometry boundary also passed. No test payload was a real release image.

The downloaded `uke-protected-cohort-source-check-1.0-3.fc46.noarch` signature
was verified with the pinned COPR key. Its six files contain only 3,754 bytes
of license and text/JSON receipts, with no ELF or package script. All eight
native source hashes, all twelve source-archive pins, the published spec and
the archive identity carried by the signed RPM matched the reviewed revision.

The typed result provides parameters for later image hashing and mappings;
it does not perform them. The physical selector, image-content comparison,
authenticated VBMeta transport, OEM anchor/rollback, protected kernel, boot
role, hardware keys and snapshot authentication remain open. The inspection
CLI accepts context and numbers as test arguments and deliberately reports
those authority checks as false. It must never authorize key release or be
renamed to the missing admission policy. A native test result is not tablet
boot or secure-boot acceptance.

[callback]: https://json.nlohmann.me/api/basic_json/parser_callback_t/
[native-build]: https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/build/11328876/
