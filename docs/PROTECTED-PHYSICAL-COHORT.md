# Physical cohort ownership and VBMeta snapshots

15 November 2026. Source implementation; native and target qualification are
pending. This is not installed as the protected admission policy. The existing
dracut module still refuses assembly without that complete policy.

`PhysicalBootDevices` owns read-only descriptors for both boot, vendor_boot,
DTBO and VBMeta slots, plus super and userdata. Its constructor is private and
the type is move-only. Synthetic topology facts can exercise the pure checks
but cannot create this owner. There is no alternate sysfs root, device pathname
argument, environment override, write operation or background monitor.

## Physical selection

The factory requires root and the real sysfs filesystem. The live device tree
must contain both `xiaomi,uke` and `qcom,sm7675`. Original Fedora libsystemd's
[sd-device API][sd-device] enumerates block devices and finds actual parent
devices; no library or distribution provider is rebuilt. All required kernel
`PARTNAME` values are counted globally, including foreign or virtual duplicates.
Each role must occur exactly once. Raw kernel attributes are read through
bounded descriptors, without relying on cached udev properties or last-writer
partition-name links. Unknown event values, including unit identifiers, are
not retained in the result.

Each partition must have a real block-disk parent under the measured
`1d84000.ufshc` platform device and `ufshcd-qcom` driver. Different UFS logical
units are permitted, as measured on this tablet. Names and partition numbers
are derived rather than fixed. Kernel names, devnums, parent capacity, partition
start/length, 4-KiB sectors and disk generation must agree. Whole-disk aliases,
duplicate devnums, overlaps, inconsistent parents and unsupported sizes refuse.

Every device opens directly below `/dev` with `openat2`, forbidding symlinks,
magic links and path escape. `BLKGETSIZE64`, `BLKSSZGET` and `BLKGETDISKSEQ`
must agree with the observed kernel attributes. Sysfs directory handles and
block handles remain owned together. A fresh independent catalogue and inode,
capacity and generation checks run before returning and around content
inspection. A successful match describes the trusted kernel's device view;
it is not an OEM attestation and a read-only descriptor does not exclude another
writer.

Enumeration is bounded to 1,024 block entries and parent walks to 32 levels.
Attribute reads have explicit limits and a progress deadline. As with the
content reader, synchronous kernel calls need the enclosing unit's independent
timeout/failure handling. There is no automatic retry or alternative device.

## Metadata and content

The new `verify_vbmeta_cohort_fd` primitive validates a supplied read-only
buffered descriptor, duplicates it with close-on-exec and retains that handle
in a private move-only result. Its observed container capacity must be aligned
and between 64 KiB and 1 MiB. A block input requires exact ioctl capacity and
4-KiB sectors; equal-sized regular files are test fixtures. It reads exactly
the first 64 KiB with `pread`, preserving the caller's offset, then invokes the
existing original-libavb/PSS/manifest validators on owned bytes. Identity,
timestamps, descriptor status and capacity are checked again afterward.

The complete 64-KiB prefix is part of this input contract. Producers must
explicitly zero-pad a smaller VBMeta image to 65,536 bytes, for example with
original avbtool's `--padding_size 65536`. This prevents stale bytes within
that prefix from breaking the existing zero-tail rule. A larger physical
partition does not extend libavb's metadata limit; bytes beyond the prefix
are outside this reader. The independent flash gate still checks the complete
expanded flash file against both physical destinations.

`inspect_physical_boot` consumes the physical owner, verifies the requested
slot's VBMeta descriptor, compares all three boot-content prefixes and the
kernel slice, then revalidates the physical catalogue. Its result retains all
physical, metadata and content descriptors. No pathname is reopened to read
metadata or boot contents. The requested slot is an inspection input and does
not prove which slot supplied the running Image. Identical images in both
slots are valid for the requested initial installation.

## Qualification and remaining authority

The pending native fixture covers four pure layouts, 40 invalid topology
observations, eight invalid compatible lists and refusal of the non-target
COPR host. Synthetic facts never construct the physical owner. The signed
regular-file fixture adds 14 descriptor/snapshot refusals, offset preservation,
pathname replacement, zero-tail bounds and cleanup. The owned-loop diagnostic
will also exercise a separate 128-KiB metadata block input with five refusals.
These remain planned checks until their actual results are recorded.

The inspection frontend offers `--identity-only`, `--inspect-slot` with explicit
test pins/context, and `--fixture-vbmeta-fd` for owned descriptor tests. It grants
no root role, hardware key or resume permission. Full OEM root, protected
rollback, authenticated immutable running context, write exclusion, booted-slot
identity, kernel DM-verity/noresume closure, protected seed and crypto/resume
integration remain the complete policy's obligations. Original Fedora providers
and the current kernel/profile are unchanged by source work.

[sd-device]: https://www.freedesktop.org/software/systemd/man/latest/sd-device.html
