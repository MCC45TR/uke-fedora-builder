# Cutefish and KDE Mobile test images

15 November 2026. Source integration; build results and physical acceptance are
recorded separately. Both profiles use the existing public singleboot EXT4
pipeline. The sparse `system` payload targets userdata; its companion boot must
come from the same verified cohort. No build step writes a tablet partition.

Cutefish is Rawhide unstable only. `cutefish-rawhide.json` supplies the actual
root package selection, exact repository allowlist and installed-closure tests.
The existing COPR signing fingerprint is unchanged. Toolkit, framework, core,
compositor, DM, applications and icons have separate source RPMs. The image
includes Uke's dedicated first-account and session configuration packages.
The root account is locked and no human account, public password, automatic
login or passwordless sudo is included. Storage growth and swap gates precede
both setup and DM. The packaged input validator runs during composition.

Cutefish language auditing retains every supplied RPM catalog. The source lock
provides sixteen languages per translated domain, with no upstream Turkish UI
catalogs. Turkish glibc locale, fonts, Qt translations and all supplied catalogs
remain required. The original vector background avoids excluded Unsplash data.
A verified `cutefish-icon-theme` RPM supplies passive icons; the general target
payload and signature checks remain enforced.

`plasma-mobile-rawhide.json` follows the mandatory/default packages in the
original Fedora `kde-mobile` and `kde-mobile-apps` groups, plus an explicit
original Fedora keyboard, mobile look-and-feel, identity and existing Uke admin
integration. Its reference raw.xz SHA-256 matches the supplied local file and
the official November 14 compose. The profile records exact Koji package-list
and KIWI-description hashes. No generic Fedora kernel, boot loader or unrelated
board firmware from that disk image is copied to Uke. KDE packages are original
signed Fedora builds. The image preselects the original Plasma Mobile session
and mobile look-and-feel, retaining original Plasma Setup.

The Cutefish workflow has a source/host-capacity preflight and a separate compose
phase. Test images are Actions artifacts; there is no publication job. The
shared publication script refuses Cutefish without separately recorded physical
setup and login acceptance. Source tests and image readback cannot establish
GPU/DRM acceleration, fitted touch provisioning, greeter keyboard, first-account
success/interruption, application UI, audio, networking or power behavior.
The existing device-local touch-data admission gate is retained; private fitted
calibration must not be baked into a generic image. Validate input and the
accepted recovery route before using a test image on a physical device.

Source-only validation covers package profiles, transitive desktop isolation,
complete supplied translations, source-stage routing, CLI selection, first-boot
storage ordering, passive icon provenance and release-layout/publication gates.
Signed native RPM builds, actual installroot transactions and filesystem/boot
integrity are required in addition before an artifact is described as built.
