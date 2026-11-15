# OEM trust investigation

On 15 November 2026, read-only inspection of POCO Pad X1 (`xiaomi,uke`,
SM7675, kernel `7.3.3-26-unstable`) found custom AVB key handling in both
installed ABL copies. This is static firmware evidence. Key enrollment,
locked custom-OS boot, tamper rejection and hardware-sealed key release
remain unqualified. The singleboot image must not claim those properties.

## What the installed firmware contains

Each ABL partition is 8 MiB. The two contents differ. Their ELF containers
hold compressed UEFI volumes; extracting only `LinuxLoader.efi` yields
distinct AArch64 PE applications of 1,347,584 and 1,339,392 bytes. A search
of unexpanded ABL bytes can miss this code.

Both extracted applications contain more than diagnostic strings:

- The fastboot flash and erase paths compare the virtual target
  `avb_custom_key` and call the corresponding key-store functions.
- The AVB operation table references a public-key validation callback.
  That callback retrieves the stored user key, compares its length and
  bytes with the proposed signing key, and marks a match trusted and as a
  user key. A separate branch compares an embedded OEM key.
- The store function admits at most 2,048 bytes, copies the key and length
  into device state, and calls the device-state interface. This bound is
  not a recommendation for a particular AVB key algorithm or enrollment.

The detailed address mappings, input hashes, original Fedora tool identity
and selected disassembly stay in private evidence. No firmware bytes are
published or executed. No key/state/partition write, reboot or lock operation
was performed. The transient acquisition tunnel was closed.

These observations supersede any inference that a missing physical
`avb_custom_key` partition or a negative unexpanded string search establishes
absence. A virtual fastboot target does not need its own GPT entry, as
described in the [AOSP device-state documentation][device-state]. The full
OEM command-admission, persistence, rollback and relock contracts have not
been qualified by this static inspection.

## Source comparison and the remaining boundary

The [Qualcomm ABL source mirror][qcom] at
`aef4e86045bd151a54d33bab8ae5e8e62462a8f4` provides a corroborating shared
implementation, not the exact Xiaomi firmware build. This is the revision
selected by [OpenABL's fetch script][openabl-fetch] at
`78b81b585f0f82882e9272cead99e1d395622de5`. Its
relevant contracts are:

| Source | Contract |
| --- | --- |
| `FastbootLib/FastbootCmds.c` | Virtual custom-key flash/erase handlers after command admission |
| `BootLib/DeviceInfo.c` | Store, erase and retrieve a bounded public key in device state |
| `BootLib/LinuxLoaderLib.c` | Device-state operations dispatch through `QCOM_VERIFIEDBOOT_PROTOCOL.VBRwDeviceState` |
| `avb/libavb/avb_ops.c` | Register the callback; accept matching user/OEM keys |
| `avb/VerifiedBoot.c` | Unlocked boot allows verification errors and reports orange; locked user-key boot reports yellow |
| `avb/KeymasterClient.c` | Green/yellow root-of-trust hashing includes signing key and lock state; orange omits the signing key and sends an all-zero public-key digest |

Fresh `/proc/bootconfig` reports `androidboot.secureboot="1"` and
`androidboot.verifiedbootstate="orange"`. The first flag does not prove that
the custom Linux payload is authenticated. The Qualcomm source comparison
also shows why a device-bound key alone is insufficient: an orange-state
release policy does not establish that the requesting OS has the expected
signing identity. The exact fitted KeyMint/TEE policy remains unknown.

Custom-key support in these installed binaries is a useful lead, not an
accepted relock procedure. Preserve OEM early firmware and recovery. Do not
write a trial key, change lock state, invoke firmware state setters, weaken
AVB, or label a replaceable downstream U-Boot as the complete OEM chain.
The shared Keymaster source also contains conditional tamper-fuse operations;
their inclusion is not evidence that they run on Uke and provides no basis
for invoking them.

Before the requested profile can qualify, establish the exact OEM-supported
custom-key/admission and recovery contract, authenticate the entire selected
boot cohort and rescue contents, and demonstrate rejection of a changed
payload through an accepted recoverable procedure. Hardware-sealed key
release additionally needs a fitted TEE/KeyMint binding to that authenticated
identity, user authentication/recovery and persistent protected swap/resume
keys. A successful public-key comparison alone proves none of those runtime
properties. User-login unlock remains the accepted fallback for key release;
it does not satisfy the separate OEM-to-Linux boot-chain requirement.

Source files retain their original notices in a local, ignored reference
subset. They include AOSP MIT, Linux Foundation BSD-style and Qualcomm
BSD-3-Clause-Clear notices; inspect the individual file before reusing code.
No donor script was executed and no ABL replacement was built.

[device-state]: https://source.android.com/docs/security/features/verifiedboot/device-state
[qcom]: https://github.com/CodeLinaro-mirror/la_abl_tianocore_edk2/tree/aef4e86045bd151a54d33bab8ae5e8e62462a8f4/QcomModulePkg
[openabl-fetch]: https://github.com/OpenHandheldCollective/OpenABL/blob/78b81b585f0f82882e9272cead99e1d395622de5/Scripts/fetch.sh
