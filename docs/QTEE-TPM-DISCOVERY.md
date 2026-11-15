# Bounded QTEE TPM discovery

15 November 2026. This is a source candidate, not a fitted TPM or automatic
unlock result. The accepted kernel27 HWKM results are recorded separately in
[hardware automatic unlock](HARDWARE-AUTO-UNLOCK.md).

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
count, physical-owner revalidation and explicit object-release success.

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
