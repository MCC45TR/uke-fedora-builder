// SPDX-License-Identifier: MIT
#pragma once

#include "hwkm-wrapped-key.hpp"
#include <string>
#include <string_view>
#include <sys/types.h>

namespace uke::protected_boot::hwkm {
struct InlinecryptReadResult {
    std::string backing_sha256;
    std::string mapped_sha256;
};

// Test one block through ICE. The caller must retain the admitted physical UFS
// fd. The disposable per-boot key only enters a temporary logon key and the
// read-only dm-inlinecrypt target. Neither block fd is opened for write access.
InlinecryptReadResult exercise_inlinecrypt_read(int block_fd, WrappedKey&& key, const char*& phase);

// The disposable fixture is the verified free EXT4 block in Fedora Live
// Rescue (system_b). The caller owns layout validation and a durable backup.
inline constexpr off_t rescue_block_offset = (256 + 500000) * 4096LL;
InlinecryptReadResult exercise_inlinecrypt_rescue_block(int block_fd, WrappedKey&& key,
    std::string_view expected_backing, bool write, const char*& phase);
}
