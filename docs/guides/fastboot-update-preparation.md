# Uke fastboot update preparation

11 November 2026. Preparation only; no installable ZIP or new physical flash
acceptance. Charging reliability remains the immediate device priority.

The next fresh-image delivery is intended for `fastboot update update.zip`.
Use original Android platform-tools and its `fastboot-info.txt` version1
tasks. The plan writes the Fedora Live Recovery image to the existing physical
`super` partition, the fresh system to `userdata`, then matching `vendor_boot`,
source-built `dtbo` and `boot`. It does not resize GPT partitions. The plan's
capacities were read from Uke sysfs; fastboot-side capacities still require
verification. No early firmware or private calibration region is a target.

Plain fastboot update uses the selected slot. The draft flashes one matched
boot/vendor_boot/dtbo cohort and retains the other cohort. An initial userdata
installation replaces shared root data; the other boot slot alone cannot
undo that. Preserve matching rollback modules and the independent rescue
path. Ordinary installed-system updates continue through DNF and existing
automatic inactive-slot staging. Do not pass `-w`: the package supplies the
prepared root image. No flashing command is executed by the planner.

`super` is currently a physical partition of11,274,289,152 bytes with no active
holder observed. Raw EXT4 Live Recovery is the candidate layout, not an accepted
bootloader contract. Confirm original fastboot handling and rescue root
selection before replacing existing dynamic metadata. Do not include
`super_empty.img`, `update-super` or logical-resize tasks in a raw-super plan.
If the fitted bootloader requires a logical container, design that layout
explicitly and qualify the corresponding native recovery mapper instead.

Live Recovery must be reachable both automatically and by a volume-button
request. Define bounded escalation after the existing accepted A/B fallback
policy,including root-unlock failure. Confirm the fitted ABL key/boot-reason
path before selecting Volume Up. If early Linux input is needed,use a bounded
event-driven existing-initramfs helper,not an idle polling daemon. Preserve the
current recovery entry; later add its shortcut to Live Recovery. The Live
root must work without a mountable userdata filesystem and default to
non-destructive inspection. No automatic format,unlimited reboot loop or
new recovery partition size is authorized by this plan. Physical key entry
and automatic fallback remain untested.

A bounded read of both slots found DTBO table version0 with one entry and
592,014 declared bytes,and vendor_boot version4 with37,136,921 vendor-ramdisk
bytes. Only fixed headers/table metadata were read;this does not establish
whole-image equality or acceptance of rebuilt payloads. The new signed cohort
also needs an explicit AVB/vbmeta chain;do not use blanket verification-disable
flags as a secure-boot implementation.

Build the DTBO table from the current cumulative native sources and exact
OEM selection metadata. Preserve both O82 suppliers, entry IDs/revisions,
ABL selection, memory reservations and runtime firmware information. A raw
compiled overlay is not a DTBO partition image. Derive vendor_boot from the
qualified header/DT/bootconfig contract; do not publish a copied private
tablet image or silently use an old template. Kernel, modules, boot DT,
overlays and initramfs must share one pinned cumulative source cohort.

The encrypted EXT4 image must support both FDE and optional per-file FBE.
Use original Fedora cryptsetup/systemd for LUKS2 unlock. The running full18
has UFS crypto/Qualcomm ICE, but disables dm-crypt and fscrypt. Native source56
qualified prerequisites separately; that configuration is not delivered in
full18. Integrate and qualify it before composing an encrypted boot image.
Ordinary LUKS/dm-crypt does not establish UFS ICE use. A separate dm-inlinecrypt
test must prove hardware I/O, key lifecycle and power-loss recovery. The
upstream7.3 interface currently lacks cryptsetup/LUKS integration. Do not
fork cryptsetup or embed shared encryption keys in the archive. TEE/HWKM
wrapped-key boot and recovery remain separate unaccepted work.

Current root-selector-v2 and the boot-image creator accept only linux/userdata.
The initramfs root guard also requires the selected physical filesystem and
rejects mapper roots. Live Recovery on super and encrypted root therefore need
a versioned selector extension,mapper-aware admission and a corresponding boot
image. Preserve the old two-root ABI and its accepted rollback path. Use standard
udev/device events for new discovery and key handling;no healthy idle poller.

`src/image/plan-fastboot-update.sh SOURCE_COMPOSITION OUTPUT` emits the
release plan and proposed original-fastboot task files. It creates no ZIP,
filesystem, payload or device change. Next implement the matched DTBO and
vendor_boot producer, fresh generic rescue/root composition, original unlock
initramfs and checked ZIP export in the existing image tooling package.
Publish only after real artifact, parser, capacity, recovery and boot checks.

Primary references reviewed:

- AOSP system/core `a3b721a32242006b59cb12bd62c9133632af3a2d`,
  [fastboot README](https://android.googlesource.com/platform/system/core/+/a3b721a32242006b59cb12bd62c9133632af3a2d/fastboot/README.md),
  `fastboot.cpp` (BSD license) and `task.cpp` (Apache-2.0). Interface research
  only; no implementation copied. Original Fedora fastboot37.0.0p1 is present.
- [AOSP DTBO table format](https://source.android.com/docs/core/architecture/dto/partitions).
- [Linux7.3 dm-inlinecrypt](https://www.kernel.org/doc/html/v7.3/admin-guide/device-mapper/dm-inlinecrypt.html)
  and the existing kernel storage-encryption source manifest/donor review.
