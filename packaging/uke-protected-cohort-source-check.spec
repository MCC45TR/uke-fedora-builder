Name:           uke-protected-cohort-source-check
Version:        1.0
Release:        6%{?dist}
Summary:        Native source verification of Uke AVB and signed cohort constraints
License:        MIT AND BSD-3-Clause
URL:            https://github.com/MCC45TR/uke-fedora-builder
Source0:        %{name}-%{version}.tar.xz
Source1:        source-identity.json
Source2:        libavb-ba2dec4b.tar.xz
Source3:        libavb-LICENSE
BuildArch:      noarch
BuildRequires:  gcc gcc-c++ binutils openssl-devel openssl json-devel bash jq coreutils findutils diffutils util-linux
# Upstream Fedora avbtool formats/signs disposable host fixtures only. Never
# install Python/avbtool or these native inspection executables on the target.
BuildRequires:  android-tools python3

%description
Temporary source-check receipts from native AArch64 COPR compilation and
OpenSSL interoperability. No admission executable or runtime service is packaged.
This does not qualify an OEM trust anchor, boot, key release or hibernation.

%prep
%autosetup
cp %{SOURCE3} libavb-LICENSE
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
mkdir -p build/upstream/libavb
tar -xJf %{SOURCE2} -C build/upstream/libavb
# Compile original upstream C as C, with its portable crypto/POSIX backend.
# Its unmodified unsupported ML-DSA backend returns failure; Uke accepts only
# the SHA256_RSA4096 profile and does not replace a verification routine.
for source in avb_crypto avb_descriptor avb_hash_descriptor avb_mldsa \
    avb_property_descriptor avb_rsa avb_sysdeps_posix avb_util avb_vbmeta_image \
    avb_version crypto/sha256_impl crypto/sha512_impl crypto/mldsa_impl; do
    gcc $CFLAGS -std=c11 -D_GNU_SOURCE -DAVB_COMPILATION \
        -Ibuild/upstream/libavb -Ibuild/upstream/libavb/crypto \
        -c "build/upstream/libavb/$source.c" -o "build/avb-${source//\//-}.o"
done
ar rcs build/libavb.a build/avb-*.o
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror -DUKE_COHORT_VBMETA_CLI \
    -Ibuild/upstream src/image/protected-cohort-{auth,manifest,vbmeta}.cpp \
    build/libavb.a -o build/cohort-vbmeta $LDFLAGS -lcrypto
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror -Ibuild/upstream -c \
    src/image/protected-cohort-vbmeta.cpp -o build/cohort-vbmeta.o

# Native tests produce the receipts that the install stage packages. RPM runs
# %%install before %%check, so these must exist before entering %%install.
readelf -h build/cohort-auth | grep -E 'Machine:.*AArch64'
bash tests/protected-cohort-auth.sh build/cohort-auth "$PWD/build/native-result.json"
readelf -h build/cohort-manifest | grep -E 'Machine:.*AArch64'
bash tests/protected-cohort-manifest.sh build/cohort-manifest "$PWD/build/manifest-result.json"
readelf -h build/cohort-vbmeta | grep -E 'Machine:.*AArch64'
bash tests/protected-cohort-vbmeta.sh build/cohort-vbmeta "$PWD/build/vbmeta-result.json"
rpm -q openssl openssl-libs json-devel gcc-c++ android-tools python3 > build/original-tools.txt
sha256sum src/image/protected-cohort-{auth,manifest,vbmeta}.* tests/protected-cohort-{auth,manifest,vbmeta}.sh \
    src/image/{fastboot-singleboot-layout,rescue-verity-layout}.sh > build/source-sha256.txt
find build/upstream/libavb -type f -print0 | sort -z | xargs -0 sha256sum > build/upstream-sha256.txt

%check
jq -e '.openssl_interoperability and .refused_cases==27 and .exact_limit_passed and
    .original_inputs_unchanged and (.role_admitted|not) and (.snapshot_authenticated|not)' build/native-result.json
jq -e '.real_signature_then_semantic_validation and .signed_invalid_cases_refused==64 and
    .decoded_duplicate_keys_refused and .all_listed_geometries_validated and
    (.boot_payloads_verified|not) and (.role_admitted|not)' build/manifest-result.json
jq -e '.original_fedora_avbtool_interoperability and .outer_avb_and_inner_pss_verified and
    .refused_cases==35 and .typed_manifest_and_hash_descriptor_sizes_bound and
    (.rollback_state_verified|not) and (.role_admitted|not)' build/vbmeta-result.json

%install
install -d %{buildroot}%{_datadir}/%{name}
install -pm644 build/native-result.json build/original-tools.txt build/source-sha256.txt \
    build/manifest-result.json build/vbmeta-result.json build/upstream-sha256.txt \
    %{SOURCE1} %{buildroot}%{_datadir}/%{name}/

%files
%license LICENSE libavb-LICENSE
%{_datadir}/%{name}/

%changelog
* Sun Nov 15 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0-6
- Stage the upstream license in the build directory before packaging.

* Sun Nov 15 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0-5
- Pin every upstream blob before generating the source archive.

* Sun Nov 15 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0-4
- Verify the external AVB carrier using original libavb and Fedora avbtool fixtures.

* Sun Nov 15 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0-3
- Validate signed manifest schemas, immutable kernel contexts and exact storage geometry.

* Sun Nov 15 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0-2
- Produce native test receipts before the RPM install stage.

* Sun Nov 15 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0-1
- Compile the production verifier and check detached signatures and bounded input refusal.
