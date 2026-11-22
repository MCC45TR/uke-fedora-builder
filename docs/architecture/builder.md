# Fedora builder architecture

The workspace's `ukelinux.sh` and the hosted scripts in `scripts/` invoke
the builder's shell entry points. The default image route resolves signed
Fedora and Uke COPR packages, verifies the Uke kernel cohort, assembles the
target filesystem and records artifact checksums. The explicit source route
uses the source and worker pins described in the [build guide](../PUBLIC-BUILD.md).

## Repository layout

| Path | Contents |
| --- | --- |
| `.github/workflows/` | Source contracts and manual build orchestration |
| `configs/` | Device, distribution, image, COPR and release settings |
| `containers/` | Containerfile recipes for host and target workers |
| `manifests/` | Pinned upstream sources and image RPM inventories |
| `packaging/rpm/` | Native helper RPM and its COPR source workers, plus the frozen kernel recipe |
| `references/` | Local upstream sources, bundles and firmware caches |
| `scripts/` | Host entry points for assembly and artifact publication |
| `src/` | Boot and initramfs integration, image stages, package helpers and audits |
| `tests/` | Source contracts, native package checks and host fixtures |
| `docs/` | Build guide, interface documentation and publication guides |

Image manifests bind the selected kernel source, RPM cohort, module ABI and
boot artifacts. Source checks, signed package composition, filesystem readback
and physical device results are separate stages with separate evidence.

## Source branches

`main` is the development branch. The
`archive/branch-consolidation-20261122/` tags retain the exact source of the
earlier Stable Fastboot, Pad 7 test, recovery development and SELinux
repository trials. Historical tags under `archive/2026-10-29/` retain their
original pins. See the commit referenced by a build or release for its
recipe and workflow. Recover a branch locally with
`git switch -c LOCAL_NAME archive/branch-consolidation-20261122/OLD_BRANCH`.
