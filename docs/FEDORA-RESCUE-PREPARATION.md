# Independent Fedora rescue filesystem

15 November 2026. Source in progress. The output is a rescue filesystem input,
not the final fastboot ZIP or a qualified tablet boot.

The manual source-contract workflow can assemble the AArch64 rescue root from
original Fedora packages and an exact signed cumulative unstable kernel cohort.
All six kernel RPMs pass the existing signature, source/ABI and boot-kernel
identity gates. Only core, modules and DT packages enter rescue through DNF;
the boot updater and desktop stack are unnecessary there. Required generic
Uke firmware is resolved through the existing signed channel. Fitted private
calibration is neither acquired nor copied by this producer.

The requested RPM EVR and source commit are pinned independently. The producer
refuses a different source even if its RPMs have valid signatures. The kernel
metadata profile must remain unstable while both root boot images are checked;
the previous shared loop variable incorrectly replaced it with userdata.

`configs/images/rescue-rawhide.json` selects systemd/udev, the native EXT4,
device-mapper, cryptsetup/keyutils, module and basic diagnostic tools. Weak
dependencies, desktop packages and Python providers are excluded. Before RPM
scriptlets execute, every resolved RPM is independently signature checked,
inventoried and budgeted. Its file list must contain no recognized Python
payload. The subsequent transaction uses only those exact local RPMs with
repositories disabled. The final extracted root passes the existing strict
Python payload audit, including shebangs and ELF dependencies.

The root is independent of userdata. Its fstab mounts only FEDORA_RESCUE read
only, with bounded volatile var/tmp and an 8-MiB journal. Final-root GPT auto,
cryptsetup and resume generators are masked. SSH/network activation and host
key generation are disabled; no generic credential, SSH key or unlock key is
embedded. Original systemd rescue/sulogin remains the console boundary with
the root account locked. This is preparation for authenticated recovery, not
a claim that a locked console already provides the requested repair workflow.

The image size follows the measured root plus margin, aligned to 64 MiB and
bounded to 512 MiB–1 GiB. Original mke2fs populates a regular EXT4 file. The
signed COPR ext4-labels helper applies and verifies original Fedora SELinux
labels; original e2fsck and independent debugfs readback check the filesystem,
fstab and systemd executable. Matching kernel/modules/DT bytes are compared
with the producer inventory, and normal RPM ownership remains in the image.

The worker is a native AArch64 hosted Actions runner with the pinned Fedora
container, two CPUs and 2 GiB RAM. It compiles nothing. A private read-only
proc mount belongs to the container's PID namespace so RPM scriptlets can
reopen their own descriptors. It receives no physical disk, tablet, userdata,
host root tree or host PID namespace. SYS_ADMIN is granted for the private
assembly proc mount; the container is never privileged. The worker marker and
explicit Uke DT refusal prevent accidental tablet assembly. An 8-GiB initial
free-space gate and measured-closure reserve precede expansion. Disposable
roots, package caches and duplicate kernel/boot inputs are cleaned after the
bounded rescue input and receipts have been retained.

Still required before delivery: the protected physical-UFS selector, trusted
seed contract, embedded native closure and versioned mapper-aware root guard;
early rescue routing before resume/unlock; matching source-built DTBO and
vendor_boot; authenticated recovery credentials and operations; OEM boot trust,
hardware-sealed keys and hardware-only conversion; actual ARM64 rescue boot,
USB/input/display behavior and bounded escalation. Masking final-root generators
does not protect an earlier initramfs resume path. No automatic repair, model
download, Release, partition write, relock or reboot is performed by assembly.

The raw rescue input must later pass the common seed calculator and actual
qualified minimum-super capacities. It does not establish a 256-GB geometry
or permit a larger-than-destination sparse image.

Primary references:

- [DNF install and download-only operation](https://dnf5.readthedocs.io/en/latest/commands/install.8.html).
- [DNF installroot and configuration](https://dnf5.readthedocs.io/en/latest/dnf5.8.html).
- [Original systemd volatile-root behavior](https://www.freedesktop.org/software/systemd/man/latest/systemd-volatile-root.service.html).
- [Original systemd debug generator](https://www.freedesktop.org/software/systemd/man/latest/systemd-debug-generator.html).

These are original Fedora/systemd components, not Uke forks. Future native
repair and session integration belongs in existing Control and the coordinated
kernel/initramfs workstream.
