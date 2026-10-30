# COPR image assembly prerequisites

On 30 October 2026, Fedora Rawhide AArch64
[COPR 11231490](https://copr.fedorainfracloud.org/coprs/build/11231490/) verified
the native image helpers and an offline guest root transaction. The signed
helper is `uke-image-tools-1.0.0-7.fc46.aarch64`, source
`bf39fb75fd396421623842b77027177ad8fa805a`. Its five C++ program sources are
unchanged from revision 3; the existing native helper checks also pass.

The full image root stage and the integration check use the same
`root-transaction.sh` function. It preserves the caller's package and repository
policy, rejects logged RPM scriptlet failures even when DNF returns success,
checks native target execution and runs the dependency check. The full desktop
package selection and subsequent provenance, payload and privacy audits remain
in the image stage.

The COPR source worker supplies 213 individually signed public Fedora RPMs and
local repository metadata. A build-only SDK imports their CPIO payloads through
TAR without host-user extraction. Inside a direct/TCG libguestfs appliance,
native DNF performs a normal signature-checked installation with scriptlets.
The bounded root records 66 installed RPM entries. Fedora creates the chrony
account, and its shipped tmpfiles rule creates the ghost state directory as
UID/GID 997. A separate read-only appliance verifies that ownership and account;
the backing image hash remains unchanged. Virtual filesystems are mounted only
inside the appliance. Native worker and guest networking remain disabled.

A separate 64 MiB EXT4 check also preserves numeric UID/GID 65534, a SELinux
attribute and fixed data through independent readback. The helper RPM contains
only the five native tools, documentation, license and source identity. The SDK
archives, QEMU and probes are not shipped or required at runtime.

These bounded checks leave full desktop composition open. The privileged
container wrapper still cannot run as the COPR worker: mapped-root and
subordinate-ID attempts return `Operation not permitted`. Production guest
transport, the complete signed desktop closure, original Fedora byte checks,
filesystem metadata and SELinux audits, privacy and exact boot/module provenance
must pass together. Qualified firmware redistribution, device-private inputs,
recovery and physical acceptance remain separate release gates.

The isolation approach follows the
[libguestfs architecture](https://libguestfs.org/guestfs-faq.1.html#How-does-libguestfs-compare-to-other-tools)
and [guestfish command interface](https://libguestfs.org/guestfish.1.html).
