// SPDX-License-Identifier: MIT
#pragma once
#include "protected-cohort-auth.hpp"
#include <array>
#include <cstdint>
#include <string>

namespace uke::protected_boot {
// Supplied by authenticated immutable early policy, not candidate storage or
// an untrusted kernel command line. ID is generated BEFORE building the Image;
// embedding its own final digest would create a self-reference.
struct ImmutableKernelContext {
    std::string cohort_id;
    std::string kernel_release;
    std::string kernel_source_commit;
};
// The physical-selector caller must own/pin the observed devices. Numbers
// passed to the inspection CLI are fixture inputs, not that physical proof.
struct ObservedBootGeometry {
    uint64_t super_bytes;
    uint64_t userdata_bytes;
    uint64_t logical_block_bytes;
    std::array<uint64_t, 2> boot_bytes;
    std::array<uint64_t, 2> vendor_boot_bytes;
    std::array<uint64_t, 2> dtbo_bytes;
};
struct CohortPayload {
    uint64_t bytes;
    std::string sha256;
};
struct RescueVerityGeometry {
    uint64_t super_bytes, userdata_bytes;
    uint64_t rescue_start_bytes, rescue_bytes, swap_start_bytes, swap_bytes;
    uint64_t data_blocks, hash_start_blocks, hash_blocks;
    std::string root_sha256, salt, container_sha256;
};
struct ValidatedCohortManifest {
    ImmutableKernelContext kernel;
    CohortPayload kernel_image, boot, vendor_boot, dtbo, super_seed, userdata_seed;
    RescueVerityGeometry rescue;
};

// Consumes ONLY the owned signed-byte snapshot returned by the signature
// primitive. Validates schema, immutable kernel context, exact observed
// geometry and derived 80/20/verity sizes. No image contents, AVB/OEM trust,
// physical identity, boot role, key or hibernation snapshot is verified here.
ValidatedCohortManifest validate_cohort_manifest(const VerifiedCohortBytes& verified,
                                                const ImmutableKernelContext& expected,
                                                const ObservedBootGeometry& observed);
}
