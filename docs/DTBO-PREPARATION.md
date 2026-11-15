# DTBO and vendor_boot preparation

15 November 2026. Installed references were read without writing partitions.
No new DTBO image or matching vendor_boot has been built or booted. These
references do not establish OEM verified boot or the complete firmware profile.

## Measured input

Both DTBO partitions are 25,165,824 bytes on the measured 512-GB Uke. Their
declared Android DTBO prefixes are identical: 592,014 bytes, table version 0,
32-byte header, one 32-byte entry and a 4,096-byte page-size field. Entry 0
contains 591,950 FDT bytes at offset 64. Its id, revision and four custom fields
are zero. The declared length and payload offset are not page aligned; the
header's page-size field does not itself imply payload padding.

The exact prefix was transferred once, without creating a target-side dump.
The installed vendor_boot v4 header has a 2,128-byte header, 4,096-byte pages,
37,136,921 vendor-ramdisk bytes and a 1,885,877-byte concatenated DTB section
at offset 37,142,528. Only that small DTB section was transferred. Neither the
full 96-MiB vendor_boot partition nor a full fastboot ROM was downloaded.

Bootconfig reports `dtbo_idx=0` and `dtb_idx=2`. Base 2 identifies Cliffs7P,
with `qcom,msm-id=<643 65536>`. This is a reported selection, separate from
authenticated proof of the running slot and boot cohort. Four base variants
are retained in the inventory; another capacity/RAM model must not be reduced
to the current unit's selected base or live memory map.

The sanitized [reference manifest](../manifests/dtbo-reference-20261115.json)
records exact prefix, payload and base hashes. Raw firmware and decompiled
references remain outside public Git. The manifest is an observation of this
installed reference, not a universal partition-capacity lock.

## Existing kernel contract

The installed overlay's root declares:

```dts
model = "Qualcomm Technologies, Inc. Uke based on SM8635";
compatible = "qcom,cliffs-mtp", "qcom,cliffs", "qcom,mtp";
qcom,board-id = <8 0>;
```

These fields agree with the exact OEM source at
[`94c84aeb9e517dbde546fc732033c184094c8e57`][oem-dt], particularly
`qcom/uke-sm8635-overlay.dts`, its `uke-sm8635.dtsi` include chain and the
`CONFIG_ARCH_CLIFFS` selections in `qcom/Makefile`. The installed msm-id list
has the same four pairs in a different order; metadata agreement is not a
claim that this source reproduces the installed binary byte for byte. OEM
file-level licenses and includes must be retained in any source-built closure.

The cumulative kernel at `8fad7a9bc1a3f1b71bb73954f4213bc8b815e964`
already transforms the incoming OEM FDT in `src/boot/uke-abl.c`, starting with
`uke_abl_transform`. It admits the exact model, board and compatible above,
then applies its generated UFS/USB overlays and other qualified native changes.
Display preparation also has variant-specific overlays. A new DTBO must not
preapply those changes and then run the same kernel transformation again.
Changing the root model to the final native model prematurely can instead
skip the transformation. No such root or kernel change has been made.

The preferred first source-built cohort preserves this OEM handoff boundary
and leaves the existing Linux transformations in the kernel. Moving an existing
transformation into DTBO requires an explicit coordinated, once-only contract
and its negative controls. Keep bootloader RAM/reserved-memory fixups, firmware
ownership, panel/PMIC selection and the other cumulative hardware features.
A stock DTB section does not contain all of the bootloader's live fixups.

## Host inspection and producer inputs

`src/image/inspect-dtbo-reference.sh PREFIX DTB_SECTION` accepts bounded regular
files, inventories every table entry and concatenated base, decompiles to
`/dev/null` to walk each FDT, and records only selected board metadata and hashes.
It checks exact declared prefix size, v0 geometry, nonoverlapping ordered
payloads, FDT lengths and unchanged input hashes. It creates at most two
temporary extracted FDT files and removes them on exit, retaining a 256-MiB
free-space reserve. It does not merge overlays, compile DTS, write a device,
produce a new DTBO image or act as the protected boot admission policy.

