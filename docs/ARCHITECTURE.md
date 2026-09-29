# Fedora build architecture

The builder consumes identified kernel, DT, module and firmware inputs. It produces core/modules/devel RPMs for `senemos-uke-kernel-mainline`, a console-first Rawhide AArch64 rootfs and boot-profile artifacts. The initial COPR channel is `mcc45tr/uke-linux-test`; it currently contains no project builds.

Resolve package dependencies before selecting a desktop. Preserve repository metadata, complete NEVRAs, RPM checksums and licenses. Do not install broad package groups without inspecting their transitive dependencies: no Python runtime, script or libpython dependency may enter a tablet payload. Choose native alternatives or defer an incompatible feature. Document unavoidable upstream Python tools as host-only exceptions with exact pins.

Each artifact manifest will include source/config/toolchain hashes, package closure, firmware profile, DT identities, kernel release, module vermagic, boot header fields, partition size limits, signature state and full SHA-256. Unpack candidates and verify these fields independently. Kernel and modules come from one build; module processing is strip, sign, then compress.

RPM scripts must not flash Android partitions or change the selected boot profile. QEMU/solver checks, terminal COPR build success and physical boot are separate acceptance records. A rootfs archive is not assumed to fit init_boot. Signing keys and raw device logs remain private.
