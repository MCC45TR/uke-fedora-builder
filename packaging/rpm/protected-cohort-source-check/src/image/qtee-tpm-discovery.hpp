// SPDX-License-Identifier: MIT
#pragma once
#include <cstdint>
#include <stdexcept>

namespace uke::protected_boot::qtee_tpm {
enum class Kind { None, Firmware, Discrete };
struct Information {
    Kind kind = Kind::None;
    std::uint16_t major = 0, minor = 0;
    std::uint32_t information_queries = 0;
};
class RemoteRefusal : public std::runtime_error {
public:
    explicit RemoteRefusal(std::uint32_t result)
        : std::runtime_error("QTEE request refused"), result(result) {}
    std::uint32_t result;
};
// Owns the admitted provider FD even on failure. The original MINK adapter
// opens /dev/tee0 separately; both device identities must match. Original
// Fedora libqcomtee supplies the ordinary userspace credential callback.
// Only UID81 and the fixed TA version/type queries are exposed. No TCG
// command, privileged NULL credential, TA loader, Startup, Clear or NV write.
// Caller owns physical-board admission and the process deadline.
Information inspect_owned_provider(int provider_fd, const char*& phase);

struct KeymasterVersion {
    std::uint32_t hal_major, hal_minor, app_major, app_minor;
};

// The fitted OTA names keymaster64. Request its fixed version through the
// named object path using ordinary credentials and no firmware input.
KeymasterVersion inspect_keymaster_owned_provider(int provider_fd, const char*& phase);

struct KeymasterStorageResult {
    std::uint32_t long_term_bytes, ephemeral_bytes;
};

// Exercise a new disposable storage key and an anonymous private disk record.
KeymasterStorageResult exercise_keymaster_storage(int provider_fd, const char*& phase);
}
