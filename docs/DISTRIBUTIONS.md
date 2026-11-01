# Distribution backend status

Source interface status on 1 November 2026. All distribution builders belong in
this repository on `main`; the repository name remains `uke-fedora-builder`.

| Selection | Current behavior | Remaining work |
| --- | --- | --- |
| `--distro fedora` | Existing Fedora image and kernel routes; default | Continue separate package, image and device qualification |
| `--distro ubuntu` | Explicit unsupported error before host preparation | Integrate native Ubuntu 1006 boot/userspace work; signed package inputs, root filesystem composition, initramfs/boot integration, payload audit, desktop/account setup and image export tests |
| `--distro arch` | Explicit unsupported error before host preparation | Native package inputs and signature verification, root filesystem composition, initramfs/boot integration, payload audit, desktop/account setup and image export tests |

Both `--distro NAME` and `--distro=NAME` are accepted. Interactive invocations
offer the same choices. Noninteractive invocations retain Fedora as the default.
Unsupported choices fail even for plans and historical boot/core commands, so
no Fedora package, release, kernel or device assumptions leak into another target.
The existing root workspace launcher consumes this common entry point.

Ubuntu implementation is a separate ongoing task; this routing change does not
replace or duplicate its native boot/userspace work. Enabling a backend requires
its own validated package and image path, followed by separate device evidence.
Source routing fixtures alone establish neither image readiness nor tablet support.

The consolidation retains TEST through commit
`854509087106381a7faffed14947e02109fd0756`, including signed package and release
validation fixes. Previous branch tips are preserved as `archive/main-only-20261101/*`
tags. Experimental tablet snapshots remain historical evidence and are not
implicitly enabled in the supported Fedora path. Existing immutable Fedora
release assets are unchanged; no new image release is produced by this change.
