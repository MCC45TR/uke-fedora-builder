# COPR image assembly prerequisites

On 30 October 2026, Fedora Rawhide AArch64 COPR builds verified the native image
helpers separately from the environment needed to compose an operating system.
The helper RPM is `uke-image-tools-1.0.0-3.fc46.aarch64`, source
`fc7b5181ee49f5c27379ee257bd3981b13e59953`, built in
[COPR 11231022](https://copr.fedorainfracloud.org/coprs/build/11231022/).

The current privileged root-stage wrapper cannot run as that non-root worker.
Both mapped-root and subordinate-ID namespace attempts return
`Operation not permitted`. No worker policy or project network setting was
changed to obtain a result.

A separate libguestfs appliance using the direct backend and TCG creates a
disposable 64 MiB EXT4 image without host mounts or physical devices. Numeric
UID/GID 65534, a `security.selinux` attribute and fixed contents survive a
separate read-only appliance. The host image hash remains unchanged after that
readback. Guest networking is disabled. The existing native helper checks also
pass; the five helper programs have no source changes.

This proves an appliance prerequisite, not a complete Fedora image. Native
DNF/scriptlet execution, the full signed desktop package closure, original
Fedora payload comparisons, filesystem metadata and SELinux policy audits,
privacy, matched boot/module provenance and recovery remain required. The
current root-stage integration has not been replaced or qualified by this
probe. COPR native networking remains disabled; a future guest composer must
use source-worker-prefetched, individually verified RPM inputs.

No tablet boot, display, charging or recovery result follows from these checks.
Unreviewed firmware redistribution and device-private data remain separate
release gates.

The isolation approach follows the
[libguestfs architecture](https://libguestfs.org/guestfs-faq.1.html#How-does-libguestfs-compare-to-other-tools)
and [guestfish command interface](https://libguestfs.org/guestfish.1.html).

The next source candidate factors the existing DNF install and dependency check
into `root-transaction.sh`. The full image stage keeps its existing desktop,
package and provenance policy. The shared helper rejects failed scriptlets even
when DNF returns success, and verifies that target native commands execute.

Its COPR integration check uses a build-only SDK made from individually signed
Fedora Rawhide AArch64 RPM payloads. CPIO-to-TAR conversion preserves numeric
metadata without extracting files as the host user. The source worker resolves
all dependencies and supplies a local repository; native worker and guest
networking remain disabled. Guest DNF uses ordinary signature checks and RPM
scriptlets. A bounded selection includes chrony to check persistent system-user
creation and directory ownership in a separate read-only appliance. This check
does not compose the complete desktop image. Its source is prepared; a successful
COPR result is still required before this route is accepted.