This host inspection used original Fedora `dtc` and `libfdt` 1.8.1-2.fc45
x86_64 binaries extracted from signature-verified Fedora RPMs. Their signing
fingerprint was `4F50A6114CD5C6976A7F1179655A4B02F577861E`. No distribution
package was rebuilt, no package was installed on the PC and no Python payload
was extracted or run. The current Fedora package release is separate from
this exact recorded tool tuple.

The original [AOSP libufdt tools][aosp-tools] are pinned at
`9b70f594cf149c7c73989c78f03d210f8aa1c1f6`. The native `mkdtimg` producer
supports the required v0 table and explicit page size/id/revision/custom fields.
Upstream deprecates it in favor of `mkdtboimg.py`; the scoped native producer
avoids introducing another host Python tool for this existing v0 contract.
Its original C sources and POSIX sysdeps must remain unchanged and compile in
COPR with original Fedora libfdt. Its `libacpi.h` and `acpi.c` dependencies are
separately pinned from AOSP external/dtc; their BSD-3-Clause notices are preserved
alongside libufdt's Apache-2.0 notices. The source-pin record alone does not
assert native qualification or authorize accepting other table versions.
The scoped `uke-dtbo-tools-source-check` recipe builds those original sources
and checks deterministic v0 output, preserved payload bytes, four synthetic
bases and ten malformed inventory cases. Its RPM contains only receipts and
original notices, with no executable, target dependency or boot hook.

## Native formatter result

COPR [11329504][copr] built source commit
`b505a00` as `uke-dtbo-tools-source-check-1.0-2.fc46.aarch64`, on the sole
Rawhide AArch64 target, in 60 seconds. Original GCC 16.2.1, dtc/libfdt
1.8.1-6.fc46 and ShellCheck 0.11.0 were used. Shell syntax and ShellCheck
passed. The original formatter produced the exact v0 header/entry geometry,
preserved the supplied FDT bytes and produced byte-identical repeated output.
The four synthetic bases were inventoried, all ten malformed inventory cases
were refused, and the formatter refused an invalid FDT. No installed firmware
input or Python was used in this build.

The actual source worker and published spec matched the reviewed recipe.
All five project source pins, the four native project hashes and all fifteen
original upstream inputs matched. The signed result package's source identity
matched both source archives; its original-notices archive was byte-identical
to the audited upstream source archive. The package contains eight regular
files totaling 27,902 bytes, no ELF, scriptlet, service or runtime dependency.
Its signature matched COPR key
`DAFC3C5A881FB49C7167EE2D6F772E3D487BD13E`; RPM SHA-256 is
`9a55e165c724f459ef6b202b95eb40a84c8d9ea9f2c1db442bb8d323e6c6d8df`.
It was not installed on the PC or tablet. This qualifies the scoped native
format producer and synthetic fixture, not a new bootable Uke DTBO image.

## Remaining qualification

1. Qualify the complete OEM DTS/include/source dependency closure and its
   differences from the installed reference, then build the custom board
   overlay with the coordinated cumulative kernel contract. No standalone
   kernel revision is reserved by this preparation.
2. Produce matching vendor_boot with the necessary base alternatives and
   preserved bootloader handoff. Validate kernel-side transformations exactly
   once, including actual RAM/reserved-memory and protected hardware gates.
3. Bind boot, DTBO and vendor_boot to the same signed manifest and VBMeta.
   Define hash-prefix lengths separately from any AVB footer/transport padding;
   check complete expanded files against both slots before any write.
4. Qualify the OEM-to-Linux trust chain, actual capacity variants and independent
   rescue route. Only then compose and audit the requested Actions ZIP and
   proceed to the user's flash and physical acceptance. A format/tool test
   alone cannot establish these properties.

[oem-dt]: https://github.com/MiCode/kernel_devicetree/tree/94c84aeb9e517dbde546fc732033c184094c8e57/qcom
[aosp-tools]: https://android.googlesource.com/platform/system/libufdt/+/9b70f594cf149c7c73989c78f03d210f8aa1c1f6/utils/
[copr]: https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/build/11329504/
