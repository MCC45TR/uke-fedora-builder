# Original fastboot parser and capacity requirements

14 November 2026. Host loopback qualification only. No tablet fastboot session,
bootable ZIP, trust-chain or physical installation is accepted here.

AOSP fastboot computes a sparse image's expanded size, but its ordinary flash
path does not first compare every payload with every physical destination.
The device can reject an oversized image after earlier operations. A small ZIP
or sparse file therefore does not provide whole-package capacity admission.

`fastboot-requirements.sh` emits android-info requirements for product Uke,
bootloader fastboot, two slots and all ten physical destination capacities.
Original fastboot checks these before set_active, download or flash. Capacities
are exact alternatives; no wildcards or guessed minimum comparisons. One file
can admit several independently qualified geometries. Unknown formats, missing
values or unlisted capacities fail closed. Accepted spellings use explicit `0x`,
lower/uppercase hexadecimal digits and minimal/8/16-digit widths. Actual OEM
getvar behavior still needs read-only qualification before the final artifact.

The data-only planner now emits these requirements for its supplied geometry.
The final common packager must independently validate every raw/sparse expanded
extent against the smallest admitted destination before generating requirements.
This work does not implement that payload audit, authenticate the metadata or
make an unmeasured 256-GB variant qualified. Do not use --force or disable the
fastboot-info path to bypass admission.

`tests/fastboot-update-parser.sh` runs original Fedora fastboot 37.0.0p1 against
a Bash/socat peer bound only to 127.0.0.1. It supplies synthetic nonbootable bytes
and a genuine original-lpmake sparse super with a 4-GiB expanded extent and under
1 MiB stored size. No USB, physical device, compiler or full image is required.

The same ZIP was parsed for both initial active slots and two synthetic storage
capacities. Ten explicit flash targets appeared in the required order, followed
by normal reboot. A wrong capacity for each destination, a missing late value,
foreign product, fastbootd or a single slot stopped before any mutation. Removing
the requirements reproduced an attempted oversized super flash. The protocol
peer rejected it; this demonstrates the missing host preflight, not real
bootloader flash implementation. The fixture's deliberately permissive fake
boot image is not kernel/header/AVB validation.

The source-contract workflow repeats this native parser fixture in the pinned
Fedora container and retains only a small JSON receipt. Actual tablet parser,
expanded-image audit, source-built boot cohort, independent rescue boot,
hardware encryption, authenticated hibernation and OEM trust remain required.

Primary source review:

- [AOSP fastboot.cpp](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fastboot/fastboot.cpp), blob `1c52da2382ad46759485c2ff096dd660a9c3c999`: requirements, task collection, explicit slots and sparse image loading.
- [AOSP task.cpp](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fastboot/task.cpp), blob `ea78a01b583207dbc4274c6f9da454e160326536`: physical versus dynamic flash tasks.
- [AOSP TCP transport](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fastboot/tcp.cpp), blob `dca306f566636d67ce771d4ff36b3d6f6700f248`: FB01 handshake and big-endian 64-bit packet framing.

The unchanged reviewed files are Apache/BSD AOSP references. Fedora's signed
android-tools RPM supplies the executed binary; no project fastboot fork is
introduced.
