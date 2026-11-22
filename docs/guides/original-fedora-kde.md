# Original Fedora KDE dependency admission

The 14 October 2026 exception permits the Fedora root to retain Python supplied
by unmodified original Fedora desktop dependencies, including KDE and GStreamer
helpers. File bytes must match separately verified signed original RPMs.
Project startup, services and tests remain native or shell. Core and early
initramfs retain their strict Python-free audit. KDE applications are never
cloned, forked or rebuilt as Uke variants.

Use DNF5 to store the transaction for `plasma-workspace plasma-desktop
kwin-wayland sddm konsole`, with signature checking and weak dependencies
disabled. Keep this private staging root separate from any public image.
The Core meta packages conflict with Python; remove only the two Core/desktop
meta packages from the copy without dependency cleanup. Native boot integration
0.1.0-6 supports coexistence without adding a Python dependency itself.

Run the host-only `src/audit/prepare-original-kde.sh TRANSACTION_DIR AUDIT_DIR`.
It requires those five original application roots, bounded paths, install-only
actions and exact signed RPM identities. Original Fedora packages use an
isolated Fedora 46 key database. Existing non-KDE native support libraries use
the pinned COPR key and retain their strict no-Python payload/dependency audit.
The receipt records the complete package hashes and transaction identity.

After replaying the same checked transaction in the copied ARM64 root, run
`src/audit/check-target-payload.sh --original-kde-payload AUDIT_DIR/original ROOT`.
This option trusts only the separately verified original staging directory;
do not substitute an arbitrary directory or the target itself. Every recognized
Python file, symlink, shebang or linked runtime must match its original package
bytes. Changed, added, retargeted and escaping files reject. Never use this
exception for project helpers or early initramfs.

Record package, emulation and physical results separately. A working software
Wayland session does not prove Adreno acceleration, native panel control,
touch, automatic rotation or light sensing. Public images additionally require
privacy/identity/firmware provenance checks, complete filesystem readback,
checksums, recovery instructions and the matching kernel/early-module tuple.
Private credentials, keys, logs, calibration and firmware must not become
release assets. The live root copy is not an offline filesystem snapshot.
