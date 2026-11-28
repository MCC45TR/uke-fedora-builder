// SPDX-License-Identifier: MIT
#pragma once
#include "protected-cohort-manifest.hpp"
#include <array>
#include <cstdint>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace uke::protected_boot {
struct VbmetaTrustPins {
    // SHA256 of the exact AVB-encoded public key, distinct from DER SPKI.
    std::string avb_key_sha256;
    std::string cohort_spki_sha256;
};
struct AvbBootHash {
    uint64_t image_bytes;
    std::array<unsigned char, 32> salt, digest;
};
struct AblBootVersion {
    uint32_t os_version;
    uint32_t security_patch;
};
struct KeyMintVersionBinding {
    uint32_t os_version;
    uint32_t os_patchlevel;
    uint32_t vendor_patchlevel;
    std::optional<AblBootVersion> abl_boot;
};

class VerifiedVbmetaCohort {
public:
    VerifiedVbmetaCohort(const VerifiedVbmetaCohort&) = default;
    VerifiedVbmetaCohort(VerifiedVbmetaCohort&&) noexcept = default;
    VerifiedVbmetaCohort& operator=(const VerifiedVbmetaCohort&) = default;
    VerifiedVbmetaCohort& operator=(VerifiedVbmetaCohort&&) noexcept = default;
    const ValidatedCohortManifest& manifest() const noexcept { return manifest_; }
    const ObservedBootGeometry& observed_geometry() const noexcept { return observed_; }
    // Fixed order: boot, vendor_boot, dtbo. These are signed expected hashes;
    // an independent bounded physical read still has to compare actual bytes.
    const std::array<AvbBootHash, 3>& boot_hashes() const noexcept { return boot_hashes_; }
    const std::string& vbmeta_sha256() const noexcept { return vbmeta_sha256_; }
    uint64_t signed_rollback_index() const noexcept { return rollback_index_; }
    // Authenticated metadata. Releasing a key also requires an admitted boot.
    const std::optional<KeyMintVersionBinding>& keymint_version_binding() const noexcept { return keymint_; }
    // Prepare the fitted QTEE Configure frame only when the bootloader
    // digest matches this signature-checked, unchained VBMeta and the paired
    // ABL/KeyMint metadata is present. The caller owns digest provenance.
    // Transmission and authorization to release a key are separate.
    std::vector<unsigned char> prepare_keymint_configure(std::string_view bootloader_digest) const;
private:
    VerifiedVbmetaCohort(ValidatedCohortManifest manifest, std::array<AvbBootHash, 3> hashes, ObservedBootGeometry observed,
                         std::string digest, uint64_t rollback, std::optional<KeyMintVersionBinding> keymint)
        : manifest_(std::move(manifest)), boot_hashes_(std::move(hashes)), observed_(observed),
          vbmeta_sha256_(std::move(digest)), rollback_index_(rollback), keymint_(keymint) {}
    ValidatedCohortManifest manifest_;
    std::array<AvbBootHash, 3> boot_hashes_;
    ObservedBootGeometry observed_;
    std::string vbmeta_sha256_;
    uint64_t rollback_index_;
    std::optional<KeyMintVersionBinding> keymint_;
    friend VerifiedVbmetaCohort verify_vbmeta_cohort_bytes(std::span<const unsigned char>,
                                                          const VbmetaTrustPins&,
                                                          const ImmutableKernelContext&,
                                                          const ObservedBootGeometry&);
};

// Uses unmodified upstream libavb for the outer AVB signature, then existing
// PSS and manifest validators on its exact property bytes. Does not verify
// actual boot partition contents, an OEM anchor or protected rollback state.
VerifiedVbmetaCohort verify_vbmeta_cohort_bytes(std::span<const unsigned char> candidate,
                                              const VbmetaTrustPins& trusted,
                                              const ImmutableKernelContext& expected,
                                              const ObservedBootGeometry& observed);

struct OwnedVbmetaDescriptor;
class VerifiedVbmetaFd {
public:
    ~VerifiedVbmetaFd();
    VerifiedVbmetaFd(VerifiedVbmetaFd&&) noexcept;
    VerifiedVbmetaFd& operator=(VerifiedVbmetaFd&&) noexcept;
    VerifiedVbmetaFd(const VerifiedVbmetaFd&) = delete;
    VerifiedVbmetaFd& operator=(const VerifiedVbmetaFd&) = delete;
    const VerifiedVbmetaCohort& cohort() const noexcept { return cohort_; }
    bool block_input() const noexcept { return block_; }
private:
    VerifiedVbmetaFd(VerifiedVbmetaCohort, std::unique_ptr<OwnedVbmetaDescriptor>, bool);
    VerifiedVbmetaCohort cohort_;
    std::unique_ptr<OwnedVbmetaDescriptor> descriptor_;
    bool block_;
    friend VerifiedVbmetaFd verify_vbmeta_cohort_fd(int, uint64_t, const VbmetaTrustPins&,
                                                   const ImmutableKernelContext&, const ObservedBootGeometry&);
};
// Reads exactly the first 64KiB through a retained RO duplicate. Capacity is
// independently observed by the physical owner; regular files are fixtures.
// Uses pread, rechecks identity/status/capacity, and never opens a pathname.
// The remainder of a larger partition is outside libavb's 64KiB input limit.
VerifiedVbmetaFd verify_vbmeta_cohort_fd(int fd, uint64_t capacity,
                                        const VbmetaTrustPins&, const ImmutableKernelContext&,
                                        const ObservedBootGeometry&);
}
