# Capacity-derived rescue integrity

15 November 2026. The host-only `build-rescue-verity.sh` composes a regular-file
EXT4+dm-verity container from an exact input digest, allocation, filesystem epoch
and public salt. `rescue-verity-layout.sh` computes the largest data area that
fits together with its SHA-256 tree. No GPT or liblp allocation is changed.
Neither script is installed in the current tablet or initrd profile.

For the measured 512-GB Uke allocation, system_b remains 2,255,486,976 bytes:
2,237,857,792 bytes hold EXT4 data and 17,629,184 bytes hold the hash tree.
The geometry uses the whole allocation. Swap's 80% share and the absence of
an /opt partition are unchanged. This is not a measurement of a 256-GB device.

The verity parameters are format 1, SHA-256, 4-KiB data/hash blocks and no
on-disk verity superblock. Hash data starts after the exposed filesystem.
The caller must authenticate every parameter, including block count, offset,
salt and expected root digest. A correct tree does not authenticate the
metadata that selected it. No corruption-ignore or zero-block bypass is used.
See the [kernel's dm-verity interface][verity].

## Repeated growth

`e2fsck` uses `E2FSCK_TIME` for its check timestamp; libext2fs uses
`SOURCE_DATE_EPOCH` (or its legacy fake-time variable) for filesystem writes.
Controlling only the latter produced different whole-image hashes and
different last-check times in a 16-to-32-MiB experiment. The producer scopes
both clocks to filesystem subprocesses. It never changes the system clock.
The epoch is part of the candidate recipe, not inferred later from the device.

The owned-file test grows a 16-MiB input into two 256-MiB containers at different
wall-clock times, crossing an EXT4 block-group boundary. It compares every
byte, reads back a known file, checks the untouched input, and uses original
`veritysetup verify`. Changed data, a changed hash block, a wrong root digest
and a wrong input digest must fail. This is userspace verification, not a
kernel mapping, device boot or authenticated metadata result.

The manual `build_rescue_verity` workflow additionally assembles the original
Fedora rescue on AArch64, formats the supplied real geometry, checks the
original systemd/fstab bytes and SELinux init context, and runs read-only
filesystem checks. It retains the original smaller input and qualification
receipts; the larger derived container is discarded after verification.
The fixed input, recorded epoch/salt, tool versions and source hashes permit
rebuilding the same candidate without retaining duplicate full images.

## Remaining protected seed integration

The current schema-3 physical provisioner grows plain EXT4 and initializes
swap. It does not implement this protected container. Its qualified behavior
must not silently become a verity installer: it lacks the signed parameter
contract, bounded protected mappings and corresponding early policy.

A practical common-seed route is to prepare a complete protected rescue image
for each qualified geometry on the host, compress it, and place it in a signed
seed region beyond every destination rescue extent and swap header. Early
provisioning could stream the selected image directly to inactive rescue,
verify it, initialize swap and commit ready metadata. This avoids a tablet
image file and allows an interrupted stream to restart without depending on
the block placement chosen by an interrupted filesystem resize. Placement,
authenticated compressed/uncompressed lengths, bounded decompression and
restart/ready refusal still require implementation and qualification. Never
replay initialization after a ready view or over active/saved/encrypted swap.

The boot metadata also needs to avoid a self-reference: this Fedora rescue
includes the matching kernel RPM, whose Image embeds the initrd. Placing the
rescue's final digest inside that Image would make it indirectly include its
own digest. Separately signed VBMeta metadata can carry verification data
outside the kernel, as described by [AOSP][avb]. The bounded descriptor
transport, exact cohort binding and full OEM trust anchor remain open. A
replaceable bootloader or an unsigned root-hash record cannot supply them.

Actual 256-GB geometry, authenticated metadata, native protected admission,
kernel/module closure, hardware crypto/hibernate, the final common ZIP and
physical acceptance are not qualified by these host artifacts.

[verity]: https://docs.kernel.org/admin-guide/device-mapper/verity.html
[avb]: https://android.googlesource.com/platform/external/avb/+/refs/heads/main/README.md
