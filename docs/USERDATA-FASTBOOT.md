# Uke userdata test images

21 October 2026 · Uke / SM7675 · Fedora Rawhide AArch64 · original Fedora Plasma.
This private test image includes the firmware and touch data matched to the
current tablet. Do not upload or redistribute the system image. No existing
account, password, SSH key or Wi-Fi connection is copied into the fresh root.

The installed kernel profile is `senemos-uke-linux-kernel-mainline-singleboot`
7.2.11-16. Its exact signed core, modules, DTBs and boot bundle are shared with
the ordinary mainline profile; the singleboot selection targets `userdata`,
while the ordinary profile targets `linux`. The only configured COPR is
`mcc45tr/uke-linux-test`; original Fedora repositories remain available.
Native audio remains disabled in this candidate.

| File | Target and contents |
|---|---|
| `system.img` / `userdata.img` | Identical Android sparse F2FS root image; flash to **userdata** |
| `boot.img` | Android boot v4, kernel 7.2.11-16, explicit userdata root selector |
| `SHA256SUMS` | Image and record checksums |
| `manifest.json` | Exact artifacts, source and validation limits |
| `rollback/boot_b-before-refresh.img` | Read-back backup of the current Linux boot B |

Flashing userdata destroys the existing Android userdata filesystem and user
data. Back up needed files first. The root filesystem is 14 GiB; this test image
does not automatically grow it to the full partition. Fastfetch reports physical
storage separately from the mounted filesystem capacity. Userdata must be at least
15,032,385,536 bytes and boot B at least 100,663,296 bytes. GPT is not changed.
The existing separate `linux` partition is not an installation target.

Use current Android platform-tools and verify the files before manual writes:

```sh
sha256sum -c SHA256SUMS
fastboot getvar product
fastboot getvar current-slot
fastboot getvar partition-size:userdata
fastboot getvar partition-size:boot_b
```

Only after confirming the Uke device, capacities and intended slot B:

```sh
fastboot flash userdata system.img
fastboot flash boot_b boot.img
fastboot set_active b
fastboot reboot
```

Do not run `fastboot -w` or format userdata after flashing: it would erase Fedora.
Boot A is not written, but replacing userdata also removes Android's existing
user data. This is a manual test image, not a recovery-flashable installer.

First boot starts original Plasma Setup. Create the account and connect Wi-Fi.
Root password login is locked and no human account is preset. Plasma Setup
creates an administrator in `wheel`; Plasma Login Manager provides subsequent
logins. All packaged translations, glibc locale data and the selected multilingual
fonts/input methods are retained. Some upstream translations may be incomplete.
SSH starts disabled; enable it locally if remote testing is required:

```sh
sudo systemctl enable --now sshd.service
```

SELinux is enforcing, original firewalld is enabled and nftables tools are
installed. Standalone nftables startup is disabled because firewalld manages the
rules. Signed COPR packages provide sensor startup, Automatic VRR/brightness
defaults, original Fastfetch configuration and F2FS-compatible half-RAM swap
initialization. Actual sensor response, VRR continuity and tablet swap activation
still need physical acceptance of this image.

The selected Control channel is `test`. Future software updates use DNF and
COPR; userdata does not need to be flashed again for ordinary package updates.
`uke-control brunch` supplies explicit channel management. Switching channels
does not bypass signature, matched-kernel or boot-update admission checks.

CDC remains manual through `sudo uke-control set cdc on`. The packaged userdata
updater validates, stages and acknowledges boot trials, but refuses an unqualified
alternate early-firmware cohort. Physical A/B recovery remains unaccepted, and
boot A/B does not roll back the shared root filesystem.
To return to the retained Linux root, restore the saved boot B manually:

```sh
fastboot flash boot_b rollback/boot_b-before-refresh.img
fastboot set_active b
fastboot reboot
```

Host package, filesystem/metadata, sparse decode and boot/Image checks do not
establish physical boot, ABL root-selector forwarding or hardware acceptance.
Recovery installation and filesystem growth are later stages.
