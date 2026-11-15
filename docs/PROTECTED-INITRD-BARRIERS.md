# Protected initrd ordering

15 November 2026. `96uke-protected-boot` supplies ordering and discovery
barriers for the future protected singleboot profile. It is explicit-only,
is not selected by the current kernel or tools archive, and cannot assemble
without `/usr/libexec/uke-protected-boot-policy`. That native admission policy
is an outstanding coordinator dependency; no placeholder is shipped.

The module depends on original dracut `systemd` and `resume`, plus the Uke
super tools. With systemd selected, dracut's resume module installs the native
systemd helper rather than its non-systemd resume hooks. Original unit bytes
and the expected `!noresume` condition must match before adding drop-ins.

## Three distinct resume boundaries

Linux can attempt resume from its own late initcall, before initrd policy
runs. The protected kernel must compile `noresume` into its enforced command
line and reject conflicting handoff overrides. A late userspace assertion
alone cannot stop an earlier kernel attempt. The current kernel source has
an empty `CONFIG_PM_STD_PARTITION` but does not declare this protected profile.
Its configuration and capability need separate coordinator qualification.

The [Linux hibernation source][linux] checks `noresume` in
`software_resume_initcall()`. Its sysfs `resume_store()` deliberately clears
that flag for a later explicit resume, while still checking
`hibernation_available()`. This does not remove integrity lockdown or add
authenticated-snapshot support. A successful sysfs write is not proof that
an image was restored; the source may return without restoration when
hibernation is unavailable.

The original systemd resume generator can select a device from command line
or EFI and start before root admission. This module masks that generator,
the GPT auto generator and the cryptsetup generator in the initrd itself.
It also masks initrd swap activation and generic cryptsetup/legacy resume
units. No automatic software encryption fallback or parallel swapfile is
introduced. Legacy boot profiles are unaffected.

Finally, the original `systemd-hibernate-resume.service` requires and follows
both Uke admission services. Its `!noresume` condition is cleared only in this
explicit protected profile. Normal-role and resume-authorization conditions
must both pass. Its command is reset to the original helper with explicit
`/dev/mapper/uke-resume 0` arguments, avoiding independent EFI/command-line
device discovery. `sysroot.mount` requires and follows role admission and
that service, so a resume attempt cannot race a userdata mount.

## Required native policy

The coordinated native helper has two admission entry points:

- `admit-role` must validate the versioned kernel/profile, unique physical
  UFS, trusted boot/layout cohort and authenticated root/rescue selection.
  It may expose `/run/uke-protected/normal` only for the admitted normal role.
- `admit-resume` is ordered after role admission and runs only in normal
  mode. It must validate persistent key release, the exact owned inactive
  swap mapping, snapshot authenticity and compatible resume support before
  exposing `/run/uke-protected/resume-authorized`. Cold boot creates no such
  authorization. A detected invalid image must fail before mounting userdata.

These paths are transient operational state from the trusted policy, not
cryptographic evidence. Creating a marker is not a substitute for the native
validation, an OEM trust anchor or kernel snapshot authentication. Rescue
must never unseal userdata, activate swap or authorize resume. Role admission
also needs to prevent untrusted root selection and preserve the accepted
recovery/debug-access rules. No helper may weaken lockdown to pass a gate.

## Verification scope

`tests/protected-initrd-barriers.sh` exercises the module's copy interface in
an owned directory and uses original systemd to verify the resulting unit
transaction. It rejects a missing native policy, an ordering cycle and an
absent executable. Native condition tests distinguish missing/rescue/normal
without authorization from normal with both fixture markers. The tests never
start a system manager, execute the resume helper or access keys/devices.

The fixture explicitly uses an inert original `true` binary as the policy
stand-in. Passing it qualifies the barriers and systemd condition semantics,
not authentication, a bootable initrd, actual mapping/hibernate or hardware.
The current cumulative kernel and six-script tool archive are unchanged.

[linux]: https://github.com/torvalds/linux/blob/23c62304dde29abe92013d85910d03a77dada35d/kernel/power/hibernate.c

The original [systemd resume helper][resume] supports explicit device and
offset arguments; its no-argument mode performs device discovery. The
[generator][generator] creates the early dependency before root admission.

[resume]: https://github.com/systemd/systemd/blob/v262/src/hibernate-resume/hibernate-resume.c
[generator]: https://github.com/systemd/systemd/blob/v262/src/hibernate-resume/hibernate-resume-generator.c
