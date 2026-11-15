Name:           uke-dtbo-tools-source-check
Version:        1.0
Release:        3%{?dist}
Summary:        Native source verification of the Uke DTBO v0 producer
License:        MIT AND Apache-2.0 AND BSD-3-Clause AND BSD-2-Clause AND GPL-2.0-only AND GPL-2.0-or-later
URL:            https://github.com/MCC45TR/uke-fedora-builder
Source0:        %{name}-%{version}.tar.xz
Source1:        source-identity.json
Source2:        dtbo-upstream.tar.xz
Source3:        dtbo-merge-upstream.tar.xz
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
mkdir merge-upstream
tar -xJf %{SOURCE3} -C merge-upstream
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
# The distribution lacks the Qualcomm overlay-to-overlay merge API. Build its
# original private host library; do not replace the Fedora runtime provider.
mkdir build/merge-objects
# Upstream Makefile version 1.7.0 with a reproducible source-commit suffix.
printf '#define DTC_VERSION "DTC 1.7.0-c1197f56b8f4"\n' > build/merge-objects/version_gen.h
for source in fdt fdt_ro fdt_wip fdt_sw fdt_rw fdt_strerror fdt_empty_tree \
    fdt_addresses fdt_overlay fdt_check acpi; do
    gcc $CFLAGS -std=c11 -D_GNU_SOURCE -Imerge-upstream/libfdt \
        -c "merge-upstream/libfdt/$source.c" -o "build/merge-objects/$source.o"
done
gcc $CFLAGS -std=c11 -D_GNU_SOURCE -Imerge-upstream -Imerge-upstream/libfdt \
    -Ibuild/merge-objects merge-upstream/fdtoverlaymerge.c merge-upstream/util.c \
    build/merge-objects/*.o -o build/fdtoverlaymerge $LDFLAGS

# Receipts consumed by %%install must exist before that RPM stage.
bash -n src/image/inspect-dtbo-reference.sh tests/dtbo-producer.sh tests/dtbo-merge.sh
shellcheck src/image/inspect-dtbo-reference.sh tests/dtbo-producer.sh tests/dtbo-merge.sh
bash tests/dtbo-producer.sh build/mkdtimg src/image/inspect-dtbo-reference.sh build/native-dtbo.json
bash tests/dtbo-merge.sh build/fdtoverlaymerge build/mkdtimg build/native-dtbo-merge.json
jq -e '.native_architecture=="aarch64" and .version_zero_layout_verified and .malformed_inventory_cases_refused==10' build/native-dtbo.json
sha256sum src/image/inspect-dtbo-reference.sh tests/dtbo-producer.sh tests/dtbo-merge.sh \
    packaging/dtbo-tools-source.json packaging/dtbo-merge-source.json packaging/uke-dtbo-tools-source-check.spec > build/project-native-sha256.txt
find upstream -type f -print0 | sort -z | xargs -0 sha256sum > build/upstream-native-sha256.txt
find merge-upstream -type f -print0 | sort -z | xargs -0 sha256sum > build/merge-upstream-native-sha256.txt
rpm -q gcc dtc libfdt libfdt-devel ShellCheck glibc > build/distribution-tools.txt
# Full original notices, including those embedded in C/header files.
tar --sort=name --mtime=@1794700800 --owner=0 --group=0 --numeric-owner \
    -cJf build/upstream-notices.tar.xz -C upstream .
tar --sort=name --mtime=@1794700800 --owner=0 --group=0 --numeric-owner \
    -cJf build/merge-upstream-notices.tar.xz -C merge-upstream .

%check
jq -e '.version_zero_layout_verified and .payload_bytes_preserved and .repeat_output_identical and .malformed_inventory_cases_refused==10' build/native-dtbo.json
jq -e '.cross_layer_phandles_resolved and .board_root_metadata_preserved and .missing_layer_application_refused' build/native-dtbo-merge.json
sha256sum -c build/project-native-sha256.txt
sha256sum -c build/upstream-native-sha256.txt
sha256sum -c build/merge-upstream-native-sha256.txt

%install
dest=%{buildroot}%{_datadir}/uke-dtbo-tools-source-check
mkdir -p "$dest"
install -m0644 build/{native-dtbo.json,native-dtbo-merge.json,project-native-sha256.txt,upstream-native-sha256.txt,merge-upstream-native-sha256.txt,distribution-tools.txt} "$dest/"
install -m0644 %{SOURCE1} "$dest/source-identity.json"
install -m0644 packaging/dtbo-tools-source.json "$dest/upstream-source.json"
install -m0644 packaging/dtbo-merge-source.json "$dest/merge-upstream-source.json"

%files
%license LICENSE build/upstream-notices.tar.xz build/merge-upstream-notices.tar.xz
%{_datadir}/uke-dtbo-tools-source-check/

%changelog
* Sun Nov 15 2026 Uke Linux <uke-linux@users.noreply.github.com> - 1.0-3
- Check original Qualcomm overlay merging with cross-layer references.

* Sun Nov 15 2026 Uke Linux <uke-linux@users.noreply.github.com> - 1.0-2
- Produce test receipts before the RPM install stage consumes them.

* Sun Nov 15 2026 Uke Linux <uke-linux@users.noreply.github.com> - 1.0-1
- Verify the original native DTBO v0 formatter with public synthetic inputs.
