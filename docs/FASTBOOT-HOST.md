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
