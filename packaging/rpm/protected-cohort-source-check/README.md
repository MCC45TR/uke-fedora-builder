# Uke protected-cohort source checks

This source group validates signed cohort constraints, Android Verified Boot
metadata, HWKM wrapped-key preparation, and QTEE application discovery. The
manifest binds its program, fixture and RPM recipe files. Use the original
upstream source identities in `packaging/` for libavb and the MINK adapter
when building the check in COPR on Fedora Rawhide AArch64.

The fixture targets test data and disposable records. Production boot and
storage decisions remain with their installed owners. See the
[signed-cohort format](docs/PROTECTED-COHORT-MANIFEST.md).
