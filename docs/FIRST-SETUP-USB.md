# Temporary USB access during Plasma setup

The Plasma image requires `uke-control(setup-cdc-v1) >= 1`. Image composition
refuses an older package, missing setup units, an already completed setup,
unsafe state directories or an unexpected activation marker before changing
the image's setup policy.

Only the newly assembled root receives the protected
`/etc/uke-control/first-setup-cdc` marker and two enabled setup units. Installing
Control on an existing system leaves its USB preference unchanged. The image
builder never writes that saved preference either.

During setup, the existing Control executable offers `help`, `status`, `logs`
and `reboot bootloader` over a restricted CDC endpoint. The original manual
CDC manager retains its hardware and ownership checks. Completion of Fedora's
original Plasma setup closes the endpoint and restores the saved USB policy.

The offline image fixture uses the distribution's real `systemctl --root`
to verify enablement, repeat behavior and refusal of completed, old, linked,
writable, foreign or incomplete roots. COPR 11332798 separately qualified the
actual protocol on ARM64 with GCC, Clang and both sanitizer modes; hardware
actions in that fixture were synthetic. Cumulative Control packaging, a real
fresh-image boot, host reconnection, idle resource measurements and physical
completion cleanup remain required.
