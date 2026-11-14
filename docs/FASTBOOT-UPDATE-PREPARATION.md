# Singleboot fastboot delivery

14 November 2026. Implementation in progress. This supersedes the 11 November
draft that assigned all of super to rescue and wrote only one boot slot.
No installable ZIP or physical acceptance is asserted by plan generation.

The requested delivery is:

```text
fastboot update fedora-rawhide-linux-kde-plasma-uke-senemos-sbfb-141126.zip
```

`sbfb` denotes the requested secure-boot/fastboot profile. The suffix is
**DDMMYY**, explicitly confirmed for this profile. A filename cannot establish
that secure boot is enforced; the completed artifact must pass that separate
admission before it can be offered as the requested installable profile.

## Storage contract

Keep the physical GPT and every physical partition size unchanged. Use the
existing super partition as a **liblp container**, allocating its usable,
aligned extents 80% to swap (`system_a`, label `linux_swap`) and 20% to an
independent Fedora rescue (`system_b`, EXT4, label `FEDORA_RESCUE`). There is
no separate `/opt` partition. The main Fedora EXT4 root stays in userdata.

The names system_a/system_b are logical partitions inside super, not separate
GPT storage. The three current Android metadata slots describe different
historical layouts and overlapping storage; their reported sizes cannot be
added together. The new installation creates one consistent two-role layout.
It must not put a raw EXT4 filesystem over the outer super container.

Calculate sizes from the actual device capacity, reserving liblp geometry,
primary/backup metadata and alignment. The measured 512-GB tablet has
11,274,289,152 super bytes. The current calculator assigns 9,017,753,600 bytes
(8600 MiB) to swap and 2,255,486,976 bytes (2151 MiB) to rescue, with the
remaining 1 MiB reserved for aligned metadata. This is an example, not a
capacity constant for other variants. Original lpmake/lpdump first round-tripped
the compact metadata description with these sizes. That compact format contains
one serialized view, so passing --slot does not prove independent slot copies.
The later full-container and sparse raw-fixture tests check the actual three
views, including deliberate disagreement and corrupted-copy recovery.

Initial delivery writes matching boot, vendor_boot, DTBO and vbmeta to both
slots. Existing early firmware, persist, modem identity/calibration and GPT
remain outside the write set. Returning to Android requires the correct stock
super and matching stock boot/vendor_boot/DTBO/vbmeta cohort; unchanged GPT
geometry avoids a repartitioning requirement. This is a restore path to
qualify, not a claim that retaining Android's old data is possible.

After mapping the logical partitions, grow rescue EXT4 to its allocated
capacity and initialize/use the complete allocated swap device. Grow userdata
EXT4 to its physical capacity, retaining the independent capacity gate. Do not
grow an inner filesystem across a logical-partition boundary. Swap must not
expose decrypted user data after encryption is selected; its key lifecycle
needs an independently qualified inline-crypto path.

## Encryption and key release

Offer encryption once after the first human desktop login. Declining closes
the dialog. The user permits rebooting to independent rescue for operations
on the mounted root; conversion must preserve existing files and be recoverable.
The primary key goal is hardware-bound automatic release tied to an accepted
verified boot, with the chosen password available for recovery. If that cannot
be supplied, unlocking at user login is the explicitly permitted fallback.
Never put a shared/plaintext unlock key in a generic image.

Two separate native checks ran on 7.3.3-26-unstable:

- A read-only dm-inlinecrypt mapping read one 4096-byte data unit. The UFS
  queue advertised AES-256-XTS/4096, 64 keyslots and raw-key support; a private
  function trace observed one Qualcomm ICE key-programming call. No partition
  was written. Software-fallback exclusion, encrypted writes and key recovery
  were not established by this read test.
- Original Fedora cryptsetup 2.8.8 converted an owned 64-MiB loop file containing
  a 48-MiB EXT4 filesystem to LUKS2. Sentinel and random-file checksums survived
  read-only reopen. This establishes the bounded offline conversion path,
  **not** UFS hardware encryption. Scratch mappings, files and keys were removed.

The running queue does not advertise hardware-wrapped keys and TRUSTED_KEYS is
disabled. This is the current configuration, not proof that the silicon lacks
HWKM. The upstream ICE driver has a wrapped-key mode requiring qualified
initialization/key lifecycle; do not toggle storage ownership/mode on a live
mounted root. A TEE device node alone is not a sealing service.

Upstream dm-inlinecrypt currently lacks original cryptsetup/LUKS integration.
Ordinary cryptsetup/dm-crypt conversion does not satisfy hardware-only bulk
crypto. The native mapper/key/reencryption integration, wrapped-key provisioning,
recovery, power-loss behavior and hardware write/read path remain required.
fscrypt alone cannot encrypt an existing EXT4 root in place; it applies policies
to empty directories. Preserve both the block- and file-encryption open scope.

## Secure boot, DT and recovery

The user explicitly requires the complete OEM-to-Linux trust chain, with no
risky stock bootloader modification. Downstream-only U-Boot verification is
insufficient. The live early-firmware secureboot flag is 1 but Android's boot
state is orange; this does not establish authenticated custom-OS boot.

