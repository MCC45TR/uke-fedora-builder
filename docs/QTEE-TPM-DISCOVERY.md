# Bounded QTEE TPM discovery

15 November 2026. Native tests and signed DNF delivery passed. The fitted
firmware refused userspace access to UID81; no TPM or automatic unlock has
been qualified. The accepted kernel27 HWKM results are recorded separately in
[hardware automatic unlock](HARDWARE-AUTO-UNLOCK.md).

## Observed result

COPR [11330412][build16], package `1.0-16`, succeeded in 244 seconds. The
actual source worker, recipe, 36 project inputs, 33 native source hashes,
43 AVB inputs and nine unchanged MINK inputs were checked. Both RPM signatures
match the existing test-project key. The package contains four AArch64
diagnostics, retained fixtures and notices: 46 regular files, 1,295,386 bytes,
no RPM scriptlets, Python runtime or service. The 31 parser refusal cases,
all three reported TPM types and actual Fedora/MINK marshalling tests pass,
along with the retained cohort, 49 HWKM and 30 record refusal cases.

DNF with mandatory signature checking upgraded only diagnostic14 to16 and
changed no dependency. Installed RPM verification and the frontend digest
match the audited package. One actual Uke query completed ordinary userspace
credential registration, then returned status 77 at
`qtee-tpm-service-open`, remote result 11. No service object was obtained;
neither vendor information query nor any TPM2 command was sent. This result
does not distinguish firmware absence from principal/service admission.
The public IClientEnv definition does not establish the fitted firmware's
meaning for this open-method result; its numeric code remains unclassified.

The system remained healthy on accepted27/A with no pending slot change,
SELinux Enforcing and unchanged update/rollback preferences. No diagnostic
process or disposable key record remained. Free space stayed 372,216 MiB on
root and 3,691 MiB in `/tmp`. No reboot, firmware, lock, partition, mapping
or key write was part of this test. Kernel-only discovery, any fitted sealing
service, measured boot and production key-release policy remain open.

## Sources and match limits

Qualcomm's [TPM driver v4 series][tpm] names QTEE service UID81 and UUID
`aabcb593-7083-5536-ac27-3d2d89419ddb`. Its published test target is Glymur-crd,
not Uke/SM7675. Shared QTEE service syntax permits a bounded discovery attempt;
it does not establish that Uke ships or permits access to that service. The
driver depends on the QTEE service-discovery helpers and automatically starts
the TPM when registered. Loading that driver is unsuitable for this diagnostic.

The standalone query uses only the vendor TA-version (`0x1000`) and TPM-type
(`0x80000`) operations, through service method 0 at locality 0. Each request is
four bytes and each response must be exactly twelve bytes. It checks response
status, command echo and the explicit fTPM/dTPM/None values. These are vendor
information operations, not TPM2 Startup, Clear, PCR, NV, transfer or sealing
commands. No arbitrary UID, command, input buffer or TA image is accepted.

Linux 7.3.3 [`qcomtee_root_object_check()`][kernel] reserves operation 5 with
a NULL credential for kernel clients. An unpublished direct-UAPI draft was
rejected before compilation or device execution because it used that path and
incorrectly expected zero flags for a returned TEE object. That route and its
mock are not qualification evidence; the kernel restriction remains intact.

The replacement uses original [MINK adapter][mink] commit
`5e3c6951d13162a262ea65ea8e8351228f092b58`, ordinary client registration
operation 2 and the original Fedora `libqcomtee` credential callback. The
[upstream example][credentials] follows the same registration. Only nine small
unchanged source/header/license files are pinned in
[`qtee-mink-source.json`](../packaging/qtee-mink-source.json). Upstream C and
AArch64 assembly remain in their original languages; the diagnostic is C++.
No library fork, Android userspace, loader or permanent bridge is introduced.

## Qualification and device admission

The COPR candidate retains every prior cohort/HWKM test. A new native fixture
uses the actual unmodified Fedora shared library and MINK adapter, with a
kernel/secure-world double below them. It checks CBOR UID/time, operation 2,
the non-NULL USER credential, TEE output flag 1 and exported-callback release.
A separate fixture tests the production C++ parser with MINK/provider doubles,
all three reported types and malformed replies, transport/permission failures,
wrong devices and object cleanup. Neither fixture contacts firmware.

The device frontend requires root and the existing exact-board/physical-UFS
owner, selects a unique QTEE provider and enforces a five-second process alarm.
The unchanged adapter supports `/dev/tee0`; the selected descriptor and that
protected character node must have identical identity before and after access.
Other provider numbering is refused. The adapter's transient callback workers
exist only during this explicit process; there is no installed service or idle
poll. Successful completion additionally requires the original descriptor
count, physical-owner revalidation and adapter reference-release success.
The adapter's local reference release and context closure are not an
attestation of remote TA teardown.

Only signed COPR RPM/DNF delivery may precede a device query. Discovery refusal
must distinguish credential, service-open, transport and malformed-response
stages. An inaccessible service is not proof that firmware lacks TPM support.
Even a positive type/version response establishes neither measured boot nor
PCR policy, sealing, recovery, automatic unlock or safe enrollment. Those
remain separate qualification gates. No firmware, lock, partition, mapper,
production key or boot-selection change is part of discovery.

[tpm]: https://lore-kernel.gnuweeb.org/linux-integrity/20261019-tpm_qcom_driver-v4-2-6889b9804ba7@oss.qualcomm.com/
[kernel]: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/drivers/tee/qcomtee/call.c?h=v7.3.3
[mink]: https://github.com/qualcomm/minkipc/tree/5e3c6951d13162a262ea65ea8e8351228f092b58/libminkadaptor
[credentials]: https://github.com/qualcomm/quic-teec/blob/736419e25a2036aac3292a10a93e394a90750ca3/tests/common.c
[build16]: https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/build/11330412/
