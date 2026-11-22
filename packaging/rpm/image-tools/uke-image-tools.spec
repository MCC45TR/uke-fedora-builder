Name:           uke-image-tools
Version:        1.0.0
Release:        26%{?dist}
Summary:        Native tools for isolated Uke image assembly and verification
License:        MIT
URL:            https://github.com/MCC45TR/uke-fedora-builder
Source0:        %{name}-%{version}.tar.xz
Source1:        source-identity.json
Source2:        guest-fedora-inputs.tar.xz
ExclusiveArch:  aarch64
BuildRequires:  gcc-c++ e2fsprogs-devel libselinux-devel openssl-devel libzstd-devel
BuildRequires:  bash jq coreutils findutils diffutils grep sed gawk tar xz cpio
BuildRequires:  rpm-build ripgrep dtc git-core make f2fs-tools e2fsprogs xfsprogs btrfs-progs zstd
BuildRequires:  util-linux-core util-linux shadow-utils
BuildRequires:  libguestfs-tools-c kernel-core kernel-modules qemu-kvm-core
BuildRequires:  bsdtar gnupg2 createrepo_c
BuildRequires:  android-tools
BuildRequires:  libarchive-devel

%description
Image codecs, payload validation, language auditing and offline EXT4 labels.
These host tools operate on supplied image files. They do not activate kernels,
flash partitions or qualify tablet hardware. Build and native tests run in COPR.

%prep
%autosetup

%build
%set_build_flags
mkdir -p build-tools
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror src/boot/boot-image.cpp -o build-tools/boot-image $LDFLAGS
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror src/boot-pair/android-sparse.cpp -o build-tools/android-sparse $LDFLAGS
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror src/image/ext4-labels.cpp -o build-tools/ext4-labels $LDFLAGS -lext2fs -lcom_err -lselinux
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror src/image/check-userdata-payload.cpp -o build-tools/check-userdata-payload $LDFLAGS -lcrypto -lzstd
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror src/image/audit-languages.cpp -o build-tools/audit-languages $LDFLAGS
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror src/image/compare-root-metadata.cpp -o build-tools/compare-root-metadata $LDFLAGS
mkdir -p build-fixtures
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror src/build/cpio-sdk-tar.cpp -o build-fixtures/cpio-sdk-tar $LDFLAGS -larchive

%install
install -d %{buildroot}%{_libexecdir}/%{name}
install -pm755 build-tools/* %{buildroot}%{_libexecdir}/%{name}/
install -Dm644 %{SOURCE1} %{buildroot}%{_datadir}/%{name}/source-identity.json

%check
echo "$(jq -er .guest_inputs_sha256 %{SOURCE1})  %{SOURCE2}" | sha256sum -c -
mkdir guest-inputs
tar -xJf %{SOURCE2} -C guest-inputs
jq -es 'length==12 and all(.[];.goal_resolved and .metadata_only and (.installed==false) and (.rpm_downloaded==false) and (.full_os_composition==false) and (.hardware_tested==false))' guest-inputs/closures/full-root/*/report.json
UKE_COPR_WORKER_AUDIT=1 bash tests/copr-image-appliance.sh
UKE_COPR_WORKER_AUDIT=1 bash src/public/copr-guest-root.sh "$PWD" "$PWD/guest-inputs"
UKE_COPR_WORKER_AUDIT=1 bash tests/copr-image-worker.sh
bash tests/public-build-contract.sh
bash tests/public-channel-contract.sh
bash tests/public-root-transaction.sh
bash tests/image-contract.sh
bash tests/boot-contract.sh
bash tests/boot-pair-contract.sh
bash tests/boot-pair-serial-contract.sh
bash tests/initramfs-module-tuple.sh
bash tests/kernel-config-contract.sh
bash tests/kernel-export-contract.sh
bash tests/original-kde-payload.sh
bash tests/kernel-dt-admission.sh
bash tests/ext4-labels-contract.sh build-tools/ext4-labels
bash tests/boot-image-contract.sh build-tools/boot-image
bash tests/userdata-payload-contract.sh build-tools/check-userdata-payload build-tools/boot-image
bash tests/userdata-filesystem-payload.sh build-tools/check-userdata-payload build-tools/boot-image
bash tests/android-sparse-contract.sh build-tools/android-sparse "$PWD/build-tools/sparse-fixtures"

%files
%license LICENSE
%doc docs/PUBLIC-BUILD.md
%{_libexecdir}/%{name}/
%{_datadir}/%{name}/source-identity.json

%changelog
* Sat Oct 31 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-26
- Use the Btrfs rescue=nologreplay readback option.
- Probe every production read-only mount option before target installation.

* Sat Oct 31 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-25
- Verify target-policy labels on the staging tree and preserve them in archives.
- Restore SELinux archive metadata for every declared filesystem.

* Sat Oct 31 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-24
- Mount the declared filesystem in the repeated-format appliance probe.
- Retain appliance kernel and command diagnostics if a probe fails.

* Sat Oct 31 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-23
- Use official HTTPS Rawhide mirrors and refresh the SDK cohort before download.

* Sat Oct 31 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-22
- Include every declared formatter in a private appliance and probe it before root installation.

* Sat Oct 31 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-21
- Validate every reported layer of an existing SDK virtual mount.

* Sat Oct 31 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-20
- Preserve appliance virtual mounts below owned SDK mount layers.

* Sat Oct 31 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-19
- Retain early SDK admission and mount diagnostics for full filesystem failures.

* Sat Oct 31 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-18
- Compose and independently verify every declared filesystem through the COPR SDK.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-17
- Resolve the complete desktop against the requested Linux 7.3.1-3 tuple.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-16
- Refuse ambiguous repeated NEVRAs in complete frozen root catalogs.
- Keep frozen repository URLs out of the delivered root and match its requested kernel source.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-15
- Share the SDK transport with the complete offline production root entry.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-14
- Select the standalone Uke PipeWire providers required by unstable Core.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-13
- Resolve complete production desktop goals before accepting guest image inputs.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-12
- Preserve exact source mtimes and retain failed readback diagnostics.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-11
- Preserve CPIO data-last hard links while bootstrapping the disposable SDK.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-10
- Place the transaction-store option on its install command.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-9
- Prefetch complete SDK and target transactions with conditional dependencies.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-8
- Populate EXT4 from the owned guest root and check labels, metadata and sparse readback.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-7
- Use Fedora's shipped tmpfiles rule to validate ghost state directory ownership.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-6
- Prepare virtual filesystems inside the appliance before native RPM scriptlets.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-5
- Declare the official Rawhide repository in the isolated source worker.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-4
- Check the shared root transaction with signed offline Fedora inputs in a TCG guest.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-3
- Probe an unprivileged TCG appliance with numeric owners, labels and separate readback.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-2
- Record bounded COPR namespace and numeric-owner prerequisites without changing worker policy.

* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-1
- Build image helpers and native file fixtures in COPR for signed assembly inputs.
