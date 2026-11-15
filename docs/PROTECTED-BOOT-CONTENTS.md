# Descriptor-based boot content verification

15 November 2026. Native qualification passed in [COPR 11329047][qualification]. The existing AVB carrier
authenticates metadata; `protected-cohort-content.cpp` compares the actual
bytes supplied through three open descriptors in boot/vendor_boot/DTBO order.
It is not installed as the protected admission policy and does not release
keys, select a root, write partitions or resume a snapshot.

## Read and ownership contract

The input is a private `VerifiedVbmetaCohort`, the requested A/B slot and three
read-only buffered descriptors. All originals are validated before allocating
duplicates. Each duplicate must preserve the original identity and status.
Aliases, writable, O_PATH/O_DIRECT and special-file descriptors are rejected.
The private, move-only result retains its own close-on-exec duplicates, so a
later pathname lookup cannot replace the verified input. No pathname is opened
by the content verifier. `pread` leaves the caller's shared file offsets intact.

Regular files are inspection fixtures, with length between the authenticated
prefix and slot capacity. The block-device path requires exact observed slot
capacity and a 4-KiB logical sector, using the pinned descriptor's ioctls.
The current regular-file COPR fixture does not qualify that block-device path.
The physical owner must still prove Uke UFS topology, partition labels,
selected slot and write exclusion throughout admission. A read-only descriptor
alone does not prevent another writer; content verification is not a durable
claim that storage cannot subsequently change.

Each 64-KiB chunk feeds both plain SHA-256 and AVB's salted SHA-256. Only the
signed `image_size` prefix is read. Any optional footer or trailer is outside
that prefix and still belongs to the complete flash-file capacity/content audit.
The boot stream also hashes the exact kernel slice in the same pass. There is
no full-image allocation or mapping. Regular-file size/timestamps/identity,
descriptor status and block capacity/sector values are rechecked before return.

Byte counts are limited by the already validated manifest. A 30-second
userspace progress deadline is checked between reads and after validation.
Synchronous kernel I/O can itself block; the enclosing protected unit still
needs its own failure/timeout handling. This layer performs no retry of a failed
digest, no write and no repair.

## Kernel slice

The accepted current Uke layout is [Android boot v4][header], a 1,584-byte
header in a 4-KiB page, with no external ramdisk or signature region. It matches
the existing native boot codec and the forced built-in initramfs architecture.
Reserved fields must be zero and the command line must terminate. Kernel length
must match the signed `kernel_image` record and fit within the authenticated
boot prefix. The [raw ARM64 Image header][arm64] must identify little-endian
ARM64 and a valid bounded memory size. The plain kernel digest covers those
exact kernel bytes, excluding page padding.

These checks establish file/descriptor content equality, not that the running
kernel came from those bytes. Immutable running context, physical slot identity,
OEM root, protected rollback, role/key admission and authenticated resume remain
separate required gates. The inspection CLI reports those as false even after
all content checks pass.

Vendor boot and DTBO are checked against both authenticated digests; this
layer does not parse their formats or establish that OEM firmware accepts them.

## Source fixture

The COPR fixture reuses the existing native boot codec with a small owned
template and a dummy ARM64 Image, then signs the expected contents through
original Fedora avbtool and the existing PSS path. It checks plain, salted and
kernel digests independently; correctly signed malformed headers; FD aliases,
closed/writable/special inputs; partial duplicate-allocation failure; caller
offset preservation and replacement of an already opened pathname. The
inspection-only frontend counts real descriptors on success and exception
exits to catch leaked duplicates.

A single 96-MiB sparse prefix checks that process peak RSS stays below 64 MiB
while the verifier retains a 64-KiB userspace I/O buffer. Kernel page cache is
separate from that process measurement. No fixture boots an OS or uses a
physical partition. Python remains limited to the already documented original
avbtool COPR-host exception; no project Python or target payload is introduced.

Source `3ddf7c2db8b93df8c8ce041b9ed167c348221b87` passed native Rawhide
AArch64 compilation, production-object compilation and all 31 content refusal
cases in 136 seconds. The prior 27 PSS, 64 manifest and 35 AVB refusal cases
also passed. The large fixture verified 100,675,584 bytes with a measured peak
process RSS of 9,928 KiB. Original Fedora hardening/LTO and `-Werror` remained
enabled. These are owned regular-file fixtures, without a block-device ioctl
or tablet boot acceptance claim.

The downloaded signed `uke-protected-cohort-source-check-1.0-7.fc46.noarch`
contains ten license/text/JSON files totaling 24,350 bytes. Its pinned COPR
signature, all 18 source-archive project pins, 43 original libavb file pins,
15 native project hashes, 43 native upstream hashes, both archive identities,
published spec and licenses matched. No ELF, package script or Python/runtime
dependency is packaged or installed on either PC or tablet.

