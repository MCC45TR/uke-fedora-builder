# Original Fedora super tools in early userspace

15 November 2026. `95uke-super-tools` is an explicit dracut tool module. It
installs the six layout, inspection, planning, provisioning, physical selection
and read-only rescue-mapping scripts with original Fedora binaries and the dynamic
libraries selected by dracut. It installs no boot hook, service, default root,
automatic physical selection, automatic format or kernel modules. It is not enabled in
the current cumulative kernel.

The manual source workflow's `build_super_runtime=true` job assembles this
module on native AArch64, without a compiler. Only the named module is selected;
the resulting archive intentionally has no `/init` and cannot boot. This
isolates the userspace dependency check from the future protected boot policy.

The host Android tools RPM may bring Python into the disposable worker. Only
the named ELF tools and their libraries enter the archive. The target scanner
must find no recognized Python file, interpreter or dynamic dependency. Every
installed ELF must be AArch64 and byte-identical to an original RPM-owned host
file; stripping is disabled for this comparison. Provenance records each ELF's
path, digest and owning NEVRA, together with the exact module/helper/test hashes.

The chroot has only these installed tools, two sparse-file fixture scripts, a
private writable fixture directory and read-only procfs for descriptor access.
The fixture's helper paths resolve to the installed archive copies. Original
liblp topology and phase/restart refusal tests run there, followed by actual
16-to-32-MiB EXT4 growth and a small swap-file signature check. No swapon, block
device, kernel driver, tablet or physical disk is lent to this job. Withholding
the copied protobuf library must make lpdump fail at the dynamic loader; the
test cannot fall through to the worker's libraries.

The tools-only chroot has no Uke device tree. The physical selector must refuse
it. Separate namespace fixtures exercise the selector with synthetic sysfs and
device-tree views over an owned loop; these are not physical UFS acceptance.

The worker is limited to two CPUs and2GiB RAM, requires12GiB free before work
and8GiB before assembly, and rejects an archive over64MiB compressed or256MiB
expanded. All large temporary files are owned disposable inputs. Only small
receipts are uploaded; this does not publish or deliver a bootable initramfs.

The coordinator still needs a versioned protected root/role contract, unique
physical UFS selection, authenticated layout/OS inputs, matching kernel and DM
support, bounded rescue routing, and crypto/resume integration. The current
kernel's selector-v2 and crypt omissions cannot qualify those capabilities.
No change to lockdown, bootloader trust, firmware, GPT or the target follows
from a successful tool-closure test.

The module uses dracut's documented `inst_multiple` and `inst_simple` interfaces;
the former includes binary dependencies, while the latter copies the explicitly
supplied project scripts. See the [upstream module interface](https://dracut-ng.github.io/dracut/man/dracut.modules.7.html)
and [dracut options](https://dracut-ng.github.io/dracut/man/dracut.8.html).
Source review used upstream commit`a82ee11242302704b999dc430bcbdeb4c838e9ea`;
the execution receipt records the actual original Fedora dracut RPM version.
