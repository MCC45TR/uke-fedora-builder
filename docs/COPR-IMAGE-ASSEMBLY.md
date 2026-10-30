# COPR image assembly prerequisites

On 30 October 2026, Fedora Rawhide AArch64
[COPR 11232234](https://copr.fedorainfracloud.org/coprs/build/11232234/) verified
the native image helpers, an offline guest root transaction and a 1 GiB EXT4
fixture. The signed helper is `uke-image-tools-1.0.0-14.fc46.aarch64`, source
`15272418bb25a58b659ac50c057ad82ea02ca54e`. Its native program sources are
unchanged from revision 12. The build also checks the complete declared desktop
package policy before accepting its SDK inputs.

The full image root stage and the integration check use the same
`root-transaction.sh` function. It preserves the caller's package and repository
policy, rejects logged RPM scriptlet failures even when DNF returns success,
checks native target execution and runs the dependency check. The full desktop
package selection and subsequent provenance, payload and privacy audits remain
in the image stage.

The COPR source worker resolves complete SDK and fixture transactions, downloads
without installation or replay, and supplies 224 individually signed public
Fedora RPMs. A build-only CPIO converter preserves data-last hard links without
host-user extraction. The SDK formatter must match its original signed RPM's
digest and hard-link identity. Inside a direct/TCG libguestfs appliance, native
DNF performs a normal signature-checked installation with scriptlets. The
bounded root records 94 installed RPM entries. Fedora creates the chrony
account, and its shipped tmpfiles rule creates the ghost state directory as
UID/GID 997. Virtual filesystems are mounted only inside the appliance. Native
worker and guest networking remain disabled.

The production stage and COPR fixture share regular-file EXT4 population and
archive/comparison functions. The formatter derives root ownership and mode
from the real staging tree. Native label application and verification pass
10,682 paths. Separate read-only appliances verify the SDK and populated image
without changing their hashes. Content, path inventory, owners, modes, exact
mtimes, symlinks, ACLs and capabilities match the independent image export.
Three deliberate owner, ACL and capability corruptions are rejected; restored
metadata passes again. The native sparse codec and independent AOSP decoder
both reproduce the original raw image.

The RPM contains six native tools, documentation, license and source identity.
The SDK, QEMU, CPIO converter and probes are not shipped. Libarchive is used only
to build the SDK converter; it adds no runtime dependency to the helper RPM.

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

The source worker and production stage share the package and exclusion policy.
All 12 KDE/GNOME, Bash/Fish/Zsh and linux/userdata goals resolve against the
exact kernel 60 parts. The KDE closures contain 961–965 packages; GNOME has
768–772. DNF stops at its confirmation boundary with `--assumeno`; only solver
metadata is retained, with empty target databases and RPM caches. The unstable
selection explicitly names `uke-pipewire` and `uke-pipewire-pulseaudio`, avoiding
a conflicting newer Fedora provider without relaxing solver policy. Device-local
touch and video-firmware RPMs are excluded from generic images. These metadata
results do not verify target RPM signatures, firmware rights, installation or
full composition.
