# Capacity-independent super provisioning

14 November 2026. Source and disposable-fixture qualification in progress.
No physical UFS write or universal installer acceptance is claimed.

The common ZIP needs a bounded seed and early-boot growth: a full-size super
image for one capacity cannot fill a larger device and also fit a smaller one.
`fastboot_seed_layout` derives the seed from actual rescue input size and a
separately qualified minimum super capacity. It retains 80% swap / 20% rescue
and refuses an input whose seed exceeds that minimum. The minimum is not a
marketed storage size or donor BoardConfig constant. Actual 256-GB geometry
remains an admission input.

Layout schema 3 places rescue/system_b first at the fixed 1-MiB logical start,
followed by swap/system_a. Names and percentages are unchanged. Rescue can grow
in place into the old seed swap without copying its files. Userdata grows
independently. GPT, physical sizes and early firmware are untouched.

## Persistent phases

Original liblp group names record the transaction across three metadata slots:

| Phase | Group | Allocation | Allowed work |
| --- | --- | --- | --- |
| seed | uke_seed | Seed capacity | Begin fresh-install growth |
| growing | uke_growing | Actual capacity | Finish rescue growth and new swap initialization |
| ready | uke_linux | Actual capacity | Verify; repair metadata copies only |

`plan-super-provision.sh` checks each decodable slot against the exact phase
geometry using original lpdump and a bounded prefix snapshot. A single-slot
result explicitly does not attest all three views. A ready view forbids payload
initialization on retry. Ready/seed conflicts, foreign valid layouts and absence
of any recoverable view are refused. Original lpdump's successful empty JSON
response is treated as unreadable metadata.

`provision-fastboot-super.sh --fresh-install DEVICE SEED_LAYOUT_JSON` is the
early-boot layer for an authorized fresh installation. Its protected caller must
select the unique physical Uke UFS super and supply the trusted release's seed
contract. Owned loop devices are accepted for actual fixtures; this lower layer
does not replace the physical selection boundary.

Before its first write it requires an inactive, writable 4096-byte logical
block device without holders, mount or direct swap use. Read-only mappings check
rescue EXT4 identity and seed/target bounds. Old seed swap and target swap are
checked for saved-image/encrypted signatures; those refuse initialization.
Unknown mapper names are preserved.

Original lpmake emits a small metadata description. Original lpflash writes the
growing layout, followed by all-slot readback. Original e2fsck/resize2fs operate
only on the admitted unmounted rescue. Original mkswap initializes the new swap;
last_page must match capacity. Temporary mappings are removed and flushed before
ready metadata is committed. Ready retries never mutate payloads; consistent
ready does not even open the device for writing.

No super image is backed up or copied on the target. Temporary snapshots retain
only the first 1 MiB with sparse logical tails. The helpers do not access
userdata, alter firmware/GPT, activate swap, authenticate an OS or hibernate.

Host composition hashes and decodes complete disposable images. It flushes its
four owned image files and uses original util-linux fadvise to release their
clean page cache before bounded metadata parsing. This is file-specific advice,
not a global cache flush, and does not change parser time/memory limits. A
metadata-prefix snapshot alone does not relieve the producer's previous
full-image cache use. The host parser source reads metadata rather than scanning
all raw payloads; earlier resource-failure attribution to such a scan was not
established. Repeated CI timeouts and memory-limit pressure are recorded as
failures until the corrected whole fixture passes.

## Qualification and remaining integration

Original-tool metadata fixtures test a 4-GiB seed in an 8-GiB container, mixed
seed/growing and growing/ready slots, corrupted copies and previous/foreign
installation refusal. The owned-loop fixture exercises real EXT4 growth, file
preservation, full swap capacity, active-use/saved-image refusal, restarts after
metadata/payload work and a torn final commit. Ready retries must not call
payload tools; a ready no-op must preserve the entire device hash. Injected
process failures and mixed metadata are not physical power-loss qualification.

The cumulative kernel still needs the protected caller, embedded native-tool
closure, mapper-aware root/resume and bounded rescue routing. The installer
needs the Fedora rescue payload, a qualified common minimum capacity, expanded
image fit checks and final fastboot task/parser audit. OEM trust, sealed keys,
encrypted conversion and authenticated hibernation remain mandatory. Initial
userdata is EXT4. The user flashes the final Actions artifact; no Release.

## Primary source review

- [AOSP lpflash](https://android.googlesource.com/platform/system/extras/+/refs/heads/main/partition_tools/lpflash.cc), blob `7ebc042b4007d6707a55e56481ba0f38fe2680f6`.
- [AOSP liblp writer](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fs_mgr/liblp/writer.cpp), blob `2708efa1564b582348ab25a1988b22cc58577f19`.
- [AOSP liblp reader](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fs_mgr/liblp/reader.cpp), blob `24ccc0f9de8e5e2f337ebddecabe95785b111f95`.
- [Original util-linux fadvise](https://man7.org/linux/man-pages/man1/fadvise.1.html) and [POSIX advice semantics](https://man7.org/linux/man-pages/man2/posix_fadvise.2.html).

The host lpflash writer omits some Android device-size checks, so the wrapper
derives and verifies actual capacity. lpflash also attempts to clear block
read-only state: the wrapper rejects read-only devices before invoking it and
never uses that behavior as an override.
