Name:           uke-fastboot-host
Version:        37.0.0p1
Release:        1%{?dist}
Summary:        Host fastboot with numeric getvar whitespace normalization
License:        Apache-2.0 AND BSD-3-Clause AND GPL-2.0-or-later AND LGPL-2.1-or-later AND MIT AND LicenseRef-Fedora-Public-Domain
URL:            https://github.com/MCC45TR/uke-fedora-builder
Source0:        android-tools-37.0.0p1.tar.xz
Source1:        uke-fastboot-host-inputs.tar.xz
Source2:        source-identity.json
Patch0:         fastboot-partition-size-whitespace.patch
ExclusiveArch:  x86_64
%global debug_package %{nil}
BuildRequires:  gcc gcc-c++ cmake make ninja-build brotli-devel fmt-devel gtest-devel libusbx-devel libzstd-devel lz4-devel pcre2-devel protobuf-devel perl-interpreter
BuildRequires:  bash jq coreutils findutils diffutils socat zip android-tools git-core

%description
The original Fedora android-tools 37.0.0p1 source, building only fastboot with
one bounded change: trim whitespace in partition-size responses before exact
android-info requirement matching. All capacity, product, mode and slot checks
remain enabled. This host tool does not replace Fedora android-tools, does not
install device payloads and is not a tablet runtime dependency.

%prep
%setup -q -n android-tools-37.0.0p1
%patch -P 0 -p1
mkdir uke-inputs
tar -xJf %{SOURCE1} -C uke-inputs

%build
%cmake -DANDROID_TOOLS_ADB_ENABLE_MDNS:BOOL=OFF -DBUILD_SHARED_LIBS:BOOL=OFF
%cmake_build --target fastboot

%check
# The synthetic planner needs Git metadata, not a historical source checkout.
git -C uke-inputs init -q
git -C uke-inputs add .
git -C uke-inputs -c user.name='Uke parser fixture' -c user.email='mcc45tr@users.noreply.github.com' commit -qm 'Synthetic parser fixture inputs'
mkdir -p uke-test-bin
ln -s "$(realpath %{_vpath_builddir}/vendor/fastboot)" uke-test-bin/fastboot
PATH="$PWD/uke-test-bin:$PATH" bash uke-inputs/tests/fastboot-update-parser.sh "$PWD/host-fastboot-tests.json" --normalizes-partition-size
jq -e '.partition_size_response_whitespace_normalized and .padded_wrong_capacity_and_malformed_values_refused and .every_destination_size_checked_before_mutation and .initial_test_other_slot_refused_before_mutation' host-fastboot-tests.json

%install
install -Dm755 %{_vpath_builddir}/vendor/fastboot %{buildroot}%{_libexecdir}/uke-fastboot-host/fastboot
install -Dm644 host-fastboot-tests.json %{buildroot}%{_datadir}/uke-fastboot-host/qualification.json
install -m644 %{SOURCE2} %{buildroot}%{_datadir}/uke-fastboot-host/source-identity.json
# Retain the original source notices without shipping other Android programs.
find vendor -type f \( -name NOTICE -o -name 'NOTICE.*' -o -name LICENSE -o -name 'LICENSE.*' -o -name COPYING \) -print0 | sort -z > original-notices.list
tar --null -T original-notices.list -cJf original-notices.tar.xz

%files
%license original-notices.tar.xz
%{_libexecdir}/uke-fastboot-host
%{_datadir}/uke-fastboot-host
