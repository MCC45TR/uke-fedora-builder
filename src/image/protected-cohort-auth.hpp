// SPDX-License-Identifier: MIT
#pragma once
#include <string>
#include <span>
#include <vector>

namespace uke::protected_boot {
// The caller must obtain this pin from its authenticated immutable policy,
// never from the same storage that supplied the candidate key or payload.
struct VerifiedCohortBytes {
    std::vector<unsigned char> bytes;
    std::string payload_sha256;
    std::string signer_spki_sha256;
};

// The descriptor-owning physical selector can pass its bounded byte snapshots
// directly, without reopening an untrusted pathname after verification.
VerifiedCohortBytes verify_cohort_signature_bytes(std::span<const unsigned char> public_key,
                                                const std::string& trusted_spki_sha256,
                                                std::span<const unsigned char> payload,
                                                std::span<const unsigned char> signature);

// Verifies bounded, detached RSA-4096/PSS/SHA-256 bytes in the cohort domain.
// Does not parse a manifest, admit a role, unlock a key or authorize resume.
VerifiedCohortBytes verify_cohort_signature(const std::string& public_key_path,
                                          const std::string& trusted_spki_sha256,
                                          const std::string& payload_path,
                                          const std::string& signature_path);
}
