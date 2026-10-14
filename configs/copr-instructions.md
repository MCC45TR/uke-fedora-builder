For **Fedora Rawhide AArch64** on Xiaomi Pad 7 / POCO Pad X1:

```sh
sudo dnf copr enable mcc45tr/uke-linux-test
sudo dnf install senemos-uke-linux-kernel-mainline
sudo dnf upgrade --refresh
```

The kernel meta package installs matching core, module and device-tree packages.
Keep that set together. DNF installs files; it does not flash `boot_b`, write
Android partitions or change the active boot slot. Kernel ABI directory names
are independent of RPM release numbers and must match the loaded kernel.

Recovery preview delivery is optional:

```sh
sudo dnf install uke-orangefox-recovery
```

Files are installed below `/usr/share/senemos/recovery/uke/`. Read the installed
`DELIVERY.md`, `INSTALL.md`, `release-lock.json` and source offer before testing.
The v003 IMG uses the installed Android boot stack and is not a `fastboot boot`
image. Its ZIP installer is unavailable. Installing or updating this RPM performs
no flashing and does not certify compatibility with the current firmware.

Use Fedora's original KDE applications. Inspect DNF transactions before accepting
changes to runtime libraries; these development builds preserve the upstream
library package names and interfaces. A successful COPR build is separate from
installation, display, touch, charging or hardware-virtualization acceptance.

See the [hardware report](https://github.com/MCC45TR/uke-linux) for observed
support and remaining work, and each COPR build page for source revisions,
dependency versions and logs. Keep a tested recovery route before device trials.

The custom `libstdc++` package targets runtime images. Fedora's compiler and
`libstdc++-devel` packages require their exact Fedora runtime release, so a
mixed development-toolchain transaction is not supported by this selection.
DNF must retain that dependency check; a matching development stack needs
separate packaging and validation.

Automatic rotation and ambient brightness preview:

```sh
sudo dnf install uke-adaptive-display
```

This selects SSC-enabled SensorProxy and native file transport for original
desktop clients. Activation is explicit; installation leaves the integration
target disabled. Matched device-local sensor firmware/configuration and a
read-only factory calibration mount are required separately. Read the installed
`ADAPTIVE-DISPLAY.md` before enabling `uke-adaptive-display.target`. Four-pose
rotation, front-light discovery, lux response and desktop behavior require
physical validation. Raw rear-light readings must not be treated as lux.
