Name:           uke-protected-cohort-source-check
Version:        1.0
Release:        9%{?dist}
Summary:        Native source verification of Uke AVB and signed cohort constraints
License:        MIT AND BSD-3-Clause
URL:            https://github.com/MCC45TR/uke-fedora-builder
Source0:        %{name}-%{version}.tar.xz
Source1:        source-identity.json
Source2:        libavb-ba2dec4b.tar.xz
Source3:        libavb-LICENSE
ExclusiveArch:  aarch64
%global debug_package %{nil}
BuildRequires:  gcc gcc-c++ binutils openssl-devel openssl bash jq coreutils findutils diffutils util-linux
BuildRequires:  json-devel = 3.12.0
# Upstream Fedora avbtool formats/signs disposable COPR-host fixtures only.
# Python and avbtool are never target payloads; the descriptor inspection
# frontend is an explicit temporary diagnostic, never an admission policy.
BuildRequires:  android-tools python3
Requires:       bash jq coreutils findutils util-linux-core

%description
Temporary source-check receipts and a descriptor inspection executable from
native AArch64 COPR compilation. Public disposable fixtures support a bounded
owned-loop block-I/O test without a formatter or Python on the target. The
executable grants no admission, key release, boot selection or runtime service.
No physical UFS or OEM trust qualification follows from these test fixtures.

%prep
%autosetup
cp %{SOURCE3} libavb-LICENSE
cp /usr/share/licenses/json-devel/LICENSE.MIT nlohmann-json-LICENSE.MIT
echo '46a65cffd1ea955132d95a8dd921640714a8d6b537d2e4e482d31145ae95b603  nlohmann-json-LICENSE.MIT' | sha256sum -c -
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
touch build/libavb-license-inputs.txt
# Compile original upstream C as C, with its portable crypto/POSIX backend.
# Its unmodified unsupported ML-DSA backend returns failure; Uke accepts only
# the SHA256_RSA4096 profile and does not replace a verification routine.
for source in avb_crypto avb_descriptor avb_hash_descriptor avb_mldsa \
    avb_property_descriptor avb_rsa avb_sysdeps_posix avb_util avb_vbmeta_image \
    avb_version crypto/sha256_impl crypto/sha512_impl crypto/mldsa_impl; do
    gcc $CFLAGS -std=c11 -D_GNU_SOURCE -DAVB_COMPILATION \
        -Ibuild/upstream/libavb -Ibuild/upstream/libavb/crypto \
        -c "build/upstream/libavb/$source.c" -o "build/avb-${source//\//-}.o"
    printf '%%s.c\n' "$source" >> build/libavb-license-inputs.txt
done
# Retain the original copyright/permission notices, including the embedded
# Chromium/Olivier Gay routines and the JSON headers' internal attributions.
# These small original-source archives avoid truncating a multi-part notice.
find build/upstream/libavb -type f -name '*.h' -printf '%%P\n' >> build/libavb-license-inputs.txt
sort -u -o build/libavb-license-inputs.txt build/libavb-license-inputs.txt
test "$(grep -c '[.]c$' build/libavb-license-inputs.txt)" = 13
if grep -Fx avb_crc32.c build/libavb-license-inputs.txt; then exit 1; fi
tar --sort=name --mtime=@1794700800 --owner=0 --group=0 --numeric-owner \
    -cJf build/libavb-notices.tar.xz -C build/upstream/libavb -T "$PWD/build/libavb-license-inputs.txt"
test -z "$(find /usr/include/nlohmann -type l -print -quit)"
tar --sort=name --mtime=@1794700800 --owner=0 --group=0 --numeric-owner \
    -cJf build/json-header-notices.tar.xz -C /usr/include nlohmann
sha256sum nlohmann-json-LICENSE.MIT build/{libavb-notices,json-header-notices}.tar.xz \
    > build/third-party-license-sha256.txt
