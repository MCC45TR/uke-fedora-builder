# Minimal installed-account rescue console

The rescue root keeps the original Fedora packages and matching signed kernel
cohort. Its global root account stays locked; network listeners remain disabled.
No desktop, generic password, persistent credential or model is added.

For the explicit `senemos.role=rescue` profile, original modprobe loads the
already signed `g_serial` module. It offers a standard CDC ACM endpoint and
refuses a busy gadget controller. The console waits for the host carrier with
a blocking TTY open. It does not poll hardware or alter Type-C ownership rules.

A private mount namespace selects the unique physical Uke UFS userdata partition
and mounts a provisioned EXT4 filesystem read-only without journal replay. The
primary installed account (UID1000) must be enabled and in wheel. Account
databases must be bounded, regular, unlinked, root-owned and non-writable by
other accounts. Duplicate identities and malformed or locked hashes refuse.

Only in that namespace, a volatile shadow entry supplies this administrator's
existing hash to original Fedora sulogin. The temporary file keeps the original
shadow SELinux context. Password input and crypt verification remain in sulogin;
the shell never receives the password. There is no `--force` fallback or disk
copy of a credential. Authentication opens a standard root rescue shell, with
`UKE_RESCUE_INSTALLED_ROOT` identifying the read-only installed system. Original
mount, filesystem and chroot tools provide explicit repair; no repair or writable
userdata mount is automatic.

The initial method requires a readable installed EXT4 account database and the
enabled primary administrator. It does not provide access to an unmountable or
still-encrypted root. Separate recovery credentials and secure unlock require
their own provisioning and validation; they must not be replaced by an open
root console. Other terminal reboot targets and a reliable one-shot return path
also remain separate from this console setup.

The fake-database tests cover the actual admission function, including primary
and supplementary wheel membership, duplicates, UID bounds, locked hashes,
symlinks, hard links, ownership, writable files and input bounds. They do not
test a password. Native module metadata on the running 7.3.4-4 confirms the
chosen original parameters. Image assembly, SELinux enforcement, actual USB
carrier/authentication, idle behavior and chroot still require validation.

A bounded check on the running 7.3.4-4 system used original Fedora sulogin and
a private mount namespace with the temporary shadow on tmpfs. An incorrect
password was refused; the existing administrator password opened a UID0 shell
with global SELinux enforcement retained. Exit removed the private mount and
temporary files; the global root account remained locked. The shell never
received or saved either password. This validates the volatile-shadow and
original crypt/TTY path in an SSH session. It does not validate the rescue
image, USB carrier, service SELinux domain or installed-filesystem mount.

Before full-ZIP composition, `scripts/verify-rescue-console.sh` independently
reads the regular rescue EXT4 file with read-only debugfs. It matches the file
hash and size to the native composition record, compares all three helpers,
both units and the module options with reviewed sources, and checks installed
permissions, the locked root account, absence of human accounts and activation
links. A second complete image hash verifies that inspection changed nothing.
When inspecting the expanded filesystem extracted from super, supply its native
`super-composition.json` as the fourth argument. The verifier retains the
original source hash and requires the exact canonical seed geometry, independent
decode/byte-match proof and actual expanded payload hash and size. The full
composer binds this receipt to both the source composition and the actual super
payload. An older locked-console-only seed is refused.

Synthetic filesystem fixtures accept the exact sources and locked account;
wrong executable permissions, an unlocked root and a changed unit refuse.
This is source/file admission, not password, USB, boot or chroot acceptance.
