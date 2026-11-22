# COPR image assembly

`uke-image-tools` packages the native filesystem, Android sparse image and
payload verification helpers. Its COPR source worker lives in
[`packaging/rpm/image-tools/`](../../packaging/rpm/image-tools/). The worker
resolves the SDK and fixture package sets and records the verified public
Fedora RPM inputs. The guest uses native DNF, signature checks and disabled
networking. The build SDK stays on the build side.

[`src/public/copr-root-stage.sh`](../../src/public/copr-root-stage.sh) admits
an exact target set. The input manifest binds the request, each RPM's path,
SHA-256 and NEVRA, and the expected installed package inventory. The input set
also carries the pinned signing key and reviewed firmware manifest. A generic
image request requires an exact kernel cohort and excludes device-local inputs.

[`src/public/copr-image-stage.sh`](../../src/public/copr-image-stage.sh)
composes the selected filesystem and verifies its contents and metadata through
separate readback. The public [build guide](../PUBLIC-BUILD.md) describes the
current production entry points and supported image profiles.
