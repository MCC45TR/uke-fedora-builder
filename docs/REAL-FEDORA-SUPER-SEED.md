# Real Fedora super seed integration

15 November 2026. This composes a fastboot-format input and tests disposable
capacity growth. It does not offer a final installable ZIP or tablet boot.

The manual source-contract workflow accepts `build_super_seed=true`. It first
runs the existing native AArch64 Fedora rescue producer with the exact signed
cumulative kernel EVR and source pin. The seed consumer runs in the same trusted
workflow, checks the original filesystem digest, kernel receipt, filesystem
identity and a fixed allowlist of eight producer source hashes. These checks
bind the current producer's handoff; self-asserted JSON flags are not an
independent signature or physical boot proof.

The actual 512-MiB rescue fits a 4-GiB seed. Original lpmake allocates rescue at
the fixed first logical extent and swap after it, preserving 20/80 shares.
Original EXT4 tools grow the copied filesystem to the seed allocation, and
the existing super producer independently decodes and compares both complete
payloads and all three metadata slots. It never writes a physical device.

`minimum_super_bytes` is an explicit assembly bound. Its default11274289152
comes from the measured512-GB Uke, not a measured256-GB device. The output records
this bound and keeps common-archive qualification false. A 4-GiB expanded seed
is smaller than the synthetic8-GiB growth fixture, but that does not turn the
fixture into actual256-GB capacity evidence. Final packaging still needs the
qualified geometry set and original-fastboot pre-write admission.

The same produced sparse seed is decoded into one owned8-GiB loop backing file;
no extra sentinel or other test file is inserted into the actual Fedora root.
The existing process-interruption suite then checks active-use and saved-image
refusal, growth restart, a torn ready commit and a byte-identical ready no-op.
After real EXT4 growth it independently reads systemd, fstab and the kernel's
source record and compares each with its original seed bytes. The systemd
SELinux context must remain init_exec_t. These extend the earlier tiny synthetic
filesystem checks without replacing their corruption/refusal cases.

Both block helpers derive major/minor from the opened descriptor and match it
to `/sys/dev/block`. The provisioner checks holders through that identity and
reopens its write descriptor through the pinned read descriptor. The owned-loop
suite also refuses an active holder through an alternate block node, then
replaces that private node with `/dev/null` during preflight. The read-only
mapper and provisioner must still operate on the original checked loop inode.
These checks do not supply the protected caller's physical UFS selection or
authenticate on-disk metadata.

The worker remains native AArch64 with two CPUs and2GiB RAM. A24-GiB initial
free-space gate covers root assembly, the producer's conservative peak, loop
fixtures and reserve. Only the owned loop and device-mapper control are lent
to the second container, with scoped mapper UUID cleanup. No tablet, physical
disk, host root or full privileged container is involved. No source is compiled;
original Fedora tools and the signed COPR cohort are used.

The artifact retains only the sparse seed and small input, source, composition
and growth receipts. The duplicate original rescue filesystem is not uploaded
when producing a seed. Existing accepted recovery, firmware, GPT and tablet
state are untouched. Root selection, trusted early mapping, resume/crypto,
authenticated recovery, source-built boot cohort, OEM trust and real tablet
qualification remain required before the requested final ZIP can be delivered.
