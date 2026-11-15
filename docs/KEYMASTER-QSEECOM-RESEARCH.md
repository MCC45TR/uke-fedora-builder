# Resident Keymaster discovery after the TPM refusal

15 November 2026. Research only: no Keymaster diagnostic has been implemented,
built or run. Kernel28's [fitted TPM service-open refusal][kernel28] leaves
the firmware's other key services unresolved. The next candidate should
investigate an already resident application without loading it or changing
its key/boot state.

## Evidence and compatibility

Both fitted ABL LinuxLoader copies contain a QSEECOM Keymaster path. Bounded
static disassembly confirms the `keymaster` application-name reference, a
`0x200` version command, four-byte input and twenty-byte output, followed by
status and major-version checks. The protocol call-table offsets corroborate
the [shared QSEECOM UEFI interface][efi]. Private firmware bytes and selected
disassembly are retained locally. This is static reachability, not proof that
the path ran or that Keymaster remains resident after Linux starts.

The [shared ABL source][abl] at aef4e860 describes the response as five
little-endian 32-bit fields: status, HAL major/minor and application
major/minor. Its ordinary branch uses QSEECOM. The alternative CAppClient/SMCI
branch is conditional on AUTO_VIRT_ABL; its presence does not qualify that
route on Uke. Do not substitute its service IDs for a fitted contract.

The exact [MiCode Uke source][xiaomi] at 5712080a contains a kernel QSEECOM
proxy and handle interface. Those wrappers delegate start/shutdown/send to
an externally supplied provider; they do not supply the complete transport
or a Keymaster TA implementation. The [OnePlus SM7675 source][oneplus] at
1138e00f supplies a useful same-SoC comparison: its load path first checks
application existence, but can then load libraries/apps and service secure
listeners. That full path is unsuitable for non-loading discovery. Its
firmware, application names and policy do not establish Uke behavior.

Linux 7.3.3 [SCM][scm] already offers `qcom_scm_qseecom_app_get_id()` and
`qcom_scm_qseecom_app_send()`. The lookup reports ENOENT for an absent
application and contains no loader. [The client manager][clients] assumes
its applications were previously loaded by firmware. The SCM transport
serializes calls but lacks general incomplete/blocked-listener handling.
Uke's existing RTC integration admits only its measured QSEECOM 0x01402000
profile and returns EOPNOTSUPP for those unsupported callbacks. Retain both
guards; raw upstream code is not the final cumulative implementation.

A separate [Fairphone 3 experiment][fp3] reports version-query success but
blocked key operations with a missing listener implementation. This is a
different SoC and firmware. It is a reason to keep key operations outside
the first experiment, not a working Uke donor or sealing proof.

## Proposed next qualification

Use the actual accepted full28 source, config and every inherited feature.
A candidate kernel-only diagnostic should require exact Uke/SM7675 identity,
the qualified provider/version, root capability and one explicit request.
No added firmware request at probe, load or cached reads; no timer, worker,
polling service, arbitrary name, command or buffer interface.

Start with the fitted `keymaster` name. An absent resident app must stop the
request; do not call a loader, fetch another firmware image or infer another
device's name. A successful lookup permits at most the fixed version request
above, using bounded TZ-memory buffers and normal SCM serialization. Report
lookup, transport, application-status and malformed-reply failures separately;
discard stale/partial version data on failure. Free every owned allocation and
serialize the request with provider removal. The existing synchronous SMC
path supplies no new hard cancellation guarantee: no automatic retry or forced
provider teardown after an uncertain/busy result.

Before a live request, qualify the production parser/lifecycle with refusal
cases and compiler/sanitizer modes in COPR, then compile actual modified
AArch64 objects with warnings as errors. Only the coordinated signed full
kernel, audited RPMs, normal DNF and accepted matching boot may precede a
physical request. No revision29 or source-check115 is reserved by this note.

Do not send key generation/import/use/deletion, entropy, root-of-trust,
boot-state/version setters, milestone, seed, attestation provisioning or
factory-secret commands. Version discovery alone establishes no supported
key-operation listener path, hardware sealing or accepted-boot release policy.
The [OEM trust boundary](OEM-TRUST-INVESTIGATION.md), production wrapped-key
policy, actual encrypted I/O and authenticated hibernation remain open.

[kernel28]: https://github.com/MCC45TR/senemos-uke-kernel-mainline/blob/488db5d7/docs/QTEE-TPM-INFORMATION-RESULT.md
[abl]: https://github.com/CodeLinaro-mirror/la_abl_tianocore_edk2/blob/aef4e86045bd151a54d33bab8ae5e8e62462a8f4/QcomModulePkg/Library/avb/KeymasterClient.c
[efi]: https://github.com/CodeLinaro-mirror/la_abl_tianocore_edk2/blob/aef4e86045bd151a54d33bab8ae5e8e62462a8f4/QcomModulePkg/Include/Protocol/EFIQseecom.h
[xiaomi]: https://github.com/MiCode/Xiaomi_Kernel_OpenSource/blob/5712080a4b0c0b1a879e6d145c601c649ddaddfd/drivers/misc/qseecom_proxy.c
[oneplus]: https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm7675/blob/1138e00fee63582a0cc6a53af3286621786827b7/vendor/qcom/opensource/securemsm-kernel/qseecom/qseecom.c
[scm]: https://github.com/gregkh/linux/blob/v7.3.3/drivers/firmware/qcom/qcom_scm.c
[clients]: https://github.com/gregkh/linux/blob/v7.3.3/drivers/firmware/qcom/qcom_qseecom.c
[fp3]: https://github.com/lawik/qsee_keymaster/blob/129b43de662b7d685727c772d90250c6e58b8583/REPORT.md
