Name:           uke-protected-cohort-source-check
Version:        1.0
Release:        3%{?dist}
Summary:        Native source verification of Uke cohort signatures and manifest constraints
License:        MIT
URL:            https://github.com/MCC45TR/uke-fedora-builder
Source0:        %{name}-%{version}.tar.xz
Source1:        source-identity.json
BuildArch:      noarch
BuildRequires:  gcc-c++ openssl-devel openssl json-devel bash jq coreutils findutils diffutils util-linux

%description
Temporary source-check receipts from native AArch64 COPR compilation and
OpenSSL interoperability. No admission executable or runtime service is packaged.
This does not qualify an OEM trust anchor, boot, key release or hibernation.

%prep
%autosetup
test "$(uname -m)" = aarch64

%build
%set_build_flags
mkdir build
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror -DUKE_COHORT_AUTH_CLI \
    src/image/protected-cohort-auth.cpp -o build/cohort-auth $LDFLAGS -lcrypto
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror -c \
    src/image/protected-cohort-auth.cpp -o build/cohort-auth.o
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror -DUKE_COHORT_MANIFEST_CLI \
    src/image/protected-cohort-auth.cpp src/image/protected-cohort-manifest.cpp \
    -o build/cohort-manifest $LDFLAGS -lcrypto
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror -c \
    src/image/protected-cohort-manifest.cpp -o build/cohort-manifest.o

# Native tests produce the receipts that the install stage packages. RPM runs
# %%install before %%check, so these must exist before entering %%install.
readelf -h build/cohort-auth | grep -E 'Machine:.*AArch64'
bash tests/protected-cohort-auth.sh build/cohort-auth "$PWD/build/native-result.json"
readelf -h build/cohort-manifest | grep -E 'Machine:.*AArch64'
bash tests/protected-cohort-manifest.sh build/cohort-manifest "$PWD/build/manifest-result.json"
rpm -q openssl openssl-libs json-devel gcc-c++ > build/original-tools.txt
sha256sum src/image/protected-cohort-{auth,manifest}.* tests/protected-cohort-{auth,manifest}.sh \
    src/image/{fastboot-singleboot-layout,rescue-verity-layout}.sh > build/source-sha256.txt

%check
jq -e '.openssl_interoperability and .refused_cases==27 and .exact_limit_passed and
    .original_inputs_unchanged and (.role_admitted|not) and (.snapshot_authenticated|not)' build/native-result.json
jq -e '.real_signature_then_semantic_validation and .signed_invalid_cases_refused==64 and
    .decoded_duplicate_keys_refused and .all_listed_geometries_validated and
    (.boot_payloads_verified|not) and (.role_admitted|not)' build/manifest-result.json

%install
install -d %{buildroot}%{_datadir}/%{name}
install -pm644 build/native-result.json build/original-tools.txt build/source-sha256.txt \
    build/manifest-result.json %{SOURCE1} %{buildroot}%{_datadir}/%{name}/

%files
%license LICENSE
%{_datadir}/%{name}/

%changelog
* Sun Nov 15 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0-3
- Validate signed manifest schemas, immutable kernel contexts and exact storage geometry.

* Sun Nov 15 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0-2
- Produce native test receipts before the RPM install stage.

* Sun Nov 15 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0-1
- Compile the production verifier and check detached signatures and bounded input refusal.
