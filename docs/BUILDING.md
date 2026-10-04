# Senemos Uke kernel build entry

Run the workspace's only new executable entry, `senemeos.sh`, from the project
root. It prepares host prerequisites, verifies the stable source signature,
builds in an isolated Fedora toolchain and produces AArch64 RPMs and an SRPM.

```sh
./senemeos.sh --build 7.2.9 --distro=fedora --test
./senemeos.sh --build latest --distro=fedora
./senemeos.sh --build lastest --distro=fedora
./senemeos.sh --help
./senemeos.sh --self-test
```

`fedora` defaults to `rawhide`. `lastest` is an alias for `latest`. Latest is
resolved through Kernel.org's `releases.json`; every version still needs a
reviewed Uke profile. A future stable release fails explicitly until ported.
Fedora 45, openSUSE Tumbleweed, Debian/Ubuntu/Armbian/Kubuntu and
Alpine/postmarketOS target profiles currently report `planned`.

Supported host families are Fedora/RHEL, Debian/Ubuntu, openSUSE, Arch and
Alpine/postmarketOS, on x86_64 or AArch64. Missing prerequisites are installed
from official repositories with root, sudo or doas. Alpine's POSIX preamble
installs Bash before handing off. A working Podman or Docker is reused; Podman
is installed when needed. Container compilation runs with the invoking user's
UID. Initial rootless namespace setup may need administrator assistance on
hosts that prohibit unprivileged namespaces.
The [host bootstrap record](../reports/HOST-BOOTSTRAP-2026-10-04.json) identifies
the six official x86_64 images whose actual prerequisite installation passed;
it also lists the host-engine and architecture cases that remain untested.

Use `--dry-run` for version/target resolution without installation or compilation,
`--jobs N` to set concurrency, and `--offline` after caching signed sources,
release metadata and the exact toolchain image. The default limit is the smaller
of available CPUs, approximately one worker per 2 GiB available RAM, and four.
At least 25 GiB free space is required. The script holds a workspace build lock,
queues behind other compilers and pauses its own container if a recovery or
other native build starts. It never pauses, kills or cleans another build.

Verified archives remain in `senemos-uke-kernel/referances/releases/`. RPM's
development sources and reusable output live below this component's ignored
`build/fedora-rawhide/VERSION/`. Changed input identities preserve the old output
as a saved directory before creating a clean output. An interrupted invocation
retains completed objects; retry the same command. Malformed dependency records
left by an interrupted fixdep are discarded without dropping complete objects.
A completed build is reused only when its source/config/toolchain/build-rule
identity and recorded artifact hashes match. A changed packaging spec rebuilds
the RPMs using the verified compiled kernel. Every enabled/value requirement in
the Uke and Fedora fragments is checked after Kconfig dependency resolution.
Logs remain local.
Previous job logs are retained on retries. Requested checks finish before a new
artifact directory is promoted; failures preserve the previous complete
candidate instead of mixing new packages with an older manifest. A promoted
candidate preserves its predecessor in a dated saved directory.

Artifacts appear in `artifacts/fedora-rawhide/VERSION/`: four RPMs (meta, core,
modules, dtbs), an SRPM, Image, Uke DTB, config, Module.symvers, dependency and
toolchain inventories, an input manifest and SHA256SUMS. RPMs are unsigned local
development candidates. Their scriptlets only run depmod. No flashing, Android
partition write, boot entry selection or global kernel-headers replacement occurs.
Each SRPM is independently extracted and its embedded spec prepares the signed
source and complete patch/config set. This validates source closure without
claiming a second full kernel rebuild or byte-identical RPM reproduction.
The SRPM is a host source/rebuild artifact, including pristine upstream source;
only the four binary RPMs are tablet installation candidates.

`--test` runs actual AArch64 RPM installation, a higher-release upgrade and
removal in a disposable Rawhide container. On x86_64, registered qemu-aarch64
binfmt support is needed for that target userspace test. A working handler is
reused; if absent, the entry installs the host's official QEMU package and
registers a dedicated handler without deleting other handlers. Host privilege
or namespace restrictions can still prevent this preparation; such failures
stop the test explicitly. The test also checks the
complete installed package list for Python. Container/package success does not
establish a tablet boot, working peripherals, UEFI firmware or physical support.
The test runtime is built separately from the pinned AArch64 Rawhide base with
kmod installed. Local RPM solving and lifecycle operations run with repositories
disabled and network access blocked. `--offline --test` needs that exact cached
runtime as well as the source and toolchain cache.

The base-image digests are pinned in `configs/build-rules.json`; the toolchain
cache is keyed by its recipe and rules, and its concrete image ID and package
NEVRAs are recorded. Fedora Rawhide repositories can change after a cache miss;
retain the recorded toolchain image to reproduce its exact package environment.

Host-only Python exception: Fedora's upstream RPM development stack installs
Python through its packaged build-policy dependencies. This preserves the
distribution's official RPM environment rather than maintaining a fork of its
policy package. The inspected environment contains Python 3.15.0~rc2-1.fc46 and
redhat-rpm-config 345-4.fc46; the exact inventory accompanies each build. RPM
postprocessing/byte-compilation is disabled for this kernel spec. Project
automation and kernel compilation use shell, Perl and native Kbuild tools.
No project Python program, interpreter or Python dependency is copied to tablet
RPMs. dt-schema is not required by this entry's compile/package checks; schema
validation must be recorded separately if added with a pinned host-only tool.

COPR publication uses the official host-only `copr-cli-2.7-1.fc46.noarch` and
`python3-copr-2.8-1.fc46.noarch` authenticated API client. It is not a project
Python program or target dependency. SCM source generation uses COPR's official
Fedora host chroot, separate from the pinned local image. `.copr/Makefile`
exports only SRPM files; verification state stays outside its result collector.
GitHub push hooks and daily stable workflows are configured for the two ready
source packages. See `reports/COPR-AUTOMATION-2026-10-04.json` and the workspace
package hub. RPM same-version corrections increase the release so DNF can
deliver them, while the compiled kernel cache remains reusable when source,
config and compilation rules are unchanged.

Official emulator package references: [Fedora](https://packages.fedoraproject.org/pkgs/qemu/qemu-user-static-aarch64/),
[Debian](https://packages.debian.org/trixie/qemu-user-static),
[Arch](https://archlinux.org/packages/extra/x86_64/qemu-user-static-binfmt/),
and [Alpine](https://pkgs.alpinelinux.org/package/edge/community/s390x/qemu-aarch64).
Package names select the host's own architecture and repositories; emulator
runtime and kernel compilation are separate evidence classes.
