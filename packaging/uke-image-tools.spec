Name:           uke-image-tools
Version:        1.0.0
Release:        1%{?dist}
Summary:        Native tools for isolated Uke image assembly and verification
License:        MIT
URL:            https://github.com/MCC45TR/uke-fedora-builder
Source0:        %{name}-%{version}.tar.xz
Source1:        source-identity.json
ExclusiveArch:  aarch64
BuildRequires:  gcc-c++ e2fsprogs-devel libselinux-devel openssl-devel libzstd-devel
BuildRequires:  bash jq coreutils findutils diffutils grep sed gawk tar xz cpio
BuildRequires:  rpm-build ripgrep dtc git-core make f2fs-tools e2fsprogs xfsprogs btrfs-progs zstd

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

%install
install -d %{buildroot}%{_libexecdir}/%{name}
install -pm755 build-tools/* %{buildroot}%{_libexecdir}/%{name}/
install -Dm644 %{SOURCE1} %{buildroot}%{_datadir}/%{name}/source-identity.json

%check
bash tests/public-build-contract.sh
bash tests/public-channel-contract.sh
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
* Fri Oct 30 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0.0-1
- Build image helpers and native file fixtures in COPR for signed assembly inputs.
