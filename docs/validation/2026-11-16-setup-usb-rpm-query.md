# First-setup USB capability query

On 16 November 2026 the native AArch64 image assembly stopped before creating
its temporary USB marker. The installed Control 2.17.0-23 package provides
`uke-control(setup-cdc-v1) = 1`, but RPM's `--whatprovides` rejects a DNF-style
`name >= version` argument. The same queries against the running tablet
returned 1 for the expression and 0 for the capability name.

Query the capability name and inspect the actual RPM header for the exact
versioned v1 interface. Keep the executable, unit, directory ownership,
permissions and activation-marker checks. Report a specific error when a gate
refuses the new image. The offline fixture now rejects missing, unversioned,
wrong-version and inequality capabilities before any activation marker exists.
The real installed package passes the corrected header query. Native image
assembly remains the integration check; these results do not qualify a physical
first-setup USB boot or wizard completion.