The requested secure boot requires a protected trust anchor, signed boot
payloads, an enforced verification path and rejection of a tampered payload.
RPM signatures, module signatures, FIT signatures and an enforced device root
of trust are distinct. U-Boot verified-boot source explicitly requires its key
and first-stage verifier to be protected. A signed but replaceable U-Boot does
not close that chain. Do not relock stock ABL without an accepted custom-key
contract, or pass blanket AVB verification-disable flags.

Build DTBO and vendor_boot from the qualified cumulative source/board selection,
including fitted suppliers, table IDs, reservations, bootconfig and handoff.
Do not publish a private tablet dump or treat a compiled overlay as a complete
DTBO partition image. Preserve all cumulative kernel features and admitted
firmware ownership refusals. Current root guard/selector and early mapper need
the independent logical rescue and encryption contracts before delivery.

Enable seamless inactive-slot updates by default in the new image. The initial
kernel is an automatically accepted baseline on successful root entry; critical
boot/root failure must still enter rescue. Bound failure escalation and keep
rescue usable without userdata. Recovery defaults to diagnosis, with explicit
review before repair/destructive operations. A small local model is optional
and must not displace essential recovery functionality or resource reserves.

## Source tools and next admission

`src/image/fastboot-singleboot-layout.sh` calculates layout and validates names.
`scripts/check-fastboot-super-layout.sh` tests original liblp using a metadata-
only file smaller than 1 MiB, without images or block writes.
It verifies the serialized description, not three independent physical copies.

[Logical rescue mapping](FASTBOOT-RESCUE-MAPPING.md) describes strict all-slot
topology validation and the demand-only read-only mapper. Original lpdump JSON
alone omits extents, so equal partition names/sizes are insufficient admission.

`src/image/build-fastboot-super.sh` is the host-only container producer. It
accepts a calculated layout and an independent raw EXT4 rescue input, then
formats full-size swap, grows the copied rescue filesystem and builds sparse
super with original lpmake. Original simg2img/lpunpack decode both payloads;
checksums, all three metadata slots, swap last_page and EXT4 block counts must
match. Inputs and outputs must be regular files, the destination must be new,
and a conservative four-container peak plus 2 GiB and free inodes are required.
This producer does not supply or qualify the rescue OS or its boot path.

The `logical-container` source-contract job runs a synthetic 4-GiB fixture
using original Fedora tools in the pinned container, with 2 CPUs/2 GiB RAM.
It independently reads the original files back through EXT4 tools, checks
failure paths and keeps only small receipts. It compiles no source and writes
no block device. This is separate from the final OS image/ZIP build.

```text
src/image/plan-fastboot-update.sh SOURCE_COMPOSITION GEOMETRY_JSON NEW_OUTPUT [DDMMYY]
```

The geometry JSON has `product: "uke"` and a `partitions` object containing
positive byte capacities for super, userdata and both boot/vendor_boot/DTBO/
vbmeta slots. Plans record the supplied evidence; actual fastboot-side capacity
and trust checks still precede an installer artifact. The planner emits only
data/task proposals, never a ZIP, flash command execution or encryption action.

The remaining producer work includes full swap/rescue/userdata composition,
the native early logical mapper and key path, source-built DTBO/vendor_boot,
enforced boot verification, first-login UI, guarded conversion, matching kernel
delivery and actual fastboot parser/artifact validation. Build compilation in
COPR and compose through existing workers. Download the final Actions artifact
for inspection. **Do not publish a GitHub Release; the user performs flashing.**

The public image entry now accepts explicit `--kernel-profile unstable` with
`--channel unstable` on Rawhide repository images. This selects the cumulative
`senemos-uke-linux-kernel-mainline-unstable` family, verifies all six signed RPMs
and requires its signed source composition to bind RPM EVR to the `-unstable`
ABI. Normal and EL2 families cannot substitute for it. Source-build options
are refused for this profile; full cumulative compilation remains in COPR.
This image selection does not itself qualify rescue, encryption or secure boot.

## Primary references

- [AOSP dynamic partitions](https://source.android.com/docs/core/ota/dynamic_partitions/implement)
- [Original fastboot task format](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fastboot/README.md)
- [DTBO partition tables](https://source.android.com/docs/core/architecture/dto/partitions)
- [U-Boot verified boot](https://docs.u-boot.org/en/latest/usage/fit/verified-boot.html)
- [Android device state and optional user trust](https://source.android.com/docs/security/features/verifiedboot/device-state)
- [Xiaomi bootloader FAQ](https://www.mi.com/global/support/faq/details/KA-07238/)
- [U-Boot FIT verification](https://docs.u-boot.org/en/latest/usage/fit/signature.html)
- [dm-inlinecrypt](https://docs.kernel.org/admin-guide/device-mapper/dm-inlinecrypt.html)
- [Inline encryption](https://docs.kernel.org/block/inline-encryption.html)
- [fscrypt](https://docs.kernel.org/filesystems/fscrypt.html)
- [Trusted keys](https://docs.kernel.org/security/keys/trusted-encrypted.html)
- [Hardware-wrapped keys](https://source.android.com/docs/security/features/encryption/hw-wrapped-keys)
- [cryptsetup reencryption](https://man7.org/linux/man-pages/man8/cryptsetup-reencrypt.8.html)
