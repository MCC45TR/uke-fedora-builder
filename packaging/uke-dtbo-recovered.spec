Name: uke-senemos-dtbo
Version: 1.0
Release: 1%{?dist}
Summary: Complete recovered-source Uke DTBO payload for coordinated boot updates
License: MIT AND Apache-2.0 AND BSD-3-Clause AND LicenseRef-Proprietary
Source0: public-dt-reference.tar.xz
Source1: dtbo-reference-roundtrip.sh
Source2: dtbo-roundtrip-source.json
Source3: dtbo-upstream.tar.xz
Source4: dtbo-producer.sh
Source5: inspect-dtbo-reference.sh
Source6: dtbo-tools-source.json
Source7: dtbo-recovered-qualification.json
Source8: package-recovered-dtbo.sh
ExclusiveArch: aarch64
%global debug_package %{nil}
BuildRequires: gcc binutils dtc libfdt-devel bash jq coreutils findutils diffutils tar xz
Provides: uke-dtbo(recovered-source-cohort-v1) = 1

%description
One common DTBO reconstructed from complete pinned public flattened Uke sources.
Native tests require the complete tree/property content, reservations, boot CPU
and all four applied public trees to match, then use the original AOSP formatter
with the actual payload length. The original OEM source closure remains open.

This package supplies a data payload to the existing coordinated boot updater.
It installs no daemon, executable, vendor_boot base replacement or partition
write hook. DNF installation does not flash either slot; physical acceptance and
coordinated A/B delivery remain separate requirements.

%prep
mkdir inputs upstream
tar -xJf %{SOURCE0} -C inputs
tar -xJf %{SOURCE3} -C upstream
(cd upstream;jq -r '.files[]|.sha256+"  "+.path' %{SOURCE6} | sha256sum -c --strict --quiet -)
(cd upstream;jq -r '.additional_sources[]|.sha256+"  "+.archive_path' %{SOURCE6} | sha256sum -c --strict --quiet -)

%build
%set_build_flags
gcc $CFLAGS -std=c11 -D_GNU_SOURCE -Wall -Wextra \
 -Iupstream/utils/src -Iupstream/sysdeps/include -Iupstream/external-dtc/libfdt \
 upstream/utils/src/{dt_table,mkdtimg,mkdtimg_cfg_create,mkdtimg_core,mkdtimg_create,mkdtimg_dump}.c \
 upstream/sysdeps/libufdt_sysdeps_posix.c upstream/external-dtc/libfdt/acpi.c \
 -o mkdtimg $LDFLAGS -lfdt
bash %{SOURCE4} "$PWD/mkdtimg" %{SOURCE5} "$PWD/formatter.json"
bash %{SOURCE1} "$PWD/inputs" %{SOURCE2} "$PWD/recovered"
bash %{SOURCE8} "$PWD/mkdtimg" %{SOURCE5} "$PWD/recovered" %{SOURCE7} "$PWD/cohort"
sha256sum cohort/{dtbo.img,source-cohort.json} > payload.sha256

%check
jq -e '.version_zero_layout_verified and .repeat_output_identical and .malformed_inventory_cases_refused==10 and .invalid_fdt_formatter_refused' formatter.json
jq -e '.common_dtbo and .reconstructed_flattened_source and (.original_oem_source_reproduction|not) and (.public_bases_packaged_for_vendor_boot|not) and (.automatic_partition_writes|not) and (.physical_boot_qualified|not)' cohort/source-cohort.json
sha256sum -c --strict --quiet payload.sha256

%install
install -d %{buildroot}%{_prefix}/lib/senemos/dtbo
install -m644 cohort/{dtbo.img,source-cohort.json} %{SOURCE7} %{buildroot}%{_prefix}/lib/senemos/dtbo/
install -Dm644 upstream/NOTICE %{buildroot}%{_licensedir}/%{name}/NOTICE
install -Dm644 %{SOURCE2} %{buildroot}%{_docdir}/%{name}/reference.json
install -m644 formatter.json recovered/report.json %{buildroot}%{_docdir}/%{name}/

%files
%{_prefix}/lib/senemos/dtbo
%{_docdir}/%{name}
%license %{_licensedir}/%{name}/NOTICE

%changelog
* Mon Nov 16 2026 Uke contributors - 1.0-1
- Package the complete recovered-source overlay with a verified v0 transport; leave partition writes to coordinated delivery.
