// SPDX-License-Identifier: MIT
#pragma once
#include "protected-cohort-manifest.hpp"
#include <array>
#include <cstdint>
#include <span>
#include <string>
#include <utility>

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
private:
    VerifiedVbmetaCohort(ValidatedCohortManifest manifest, std::array<AvbBootHash, 3> hashes, ObservedBootGeometry observed,
                         std::string digest, uint64_t rollback)
        : manifest_(std::move(manifest)), boot_hashes_(std::move(hashes)), observed_(observed),
          vbmeta_sha256_(std::move(digest)), rollback_index_(rollback) {}
    ValidatedCohortManifest manifest_;
    std::array<AvbBootHash, 3> boot_hashes_;
    ObservedBootGeometry observed_;
    std::string vbmeta_sha256_;
    uint64_t rollback_index_;
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
}
