// SPDX-License-Identifier: MIT
#pragma once
#include <string>
#include <span>
#include <vector>
#include <utility>

namespace uke::protected_boot {
// Untrusted regular-file snapshot for inspection frontends only. Same strict
// openat2/identity checks as signature inputs; this does not authenticate it.
std::vector<unsigned char> read_cohort_metadata_file(const std::string& path, size_t maximum_bytes);
// The caller must obtain this pin from its authenticated immutable policy,
// never from the same storage that supplied the candidate key or payload.
class VerifiedCohortBytes {
public:
    VerifiedCohortBytes(const VerifiedCohortBytes&) = default;
    VerifiedCohortBytes(VerifiedCohortBytes&&) noexcept = default;
    VerifiedCohortBytes& operator=(const VerifiedCohortBytes&) = default;
    VerifiedCohortBytes& operator=(VerifiedCohortBytes&&) noexcept = default;
    const std::vector<unsigned char>& bytes() const noexcept { return bytes_; }
    const std::string& payload_sha256() const noexcept { return payload_sha256_; }
    const std::string& signer_spki_sha256() const noexcept { return signer_spki_sha256_; }
private:
    VerifiedCohortBytes(std::vector<unsigned char> bytes, std::string payload, std::string signer)
        : bytes_(std::move(bytes)), payload_sha256_(std::move(payload)), signer_spki_sha256_(std::move(signer)) {}
    std::vector<unsigned char> bytes_;
    std::string payload_sha256_, signer_spki_sha256_;
    friend VerifiedCohortBytes verify_cohort_signature_bytes(std::span<const unsigned char>,
                                                            const std::string&,
                                                            std::span<const unsigned char>,
                                                            std::span<const unsigned char>);
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