## Owned-loop diagnostic

The `1.0-8` source-check package is an AArch64 diagnostic package rather
than a text-only receipt. It includes the same inspection frontend, the
`owned-block-fixture` test and six public disposable fixture files. No private
signing key, formatter, Python, service or boot hook is included. It is a
temporary test dependency and was removed after the block-I/O evidence was
preserved. It is not the protected admission policy or a production dependency.

The test accepts no device argument. It creates three sparse owned files under
a private `/var/tmp` directory, then attaches them read-only with original
util-linux. Every loop must match the backing inode and filesystem device;
detach repeats those checks and confirms that no backing file remains attached.
An ownership/cleanup failure preserves the work directory for inspection.
At least 1 GiB and 1,024 free inodes must remain before allocation, with an
initial allocated backing limit below 1 MiB. The three loops have 216 MiB of
combined apparent capacity, without copying a physical image. Whole backing
hashes must match after the test, and owned cache pages are discarded afterward.

The checks exercise exact block capacity and 4-KiB ioctls, both
requested slot values, and eight refusals: 512-byte sectors, two wrong
capacities, an alias, a closed descriptor and each of three changed prefixes.
Slot values and signing keys remain fixture inputs. Version `1.0-8` passed
COPR 11329076 on native Rawhide AArch64 in 149 seconds,
including all prior 27/64/35/31 refusal cases and fixture export. Its pinned
signature, 19 project and 43 upstream source pins, 16 native project and 43
native upstream hashes, published recipe, licenses and archive identities
matched. The signed RPM is 111,056 bytes; its 18 regular files total 368,654
bytes, including one AArch64 ELF and one Bash diagnostic, with no RPM scriptlet,
Python dependency or private signing key.

Version `1.0-9` adds the original JSON MIT license and small original-source
archives preserving the complete embedded copyright/permission notices from
JSON headers and the compiled libavb routines. The archives include original
Chromium, Olivier Gay and JSON internal attributions without truncating them.
No provider source is patched. The original Fedora JSON license SHA-256 is
`46a65cffd1ea955132d95a8dd921640714a8d6b537d2e4e482d31145ae95b603`.
The original libavb archive covers exactly 13 compiled C files plus its headers;
the unused Apache-licensed CRC32 implementation is excluded from that notice
archive. All included libavb source bytes match the existing upstream pins.

This package passed [COPR 11329154][blocks-qualification] in 150 seconds,
including all four existing native test groups. Its pinned signature, source
inputs, 22 regular files totaling 514,027 bytes, three added license digests and
both notice archives were checked. The signed RPM is 256,996 bytes. Executable
instructions, read-only constants and relocation tables (`.text`, `.rodata`,
`.data.rel.ro`) match version `1.0-8` byte for byte; original build providers
and runtime requirements also match. No C++ or fixture-test code changed.

The test then passed on the actual Uke `7.3.3-26-unstable` kernel through a
GPG-checked DNF installation. That transaction installed only this diagnostic;
original Fedora dependencies already satisfied the complete transaction. All
eight block refusals passed, with three read-only 4-KiB loop inputs, 81,920
verified prefix bytes and 8,388 KiB process peak RSS. The backing files initially
allocated 16,384 bytes; their whole hashes remained identical. A separate
post-test check found zero owned loops and zero owned work directories. DNF
then removed only the diagnostic, with automatic dependency removal disabled.
The installed helper/assets and matching task RPM cache were absent afterward;
original Fedora providers and integrity lockdown remained unchanged.
That device execution used version `1.0-8`; the license-only `1.0-9` package
was not installed on the tablet. The superseded temporary build 11329076 was
retired after its signed RPM, SRPM, exact sources and runtime receipts were
retained, with `1.0-9` preserving the unchanged diagnostic implementation.

This qualifies the owned-loop block-I/O path, not physical UFS ownership, the
selected boot slot, the running Image, OEM trust, a boot role or key release.
No production initrd or boot profile incorporates this inspection executable.

A separate read-only probe subsequently read 4,160 bytes from each actual boot
partition after checking unique labels, controller ancestry and opened device
identity. Both showed Android v4, 1,584-byte headers, zero ramdisk/signature
lengths, a 69,933,568-byte kernel and a little-endian ARM64 header with
72,613,888-byte memory size. Those measured fields match the reader's current
layout assumptions. This 8,320-byte observation does not compare complete
prefix digests, inspect all header constraints or identify the booted slot.

[header]: https://android.googlesource.com/platform/system/tools/mkbootimg/+/4a27dd13adf9846e12d585d6fe99a375ebb58396/include/bootimg/bootimg.h
[arm64]: https://docs.kernel.org/arch/arm64/booting.html
[qualification]: https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/build/11329047/
[blocks-qualification]: https://copr.fedorainfracloud.org/coprs/mcc45tr/uke-linux-test/build/11329154/