ar rcs build/libavb.a build/avb-*.o
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror -DUKE_COHORT_VBMETA_CLI \
    -Ibuild/upstream src/image/protected-cohort-{auth,manifest,vbmeta}.cpp \
    build/libavb.a -o build/cohort-vbmeta $LDFLAGS -lcrypto
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror -Ibuild/upstream -c \
    src/image/protected-cohort-vbmeta.cpp -o build/cohort-vbmeta.o
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror -DUKE_COHORT_CONTENT_CLI \
    -Ibuild/upstream src/image/protected-cohort-{auth,manifest,vbmeta,content}.cpp \
    build/libavb.a -o build/cohort-content $LDFLAGS -lcrypto
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror -Ibuild/upstream -c \
    src/image/protected-cohort-content.cpp -o build/cohort-content.o
g++ $CXXFLAGS -std=c++20 -Wall -Wextra -Werror src/boot/boot-image.cpp \
    -o build/boot-image $LDFLAGS

# Native tests produce the receipts that the install stage packages. RPM runs
# %%install before %%check, so these must exist before entering %%install.
readelf -h build/cohort-auth | grep -E 'Machine:.*AArch64'
bash tests/protected-cohort-auth.sh build/cohort-auth "$PWD/build/native-result.json"
readelf -h build/cohort-manifest | grep -E 'Machine:.*AArch64'
bash tests/protected-cohort-manifest.sh build/cohort-manifest "$PWD/build/manifest-result.json"
readelf -h build/cohort-vbmeta | grep -E 'Machine:.*AArch64'
bash tests/protected-cohort-vbmeta.sh build/cohort-vbmeta "$PWD/build/vbmeta-result.json"
readelf -h build/cohort-content | grep -E 'Machine:.*AArch64'
bash tests/protected-cohort-content.sh build/cohort-content build/boot-image "$PWD/build/content-result.json" "$PWD/build/content-fixture"
rpm -q openssl openssl-libs json-devel gcc-c++ android-tools python3 > build/original-tools.txt
sha256sum src/image/protected-cohort-{auth,manifest,vbmeta,content}.* tests/protected-cohort-{auth,manifest,vbmeta,content}.sh \
    src/image/{fastboot-singleboot-layout,rescue-verity-layout}.sh src/boot/boot-image.cpp \
    tests/protected-cohort-blocks.sh > build/source-sha256.txt
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
jq -e '.real_signed_metadata_then_fd_content_verification and .refused_cases==31 and
    .partial_duplicate_failure_cleaned_up and .large_streaming_result.peak_rss_kib<65536 and
    (.physical_block_branch_tested|not) and (.role_admitted|not)' build/content-result.json
(cd build/content-fixture; sha256sum -c SHA256SUMS)
test "$(find build/content-fixture -type f | wc -l)" = 6
test ! -e build/content-fixture/key.pem

%install
install -d %{buildroot}%{_datadir}/%{name}
install -pm644 build/native-result.json build/original-tools.txt build/source-sha256.txt \
    build/manifest-result.json build/vbmeta-result.json build/content-result.json build/upstream-sha256.txt \
    build/third-party-license-sha256.txt \
    %{SOURCE1} %{buildroot}%{_datadir}/%{name}/
install -d %{buildroot}%{_libexecdir}/%{name} %{buildroot}%{_datadir}/%{name}/fixtures
install -pm755 build/cohort-content %{buildroot}%{_libexecdir}/%{name}/cohort-content-inspect
install -pm755 tests/protected-cohort-blocks.sh %{buildroot}%{_libexecdir}/%{name}/owned-block-fixture
install -pm644 build/content-fixture/* %{buildroot}%{_datadir}/%{name}/fixtures/

%files
%license LICENSE libavb-LICENSE nlohmann-json-LICENSE.MIT build/libavb-notices.tar.xz build/json-header-notices.tar.xz
%{_datadir}/%{name}/
%{_libexecdir}/%{name}/

%changelog
* Sun Nov 15 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0-9
- Retain original JSON and libavb source copyright and permission notices in the diagnostic RPM.

* Sun Nov 15 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0-8
- Supply a temporary native inspection tool and public fixtures for owned-loop qualification.

* Sun Nov 15 2026 Uke Maintainers <75160848+MCC45TR@users.noreply.github.com> - 1.0-7
- Verify signed boot prefixes and the raw ARM64 kernel slice through owned read-only descriptors.

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
