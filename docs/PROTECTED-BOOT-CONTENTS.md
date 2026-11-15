# Descriptor-based boot content verification

15 November 2026. Native qualification is pending. The existing AVB carrier
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

[header]: https://android.googlesource.com/platform/system/tools/mkbootimg/+/4a27dd13adf9846e12d585d6fe99a375ebb58396/include/bootimg/bootimg.h
[arm64]: https://docs.kernel.org/arch/arm64/booting.html
