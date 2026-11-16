# Early plaintext super and rescue profile

The existing tool-only dracut module stays separate. A new opt-in module adds
ordering before the unchanged physical-root guard. The fixed seed4-v1 profile
uses the canonical 4 GiB seed layout; a future larger seed requires an explicit
coordinated contract update. Runtime capacity still comes from the uniquely
selected Uke UFS partition, so it is not fixed to the 512 GB storage model.
The current 512 MiB Fedora rescue has already passed composition and owned-loop
growth. No 256 GB physical geometry or physical early boot is claimed.

Without the explicit kernel-admitted seed flag, original root admission runs
unchanged. With the flag, the existing provisioner accepts only canonical Uke
seed/growing/ready metadata and preserves its saved-image/encrypted-state and
active-holder refusal checks. It does not format an Android super layout.
Only rescue creates a read-only mapper, then independently revalidates its UUID,
linear table, capacity, filesystem and all metadata views before root admission.
Verification never creates a mapping or removes a foreign one. The profile
neither activates swap nor unlocks an encrypted userdata volume.

The plaintext module refuses an installed protected-boot policy. It does not
replace the separate authentication/resume barriers required for the planned
encrypted profile. The pure role fixture and original systemd offline unit and
ordering checks pass; protected-policy overlap and ordering cycles refuse.
Real original-tool mapper verification and dracut/early-boot integration remain
pending remote qualification. No device write or physical OS boot was tested.
