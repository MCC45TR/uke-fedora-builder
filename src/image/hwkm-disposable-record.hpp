// SPDX-License-Identifier: MIT
#pragma once
#include "hwkm-wrapped-key.hpp"
namespace uke::protected_boot::hwkm::disposable {
// File mechanics only; this type grants no physical-device or boot authority.
// The caller supplies an already opened private directory owned by its EUID.
// This format is exclusively for a disposable diagnostic key, never FDE keys.
class Record {
public:
    explicit Record(int private_directory_fd);
    ~Record();
    Record(const Record&) = delete;
    Record& operator=(const Record&) = delete;
    bool exists() const;
    void create(const WrappedKey& long_term);
    WrappedKey read() const;
    bool remove();
private:
    int directory_ = -1, lock_ = -1;
};
}
