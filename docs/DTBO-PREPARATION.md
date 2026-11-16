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
are retained in the inventory, including the bootloader's dynamic memory
handoff. The 256-GB and 512-GB models have the same DTBO partition capacity;
one common `dtbo.img` is required. Storage capacity does not select another
DTBO or justify a separate overlay build. Source/firmware base ordering is a
separate property and must be checked by payload identities.

The sanitized [reference manifest](../manifests/dtbo-reference-20261115.json)
records exact prefix, payload and base hashes. Raw firmware and decompiled
references remain outside public Git. The manifest is an observation of this
installed reference, not a universal partition-capacity lock.

## Existing kernel contract

### Complete public reference observation,16 November

The public boot cohort at
[`0d2b9c42`](https://github.com/Xiaomi-Pad-7-Pro-Resources/android_device_xiaomi_uke-kernel/tree/0d2b9c42b8e1873e6c7b61326b35c94c991ab713)
contains a complete overlay reference. Its padded file is593920bytes, declared
table length591857 and FDT payload591793bytes. It is a binary reference, not
proof that the previous123-source candidate reproduces the installed overlay.
That earlier candidate still lacks592 nodes and must not be flashed.

A fresh PC inventory applies the signed source7 payload to the same exact
installed base2. It has3602 nodes against4194 in the working graph. Of the
592 missing paths,496 are under the LPASS LPI pin controller; other groups
include audio codecs/clock links, WLAN SMP2P/ICNSS and fingerprint/board pins.
The [gap inventory](../manifests/dtbo-source7-gaps-20261116.json) records the
groups without importing private live FDT or calibration data. The board,
camera and display closure must be extended with these subsystem layers;
successful source7 compilation alone cannot admit a runtime DTBO package.

Independent roundtrip8/COPR11332128 refused byte-exact reproduction: the
overlay recompiles from591793 to591697bytes while its canonical DTC text has
no reported difference. This failed diagnostic admits no payload. Source9
separates serialization from content: it requires identical complete canonical
trees, reservations, boot CPU and all four applied public trees, with wrong
model/CPU/reservation refusals. It reports lengths and byte equality separately
and produces no DTBO transport; a runtime formatter must use the new actual
FDT length. No numeric/phandle heuristic is used in that comparison.
Recovered DTS is distinct from the missing original OEM source closure.
Neither diagnostic admits installed vendor_boot replacement, OEM verification
or a physical write. Only public references are uploaded.

Source9/COPR11332218 failed without a useful stage report. Inspection found
that its negative reservation fixture inserted `/memreserve/` before the
overlay's `/plugin/` header. Source10 places it before the root, after both
headers, and reports the failing stage and bounded compiler diagnostics.
The complete-content assertions and all three refusals remain mandatory;
native execution is still required to establish whether this explains the
observed failure. PC inspection decompiled public input and checked text
placement only, without compiling any DTS.

Original Fedora fdtoverlay applies both the installed and public overlay to
each exact installed base. A bounded private PC data analysis resolves only
the byte offsets declared in `__local_fixups__` and `__fixups__`, using actual
base symbols and provider paths. Every ordinary numeric cell remains raw.
The overlay's seven root selection properties are separately byte-identical.
All four applied graphs match:4209/4206/4194/4196nodes and
20942/20921/20797/20811properties. Each has523 declared reference cells.
The390 raw property differences are276 phandle definitions and114 properties
with relocated references; no semantic difference remains in this comparison.

For every base, five in-memory negative controls reject an ordinary number
matching a valid phandle, a missing property, a reference redirected to another
valid provider, a missing provider node and an out-of-range relocation offset.
Reserved-memory records and the boot CPU identity also match. The
[observation manifest](../manifests/dtbo-public-reference-20261116.json) pins
all inputs, counts and the analysis-program digest. This is PC data evidence,
not a native package/physical/verified-boot admission gate.

All four public base binaries differ from their installed counterparts. The
observation therefore qualifies neither replacing vendor_boot's bases nor
using public bases in the final cohort. Preserve the actual base alternatives,
OEM dynamic RAM handoff and existing once-only Linux transformations. Complete
original source reproduction, attribution, coupled A/B delivery and physical
acceptance remain required before producing the installable DTBO package.

The relocation interpretation follows the
[original DTC object-format documentation](https://android.googlesource.com/platform/external/dtc/+/refs/heads/main/Documentation/dt-object-internal.txt)
and the pinned original libfdt implementation. No generic integer-to-phandle
heuristic, tablet Python, local C compiler or hardware write was used.

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

The next source-cohort candidate pins 123 unchanged inputs (1,599,568 source
bytes) from the exact board, camera, display and kernel releases below, plus
camera-kernel headers at `699fa15a98abd40fbb94f3a6fc00f91723d29d35`.
The [OEM source record](../packaging/dtbo-oem-source.json) preserves each Git
blob, digest and any declared SPDX notice. The DMA-heap binding's original
relative symlink and its in-repository target are retained, as is the input
binding's relative `linux-event-codes.h` link. Unmarked files
are recorded as such; a header's license is not silently assigned to a whole
tree. Original sources and notices accompany the build inputs.

`build-uke-dt-cohort.sh` compiles the four base roots and the selected generic
and Uke-specific camera/display layers. Generic layers enter the four bases;
Uke layers merge with the board overlay. It keeps the observed base order
614/632/643/642, one common v0 DTBO, source board identities and placeholder
memory. It checks complete overlay application to all four bases, repeated
merge identity and rejection when the platform camera layer is omitted.
Compilation remains in COPR. The resulting DTB section is not a complete
vendor_boot image; no bootloader fixup, once-only kernel transformation,
hardware or OEM-trust acceptance follows from this candidate.

The first complete source-cohort build, COPR 11330802, reached native
compilation after both tool fixtures passed, but Fedora DTC rejected the OEM
warning selector `graph_child_address`. Release 5 removes the downstream
warning suppression list and uses Fedora's default diagnostics. OEM sources,
bindings, composition and validation remain unchanged. This failure did not
produce a DTBO or modify a device.

COPR 11330817 then compiled all four base roots before CPP found the missing
input-header symlink. The collector had resolved a relative include through
the link and retained only its target. Release 6 preserves the lexical include
path and original link, with unchanged target bytes. All nine root files pass
bounded PC preprocessing with this closure; native DTC and graph composition
are separate COPR checks. No source or hardware setting was substituted.

COPR 11330826 compiled all nine roots and merged the OEM board, camera and
display layers. The additional source marker used an absolute target path,
which the Qualcomm overlay merger rejected. Release 7 targets the OEM's
existing `chosen` symbol instead. This marker records source provenance after
boot; it is neither a trust anchor nor hardware configuration. The real
platform layers and graph checks remain unchanged.

The board include chain alone is incomplete. Installed entry 0 also contains
the camera and O82 display layers. The corresponding OEM sources are separate:
camera DT `57d2135ee6909ffb7d288a7dc4d82c85d95fc10d` and display DT
`4a3e1c391130237c5e8c2b250d1c94f3e25b9b11`. A static union scan of the board
overlay and four base roots found 71 files with no missing literal include;
that scan neither includes every external hardware layer nor proves the active
preprocessor/build profile. It cannot be used as a complete production closure.

The original OEM `kernel_build` script `android/merge_dtbs.py` at
`e6b1cb8a38fa93564009bbd8116094928c67b876` matches platform, board, PMIC and
Xiaomi board IDs, merges subsystem overlays, rewrites the selected ID sets,
and checks applicable base/overlay combinations. It uses `fdtoverlaymerge` for
overlay-to-overlay composition and `fdtoverlay` for application to a base DTB.
Its source was inspected without executing Python. Its API must not be
replaced by ordinary base-DTB overlay application.

The scoped native merger preparation pins the original Qualcomm implementation
as maintained in LineageOS external/dtc at
`c1197f56b8f468effbbf5e79feae353c4280e2ea`. This is a current host-tool source
comparison, not proof of the exact OEM tool revision. Original Fedora libfdt
does not provide `fdt_overlay_merge`; the isolated COPR host fixture therefore
builds the original private host library and merger without replacing Fedora's
runtime library. No source is patched. The 24 input files, GPL/dual-license
notices and source identity are pinned in `packaging/dtbo-merge-source.json`.
The recipe's generated version header records upstream 1.7.0 and its commit.

COPR [11329537][merge-copr] qualified that unmodified merger natively on the
sole Rawhide AArch64 target in 125 seconds. Synthetic board/camera/display
layers merged successfully; external and local phandles resolved, the board
root metadata and synthetic memory/reserved regions remained intact, and
selected resulting graph relationships matched sequential application.
Repeated merging produced identical bytes. The merged payload packed into
the required v0 container, while omitting the required camera layer prevented
successful final application. No Python or installed firmware input was used.
The formatter's prior fixture and ShellCheck also passed.

The signed `1.0-3.fc46.aarch64` result contains twelve regular receipt/notice
files totaling 82,947 bytes, with no ELF, scriptlet or runtime dependency. The
actual worker/spec, seven project input pins, six native project hashes and
all 39 original upstream hashes matched. Three source archive identities and
both byte-identical original-notice archives were checked against the signed
package. Its RPM SHA-256 is
`d1c180def4ee2bd964ce59fc0c99270512f3cc1c4aa1ca0becf424b54a839609`.
No package or replacement libfdt was installed on the PC or tablet. This
qualifies the host composition tool and scoped synthetic graph checks; it
does not establish an installed Uke source reproduction or hardware acceptance.

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
[merge-copr]: https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/build/11329537/
