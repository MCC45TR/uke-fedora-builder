Name:           uke-dtbo-tools-source-check
Version:        1.0
Release:        1%{?dist}
Summary:        Native source verification of the Uke DTBO v0 producer
License:        MIT AND Apache-2.0 AND BSD-3-Clause
URL:            https://github.com/MCC45TR/uke-fedora-builder
Source0:        %{name}-%{version}.tar.xz
Source1:        source-identity.json
Source2:        dtbo-upstream.tar.xz
ExclusiveArch:  aarch64
%global debug_package %{nil}
BuildRequires:  gcc binutils dtc libfdt-devel bash jq coreutils findutils diffutils util-linux ShellCheck

%description
Temporary receipts from native AArch64 COPR compilation of the original AOSP
mkdtimg v0 formatter and public disposable Device Tree fixtures. This package
contains text receipts and original license notices only. It installs no tool,
Python, service, firmware or boot hook and establishes no hardware admission.

%prep
%autosetup
mkdir upstream
tar -xJf %{SOURCE2} -C upstream
test "$(uname -m)" = aarch64

%build
%set_build_flags
mkdir build
# Original upstream C and POSIX sysdeps; original distribution libfdt provider.
gcc $CFLAGS -std=c11 -D_GNU_SOURCE -Wall -Wextra \
    -Iupstream/utils/src -Iupstream/sysdeps/include -Iupstream/external-dtc/libfdt \
    upstream/utils/src/{dt_table,mkdtimg,mkdtimg_cfg_create,mkdtimg_core,mkdtimg_create,mkdtimg_dump}.c \
    upstream/sysdeps/libufdt_sysdeps_posix.c upstream/external-dtc/libfdt/acpi.c \
    -o build/mkdtimg $LDFLAGS -lfdt

%check
bash -n src/image/inspect-dtbo-reference.sh tests/dtbo-producer.sh
shellcheck src/image/inspect-dtbo-reference.sh tests/dtbo-producer.sh
bash tests/dtbo-producer.sh build/mkdtimg src/image/inspect-dtbo-reference.sh build/native-dtbo.json
jq -e '.native_architecture=="aarch64" and .version_zero_layout_verified and .malformed_inventory_cases_refused==10' build/native-dtbo.json
sha256sum src/image/inspect-dtbo-reference.sh tests/dtbo-producer.sh \
    packaging/dtbo-tools-source.json packaging/uke-dtbo-tools-source-check.spec > build/project-native-sha256.txt
find upstream -type f -print0 | sort -z | xargs -0 sha256sum > build/upstream-native-sha256.txt
rpm -q gcc dtc libfdt libfdt-devel ShellCheck glibc > build/distribution-tools.txt
# Full original notices, including those embedded in C/header files.
tar --sort=name --mtime=@1794700800 --owner=0 --group=0 --numeric-owner \
    -cJf build/upstream-notices.tar.xz -C upstream .

%install
dest=%{buildroot}%{_datadir}/uke-dtbo-tools-source-check
mkdir -p "$dest"
install -m0644 build/{native-dtbo.json,project-native-sha256.txt,upstream-native-sha256.txt,distribution-tools.txt} "$dest/"
install -m0644 %{SOURCE1} "$dest/source-identity.json"
install -m0644 packaging/dtbo-tools-source.json "$dest/upstream-source.json"

%files
%license LICENSE build/upstream-notices.tar.xz
%{_datadir}/uke-dtbo-tools-source-check/

%changelog
* Sun Nov 15 2026 Uke Linux <uke-linux@users.noreply.github.com> - 1.0-1
- Verify the original native DTBO v0 formatter with public synthetic inputs.
