# Sequential desktop images

The root repository's manual **Sequential shared-core desktop images** workflow
installs the signed Fedora Rawhide AArch64 unstable core once, then runs KDE
Plasma, GNOME, Cutefish and NextKDE jobs in that order. All images use Bash,
singleboot userdata and the same EXT4 capacity. No source compilation is used.

The core is an internal seven-day Actions artifact, not a flashable image or
Release asset. It contains the owned root archive, original Fedora byte evidence,
exact signed kernel/tool inputs, RPM inventory and checksums. Desktop jobs must
use the same builder commit and profile. Corruption, recipe/profile differences,
or replacement/removal of any core RPM fail the job. Desktop dependency solving
and signature verification still run; failures never fall back to source builds
or another desktop.

Each completed desktop is independently checked through filesystem readback,
SELinux metadata, both Android sparse decoders and the kernel/module/DT/root
cohort checks. Publication appends only images to one dated experimental Release.
Before reusing the published boot, the publisher downloads it, compares its
bytes and checks the canonical cohort. A changed boot or root collision requires
a new revision. Old Release assets and URLs remain intact. Receipts stay in
seven-day delivery and 90-day metadata Actions artifacts.

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
