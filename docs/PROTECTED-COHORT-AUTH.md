# Native cohort signature verification

`protected-cohort-auth.cpp` supplies the signature primitive for the future
native initrd admission policy. It uses original OpenSSL EVP APIs, with a
pinned RSA-4096 public key, SHA-256, PSS padding, SHA-256 MGF1 and a 32-byte
salt. It implements no encryption or private cryptographic algorithm.

The caller must supply the trusted SHA-256 of DER SubjectPublicKeyInfo from
its authenticated immutable policy. Reading a fingerprint beside an untrusted
candidate key defeats that contract. This additional signature layer does
not establish the OEM bootloader anchor or solve custom-key enrollment.

The signed bytes start with `UKE-PROTECTED-COHORT-v1` and a newline, followed
by a nonempty payload. Exact signed bytes are bounded to 64 KiB, public PEM
to 8 KiB and the detached signature to 512 bytes. Keys must use exponent
65537. The PEM parser rejects additional keys, trailing non-whitespace and
password requests. Signature parameters are fixed rather than inferred from
candidate data. The separate [typed manifest consumer](PROTECTED-COHORT-MANIFEST.md)
adds schema, immutable kernel context and exact capacity checks. It passed
native COPR qualification separately; a signature over arbitrary bytes is not
role admission.

The byte-span API accepts snapshots directly from a descriptor-owning physical
selector. It returns an owned copy of the verified bytes for later parsing;
the caller must not reopen the original path and parse different bytes.
The snapshot has a private constructor and exposes only const byte/hash access;
callers cannot fill a public structure or mutate its data after verification.
The inspection wrapper uses `openat2` without symlink or magic-link traversal,
rejects special files before reading, bounds regular files and checks file
identity, size and timestamps around the read. It has no weaker path fallback,
subprocess execution, mapping, write, key release or resume operation.

`uke-protected-cohort-source-check` is a temporary COPR source fixture. It
compiles the actual library and its inspection entry on native AArch64, then
checks OpenSSL CLI interoperability, exact size limits and malformed/tampered
input refusal. Private fixture keys are generated in a disposable build
directory and are not installed or published. The resulting noarch RPM
contains only small provenance/test receipts. It is not a runtime bridge
package, an admission binary or a tablet installation candidate.

The inspection JSON deliberately reports semantic admission, role admission,
snapshot authentication and hardware trust as false. The barrier module still
refuses assembly without the real `uke-protected-boot-policy`; this primitive
is not installed under that name. Physical/cohort semantic matching, authenticated
rescue contents, persistent hardware keys, kernel snapshot verification and
the complete OEM-to-Linux chain remain required.

On 15 November 2026, [COPR 11328615](https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/build/11328615/)
qualified source `31e5a0098c7cf90a006eba6505bb07cde68560c1` on
`fedora-rawhide-aarch64` in 72 seconds, including native compilation and the
27 refusal cases. Original OpenSSL 4.0.3 and GCC 16.2.1 were used with Fedora
hardening/LTO and warnings treated as errors. The signed
`uke-protected-cohort-source-check-1.0-2.fc46.noarch` contains only 2,402 bytes
of license and text/JSON receipts; its source hashes, published spec and source
archive were checked against that revision. The preceding release failed at
RPM install ordering before tests ran and is not a passing qualification.

API references: [OpenSSL EVP verification](https://docs.openssl.org/3.6/man3/EVP_DigestVerifyInit/)
and [RSA-PSS](https://docs.openssl.org/3.6/man7/RSA-PSS/).
