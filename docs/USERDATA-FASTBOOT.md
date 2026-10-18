# Fedora userdata fastboot images

18 October 2026 · Xiaomi Pad 7 / POCO Pad X1 (`uke`) · Fedora Rawhide AArch64

These are host-verified test images from the prepared userdata payload. They
still require validated device-local OEM firmware and touchscreen provisioning
before activation. This export does not supply that unfinished provisioning
route or establish a successful tablet boot.

| File | Format and target |
|---|---|
| `userdata.img` | Android sparse v1; expands to a 14 GiB F2FS filesystem labelled `UKE_LINUX` on `userdata` |
| `boot.img` | 96 MiB Android boot v4; kernel 7.2.10-31, `senemos.root=userdata` |
| `SHA256SUMS` | Checksums for the images and accompanying records |
| `manifest.json` | Source commits, original payload metadata, hashes and validation limits |

## Manual flashing

Flashing userdata destroys the existing Android/userdata filesystem and its
user data. Back up needed data and preserve a working recovery/stock boot route
first. Use an unlocked Uke bootloader and current Android platform-tools.
Keep the images on the host. The userdata partition must be at least
15,032,385,536 bytes; the selected boot partition must be at least 100,663,296
bytes. This export does not repartition storage.

Verify the extracted files on the host:

```sh
sha256sum -c SHA256SUMS
```

Inspect the intended slot and capacity before any manual write:

```sh
fastboot getvar product
fastboot getvar current-slot
fastboot getvar partition-size:userdata
```

Check the size of `boot_a` or `boot_b` for that selected slot. After the
device-local provisioning requirement is satisfied, the requested write syntax
from the directory containing these files is:

```sh
fastboot flash userdata userdata.img
fastboot flash boot boot.img
```

With no `--slot` override, `boot` means the current active slot. Confirm that it
is the slot intended for replacement; these commands do not preserve that slot's
existing boot image. They do not select another slot or update both slots.
Do not use `fastboot -w` or format userdata afterwards: that would erase Fedora.
The sparse image explicitly supplies every logical block with RAW/FILL chunks;
it has no DONT_CARE chunks. Fastboot can split sparse transfers according to the
device's reported download limit. The actual Uke transfer remains untested.

## Remaining validation

The filesystem is 14 GiB even on a larger partition. Automatic growth is not
implemented here; the remaining space requires a qualified offline F2FS resize.
Firmware/touch provisioning, actual ABL root-selector forwarding, first boot,
Plasma Setup, hardware operation and Android restoration remain untested.
Secure Boot is off. Automatic kernel activation remains held until the userdata
A/B writer and failed-boot fallback are qualified. Other prepared-root settings
are recorded in `manifest.json`.

The existing C++ sparse encoder was reused without modification. Independent
AOSP `simg2img` expansion must match the original 14 GiB image's exact size and
SHA-256 before export succeeds. No fastboot operation runs in the exporter.
To reproduce from the completed preparation directory, run
`bash src/image/export-userdata-fastboot.sh JOB`; it requires a new `JOB/fastboot`
directory and the verified original delivery. The exporter is host-only.

Format and command references: [AOSP sparse format](https://android.googlesource.com/platform/system/core/+/refs/heads/main/libsparse/sparse_format.h)
and [AOSP fastboot implementation](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fastboot/fastboot.cpp).
