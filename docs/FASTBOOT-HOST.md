# Host fastboot capacity response normalization

On 15 November 2026, Uke ABL returned a leading ASCII space before the correct
`partition-size:boot_a` hexadecimal value. The installation ZIP refused the
response before any payload transfer or slot selection.

Android fastboot 37.0.0p1 trims each requirement option but compares the getvar
response verbatim. Consequently adding a space to android-info does not fix
this mismatch. Its `get_uint_var` helper already trims numeric responses.

The isolated `uke-fastboot-host` package builds only fastboot from the exact
Fedora source archive. Its sole behavior change trims `partition-size:`
response whitespace before the existing exact requirement comparison. It does
not add wildcards, use `--force`, remove capacity requirements or alter firmware.
It installs below libexec and does not replace Fedora android-tools or enter
the tablet root filesystem.

COPR build `11331168` produced `uke-fastboot-host-37.0.0p1-3.fc46.x86_64`.
Its two RPM signatures, source recipe and exact patch were checked before
running the packaged executable. The complete loopback regression passed both
on the COPR worker and with the packaged binary on a Fedora x86_64 PC.

On 15 November, the same initial EXT4/Plasma ZIP passed all fourteen native
requirements on the measured 512-GB Uke. Both requested payloads were written
successfully and reboot was acknowledged in 129 seconds. The Plasma first
account setup screen was observed. Runtime kernel/slot identity, full-capacity
growth and native health acceptance remain separate SSH validation gates.

`scripts/install-fastboot-test.sh` adds five stages, strict archive and host
binary checks, all ten capacity checks, per-piece sparse progress, error
explanations and a final summary. `--check` is read-only; `--install` explicitly
replaces userdata. Temporary extraction uses the ZIP filesystem with a 10-GiB
reserve. Expected optional archive probes stay in the support log; actual
failures remain visible. The tool distinguishes completed flashing from a
verified OS boot.

The original-client fixture demonstrates refusal of correct padded capacities.
The patched-client fixture must accept those capacities and retain refusal of
wrong, missing, malformed and whitespace-only values before any mutation. Both
exercise the real upstream ZIP parser through a loopback-only TCP peer.

The exception is necessary because this response originates in the protected
OEM bootloader, before the Linux kernel or Device Tree can correct it. Return
to unmodified Fedora fastboot when its requirement checker normalizes numeric
responses; retain the regression in the image source checks. Physical USB
flashing and OS boot acceptance are separate from these host fixtures.

Sources: [AOSP requirement parser and numeric getvar handling](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fastboot/fastboot.cpp),
[android-tools 37.0.0p1](https://github.com/nmeum/android-tools/releases/tag/37.0.0p1).
