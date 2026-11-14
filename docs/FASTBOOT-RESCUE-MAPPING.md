# Logical rescue mapping

14 November 2026. The singleboot container has two fixed roles across all three
liblp metadata slots. Both boot slots must see the same swap and rescue. This
is separate from Android's slot-selected system/snapshot layout.

`src/image/inspect-fastboot-super.sh` uses original Fedora lpdump to validate
all three slots before returning a mapping plan. It checks JSON identities and
the complete text report because JSON omits attributes and extents. The current
producer contract is liblp10.0, 65536-byte metadata, three slots, one4096-byte
physical block device, 1MiB alignment, one default group and one uke_linux group,
two contiguous linear extents with the capacity-derived80/20 roles. There are
no snapshot, virtual-A/B, slot suffix, read-only partition attributes or extra
block devices. Unknown parser/producer format changes fail closed.

The verifier supports full-size regular raw images for host checks and pinned
read-only descriptors for block inputs. Each original-tool invocation has a
time, output and address-space limit. Its temporary reports are removed. AOSP
checksums and fallback-copy handling remain in the original parser. Compact
metadata-description files are refused because lpdump ignores --slot for that
format. Sparse raw fixtures have full logical capacity with less than1MiB
allocated data, allowing actual independent-copy fault tests. Checksums
detect corruption; they do not authenticate a rescue operating system.
For regular raw inputs, the host verifier copies only the exact1MiB metadata
prefix into a sparse file with the original logical capacity. All primary and
backup slot offsets remain intact. This avoids original lpdump scanning GiB of
raw payload under CI resource limits; the producer independently decodes and
byte-checks both complete logical payloads afterward.

`src/image/map-fastboot-rescue.sh` is a demand-only early-boot helper. The
protected caller must first resolve the **unique physical Uke UFS super**.
The lower mapper accepts a block descriptor, verifies all three metadata views,
creates only the rescue extent as read-only dm-linear with an owned UUID, checks
the active table, EXT4 label FEDORA_RESCUE and full allocated filesystem capacity,
then rechecks metadata. It holds a private root-owned lock and refuses an
occupied mapping name. Failure removes only its own mapping; it never writes a
partition, formats a volume, activates swap, changes firmware or repairs root.
It deliberately supports owned loop devices for actual mapping fixtures, so
this helper alone is not the physical-UFS root-admission boundary.

Layout schema 3 puts rescue first to permit growth without relocation. The
normal block mapper accepts ready metadata. Host snapshot inspection can select
a provisioning phase and single slot; that result sets
`three_slot_topology_verified` false. The
[fresh-install provisioner](FASTBOOT-SUPER-PROVISIONING.md) uses these views to
distinguish interrupted growth from a completed installation.

The image producer now requires this topology check after decoding super.img.
The small original-tool metadata suite tests different capacities, reversed
extents with unchanged names/sizes, conflicting third-slot metadata, recovery
from one damaged redundant copy, refusal after both copies are damaged, changed
attributes/groups, virtual A/B and invalid inputs. The mapping fixture prepares
one synthetic sparse4GiB loop device in the disposable Actions VM. It checks a
real read-only mapper, original EXT4 file extraction, rejected writes, unchanged
backing-device hashes, occupied-name preservation and wrong-label error cleanup.
Only small receipts are retained; no physical tablet is attached to that test.

## Remaining boot integration

The helpers are not yet included in the current kernel's embedded initramfs,
and the existing physical-root guard/selector remains intact. The cumulative
kernel queue must integrate them with a versioned mapper-aware root contract,
independent Fedora rescue OS, bounded failure escalation and a qualified
switch-root path. Do not treat a loop mapping as a rescue boot test. Neither
helper establishes the OEM trust anchor, authenticates rescue/kernel bytes,
provides wrapped keys or converts/encrypts userdata. These remain required
before publishing the requested sbfb installer artifact.

## Primary format references

- [AOSP liblp metadata format](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fs_mgr/liblp/include/liblp/metadata_format.h), reviewed blob8d77097ed67b047603d4571e514730ca98b63cf8.
- [AOSP liblp reader and redundant-copy validation](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fs_mgr/liblp/reader.cpp), reviewed blob24ccc0f9de8e5e2f337ebddecabe95785b111f95.
- [Linux dm-linear](https://docs.kernel.org/admin-guide/device-mapper/linear.html).
