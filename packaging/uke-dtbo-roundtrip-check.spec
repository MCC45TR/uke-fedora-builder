Name: uke-dtbo-tools-source-check
Version: 1.0
Release: 10%{?dist}
Summary: Native recovery of complete public Uke flattened Device Tree sources
License: MIT AND LicenseRef-Proprietary
Source0: public-dt-reference.tar.xz
Source1: dtbo-reference-roundtrip.sh
Source2: dtbo-roundtrip-source.json
ExclusiveArch: aarch64
%global debug_package %{nil}
BuildRequires: dtc libfdt bash jq coreutils findutils diffutils tar xz

%description
Diagnostic recovery of DTS text from pinned complete public DTBO/base references.
Original Fedora DTC must preserve full canonical tree content and boot CPU.
Binary layout differences are reported separately. This is distinct from
reproducing the original OEM source layers or admitting a physical update.
The package contains references and receipts only, with no daemon, executable
or partition-writing hook. Public bases do not replace installed vendor_boot.

%prep
mkdir inputs
tar -xJf %{SOURCE0} -C inputs

%build
bash %{SOURCE1} "$PWD/inputs" %{SOURCE2} "$PWD/result"

%check
jq -e '.overlay_and_bases_full_canonical_content_identical and .boot_cpu_headers_preserved and .all_four_applied_canonical_trees_identical and .wrong_model_boot_cpu_and_reserved_memory_refused and (.dtbo_transport_produced|not) and (.original_oem_source_reproduction|not) and (.physical_update_qualified|not)' result/report.json
(cd result;sha256sum -c --strict --quiet output.sha256)
(cd result;sha256sum -c --strict --quiet applied.sha256)

%install
install -d %{buildroot}%{_datadir}/%{name}
cp -a result/{source,rebuilt,report.json,output.sha256,applied.sha256,distribution-tools.txt} %{buildroot}%{_datadir}/%{name}/
install -m644 %{SOURCE2} %{buildroot}%{_datadir}/%{name}/reference.json

%files
%{_datadir}/%{name}

%changelog
* Mon Nov 16 2026 Uke contributors - 1.0-10
- Place the reservation refusal fixture after plugin headers and report the failing native stage.

* Mon Nov 16 2026 Uke contributors - 1.0-9
- Compare full flattened content and boot CPU; report serialization differences without producing a DTBO transport.
