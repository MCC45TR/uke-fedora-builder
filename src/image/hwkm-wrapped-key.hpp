// SPDX-License-Identifier: MIT
#pragma once
#include <cstddef>
#include <memory>
#include <span>

namespace uke::protected_boot::hwkm {
// Mechanism only: these objects do not establish boot, device or role authority.
// The enclosing policy must admit the boot and retain its storage ownership.
// This implementation deliberately supports the fitted HWKM v2 format only.
inline constexpr std::size_t wrapped_key_bytes = 100;
enum class Lifetime { LongTerm, PerBoot };
struct KeyMemory;
class WrappedKey {
public:
    ~WrappedKey();
    WrappedKey(WrappedKey&&) noexcept;
    WrappedKey& operator=(WrappedKey&&) noexcept;
    WrappedKey(const WrappedKey&) = delete;
    WrappedKey& operator=(const WrappedKey&) = delete;
    Lifetime lifetime() const;
    std::span<const unsigned char> bytes() const;
private:
    WrappedKey(std::unique_ptr<KeyMemory>, Lifetime);
    std::unique_ptr<KeyMemory> memory_;
    Lifetime lifetime_;
    friend WrappedKey generate_v2(int);
    friend WrappedKey load_long_term_v2(std::span<const unsigned char>);
    friend WrappedKey prepare_v2(int, WrappedKey&&);
};
// Borrow an already admitted O_RDONLY 4-KiB block FD; pin a CLOEXEC duplicate
// during the operation. No paths, mappings, sector writes, raw-key imports,
// retries, software fallback, logging or persistence are provided here.
WrappedKey generate_v2(int block_fd);
// Copies a long-term wrapped blob into locked memory. This is parsing, not
// firmware authentication, a password check or authorization to use the blob.
WrappedKey load_long_term_v2(std::span<const unsigned char>);
// Consumes and clears the long-term input on success AND failure. Persist it
// durably through the enclosing transaction before calling this operation.
WrappedKey prepare_v2(int block_fd, WrappedKey&& long_term);
}
