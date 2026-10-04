# Fedora build architecture

The first implementation consumes the reviewed Linux 7.2.9 Uke adaptation and
produces `senemos-uke-linux-kernel-mainline` meta/core/modules/dtbs RPMs and a
complete SRPM through the workspace's single `senemeos.sh` entry. A console-first
Rawhide AArch64 rootfs, development packages, firmware and boot-profile artifacts
remain later outputs. The initial COPR channel is `mcc45tr/uke-linux-test`; this
local build workflow does not publish to it. See [the build contract](BUILDING.md).

Resolve package dependencies before selecting a desktop. Preserve repository metadata, complete NEVRAs, RPM checksums and licenses. Do not install broad package groups without inspecting their transitive dependencies: no Python runtime, script or libpython dependency may enter a tablet payload. Choose native alternatives or defer an incompatible feature. Document unavoidable upstream Python tools as host-only exceptions with exact pins.

The kernel manifest includes source/config/patch/toolchain identities, kernel
release, DT identity and module ABI inventories, with full artifact SHA-256.
`--test` additionally records the AArch64 installed package closure. Firmware,
boot header and partition geometry belong to subsequent boot-profile manifests;
none is inferred by the compile-stage kernel package. Unpack candidates and
verify these fields independently. Kernel and modules come from one build.
Current local candidates are unsigned; modules are stripped and compressed.
When signing is introduced, it must occur after strip and before compression.

RPM scripts must not flash Android partitions or change the selected boot profile. QEMU/solver checks, terminal COPR build success and physical boot are separate acceptance records. A rootfs archive is not assumed to fit init_boot. Signing keys and raw device logs remain private.
