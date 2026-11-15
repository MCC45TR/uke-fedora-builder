# Physical Uke super selection

15 November 2026. This is an early-startup read-only selection boundary. It
does not format a volume, authorize a fresh installation, choose a boot role,
unlock storage or resume a saved system.

`select-uke-super.sh --identity-only` requires the live device tree to contain
both `xiaomi,uke` and `qcom,sm7675`. It counts every sysfs `PARTNAME=super`,
including foreign and virtual candidates, before accepting exactly one physical
partition under the measured `1d84000.ufshc` controller and `ufshcd-qcom` driver.
Partition type, number, kernel name, major/minor, sysfs device links, capacity,
4096-byte logical sectors and the partition-name device link must agree.
Partition numbers and byte capacity are read from the device, not fixed to a
storage model or the example `sda31` name.

The helper opens the selected block inode read-only on descriptor3 and derives
its identity from that descriptor. `--inspect-ready` passes the pinned descriptor
to the existing original-libLP all-slot verifier, which checks the exact ready
geometry and mappings. Identity-only does not qualify a Linux logical layout.
Neither mode authenticates on-disk contents or establishes OEM boot trust.

The function `uke_open_physical_super` can be sourced by a future protected
caller that retains descriptor3. This does not supply that caller's trusted
seed/cohort contract or authorize the current low-level provisioner. There is
no option that executes an arbitrary command or reopens a returned pathname.

Read-only identity selection was exercised through SSH on the running Uke
kernel26 without installing a script or binary. The selected physical super
was11274289152B with4096-byte logical sectors. This is one512-GB device, not
actual256-GB geometry, Linux rescue mapping, OS boot or encryption acceptance.
Private identity receipts omit captured unit identifiers and credentials.

Read-only reinspection on 15 November confirmed that these roles span two
UFS logical units under the same `1d84000.ufshc` controller. Super and userdata
are on the current `sda` disk, while both boot/vendor_boot/DTBO/vbmeta sets are
on `sde`. These names and partition numbers remain observations, never fixed
selector inputs. A future complete-cohort owner must validate each physical
partition independently and permit different logical units of that same
verified controller; requiring every role to share the super disk would reject
this tablet. The current super selector does not open those other roles.
Follow the kernel's [sysfs access rules][sysfs]: resolve classification links
to device paths and read parent attributes on the relevant parent device.

The running kernel remains `7.3.3-26-unstable` with integrity lockdown. The
filtered command line/bootconfig/chosen data supplied no explicit slot hint;
`androidboot.secureboot=1` and `verifiedbootstate=orange` do not identify a slot
or establish the requested full OEM-to-Linux trust chain. Equal images in both
slots are an intentional initial-install requirement, so a unique image hash
cannot be required to distinguish them.

CI also exercises both modes over the existing owned4KiB growth loop using a
synthetic read-only sysfs/device-tree mount namespace and a capability-free child.
Two names/partition numbers are accepted;19 malformed, duplicate, foreign,
virtual, mismatched-link/device/capacity and sector-size cases must refuse.
The complete loop hash must equal the prior ready no-op hash. No additional
full image is made. A successful synthetic view is not physical hardware proof;
the uploaded fixture receipt explicitly records that distinction.

The host fixture uses original util-linux unshare, mount and setpriv. Mounts
remain private; sysfs/device views are read-only, and temporary space is bounded
to64MiB plus16MiB for `/run`. The selector child must have all five capability
sets empty and no-new-privileges enabled. Docker's default syscall filter is
retained; no pivot_root, custom seccomp profile or privileged container is needed.

The explicit dracut tools module includes this script but installs no boot
hook. It remains absent from the current cumulative kernel. Trusted role and
key/resume ordering, authenticated rescue inputs and the matching kernel/driver
closure remain required before boot integration or a final installer.

[sysfs]: https://docs.kernel.org/admin-guide/sysfs-rules.html
