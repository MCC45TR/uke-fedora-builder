# Parallel desktop images with one publisher

The root repository's manual **Parallel shared-core desktop images** workflow
installs the signed Fedora Rawhide AArch64 unstable core once, then runs KDE
Plasma, GNOME, Cutefish and NextKDE jobs independently in parallel. All images use Bash,
singleboot userdata and the same EXT4 capacity. No source compilation is used.

The core is an internal seven-day Actions artifact, not a flashable image or
Release asset. It contains the owned root archive, original Fedora byte evidence,
exact signed kernel/tool inputs, RPM inventory and checksums. Each desktop gets
a fresh copy of that artifact; a previous desktop image is never an input.
Ordinary imports require the same builder commit and profile. Corruption and profile differences,
or replacement/removal of any core RPM fail the job. Desktop dependency solving
and signature verification still run; failures never fall back to source builds
or another desktop.

Each desktop is independently checked through filesystem readback,
SELinux metadata, both Android sparse decoders and the kernel/module/DT/root
cohort checks. One publisher waits for all desktop jobs to finish. It downloads
each successful delivery into its own directory, checks the required set, equal
core hashes, compatible cohorts and byte-identical boot files, then creates one
experimental Release containing one boot and the validated root images. KDE,
GNOME and NextKDE are mandatory. An isolated Cutefish failure does not block
those three; its absence is stated in the Release body. Cutefish is added only
after independent success and identical boot/cohort verification. Missing
mandatory desktops or conflicting receipts fail before publication. A changed boot or root
collision requires a new revision. Old Release assets and URLs remain intact. Receipts stay in
seven-day delivery and 90-day metadata Actions artifacts.

An explicit `core_run_id` can recover an already validated core after a desktop
worker failure, without repeating core assembly. The recovery job checks the
same repository's completed manual Fedora series, the successful core job,
its immutable workspace gitlink, artifact ZIP SHA256 and the target profile.
The inner archive's checksums are checked again in each fresh desktop job.
The selected producer builder must match the artifact; the consumer builder
and original producer source/run/hash are recorded separately in each root
manifest. This is explicit reuse, never an automatic fallback. All current RPM
signature, unchanged-core-package, module/DT/boot and filesystem checks still
run. Each worker initializes its own pinned kernel signer database.

Explicit `kde_run_id`, `gnome_run_id`, `cutefish_run_id` and `nextkde_run_id` inputs
can preserve an already validated delivery from a successful composition job,
including a run cancelled before publication. Reuse verifies repository, source
gitlink, successful composition, artifact ZIP SHA256, root/boot hashes, profile,
date/revision and the expected common core hash. The image is not rebuilt and
its original source record is preserved. These inputs never install one desktop
image into another desktop root.

Both producer and consumer reject full desktop sessions/display managers in
the common RPM inventory. Shared libraries such as `libplasma` and
`plasma-workspace-common` are allowed. Cutefish's GDM greeter legitimately pulls
GNOME components; those are independent package dependencies, not input from the
GNOME image. RPM inventories distinguish those dependencies from full sessions.

KDE Plasma and NextKDE retain Fedora Plasma Setup. NextKDE uses the original
Plasma Wayland session and starts its signed KOS user services only after setup
and a normal account login. GNOME retains GNOME Initial Setup. These three
images have no default normal account.

Cutefish uses Fedora GDM and the explicitly requested public test account
`senemos` / `fedora`. Its password is expired. During assembly a host-only GJS
probe drives the **actual installed GDM worker and PAM stack** through login,
the current-password prompt, both new-password prompts and authorization. The
probe uses an ephemeral generated replacement password, then restores and
expires the public test password. It installs no helper or test credential
on the tablet. `cracklib-dicts` is explicit: without it Fedora PAM can reject
every new password when weak dependencies are disabled. Probe failure blocks
the image. Automatic login, SSH, remote password authentication and passwordless
sudo are disabled. Tablet graphical login, the desktop session, first account
setup, physical boot and rollback remain separate unqualified hardware tests.

The desktop COPR repositories are limited to `nextkde,quickshell` or
`cutefish-desktop` and their pinned signing fingerprints. Fedora supplies Qt,
KWin and the display manager. ABI/dependency mismatches are build failures.

On 1 November 2026 an isolated Fedora Rawhide x86_64 host probe observed GDM
51.1.1 completing the real expired-password conversation after adding the
dictionary package. The native ARM image job must repeat that test against
its own installed packages; this observation alone does not qualify an image.
