# Minimal installed-account rescue console

The rescue root keeps original Fedora packages and the matching signed kernel
cohort. Its disk root account stays locked and network listeners stay disabled.
No desktop, generic password, persistent credential or model is added.

The explicit `senemos.role=rescue` profile loads the already signed original
`g_serial` module. Its CDC ACM endpoint retains normal gadget ownership guards.
The terminal uses sane flags without imposing a UART baud rate: the live Uke
TTY kept 9600 and rejected a forced 115200 setting. Original sulogin handles
terminal input; the project glue does not poll hardware or receive passwords.

Before login, a private mount namespace selects the unique physical Uke UFS
userdata partition and mounts a provisioned EXT4 filesystem read-only without
journal replay. The enabled UID1000 primary account must belong to wheel.
Account databases must be bounded, regular, unlinked, root-owned and protected
against other-account writes. Duplicate or malformed identities and locked
hashes refuse. The installed filesystem is released before authentication.

A root-private systemd runtime directory holds a copy of the original rescue
`/etc`, preserving labels and relative links, with only its root shadow entry
replaced by the captured administrator hash. The copy is limited to 64 MiB;
free tmpfs must cover two copies plus a 32-MiB reserve. No credential goes to
disk. PID1 binds the directory read-only only for the original sulogin process.
Sulogin runs directly from systemd, retaining Fedora's normal login transition;
no custom SELinux allow rule, process-context override or force option is used.
A stop helper removes the labeled RAM files and systemd removes the empty
runtime directory. The persistent rescue account remains locked.

This division addresses two live SELinux refusals: a generic wrapper service
could authenticate but could not transition to the login shell; binding a file
onto `shadow_t` from PID1 was also denied. Binding the bounded labeled directory
uses Fedora's existing directory policy. Global `/etc` is unchanged.

After authentication, original filesystem, mount and chroot tools support
explicit repair. Userdata is initially unmounted in the rescue login namespace.
For a healthy EXT4 filesystem, an administrator can create `/mnt/installed` and
mount `/dev/disk/by-partlabel/userdata` there read-only with `ro,noload` before
inspection. Writable repair, API-filesystem bind mounts and chroot are explicit
administrator actions. Do not run filesystem repair against a mounted volume.

The initial identity method requires a readable plain EXT4 account database and
an enabled primary administrator. It does not unlock encrypted or unmountable
userdata. Independent recovery credentials, secure unlock, terminal rescue entry
and a reliable return path remain separate qualification work.

On running 7.3.4-4, a bounded USB service fixture refused an incorrect password,
accepted the existing administrator password and opened a UID0 maintenance shell
with SELinux Enforcing. The temporary `/etc` mount was read-only and private.
Exit removed the runtime tree; the global account stayed locked and the normal
Wayland session stayed active. The current system's `/etc` copy was about23 MB.
The fixture used a read-only bind of the already running userdata filesystem
because a second raw EXT4 mount cannot change its live superblock's RO state.
This validates actual CDC transport, password handling, service login transition
and cleanup, not independent rescue OS boot, offline userdata mount or chroot.

Before full-ZIP composition, `scripts/verify-rescue-console.sh` independently
reads the regular rescue EXT4 file with read-only debugfs. It compares all three
helpers, both units and module options with reviewed sources and checks root
ownership, executable/data permissions, the locked account, absence of human
accounts and activation links. A second whole-image hash proves no change.
For a resized filesystem extracted from super, the fourth argument supplies
its native super composition: canonical seed geometry, independent decode,
byte-match proof and actual expanded payload hash must pass. The full composer
binds both source and expanded hashes to the actual sparse super payload.
Source/file readback does not establish USB, password, boot or chroot acceptance.
