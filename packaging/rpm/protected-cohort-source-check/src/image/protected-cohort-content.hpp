// SPDX-License-Identifier: MIT
#pragma once
#include "protected-cohort-vbmeta.hpp"
#include <array>
#include <cstdint>
#include <memory>

namespace uke::protected_boot {
enum class BootSlot { A, B };
struct BootContentIdentity {
    bool block_device;
    uint64_t device, inode, rdev, capacity_bytes;
};
struct OwnedBootDescriptors;
class VerifiedBootContents {
public:
    ~VerifiedBootContents();
    VerifiedBootContents(VerifiedBootContents&&) noexcept;
    VerifiedBootContents& operator=(VerifiedBootContents&&) noexcept;
    VerifiedBootContents(const VerifiedBootContents&) = delete;
    VerifiedBootContents& operator=(const VerifiedBootContents&) = delete;
    const VerifiedVbmetaCohort& cohort() const noexcept { return cohort_; }
    const std::array<BootContentIdentity, 3>& identities() const noexcept { return identities_; }
    uint64_t verified_bytes() const noexcept { return verified_bytes_; }
    BootSlot requested_slot() const noexcept { return slot_; }
private:
    VerifiedBootContents(VerifiedVbmetaCohort, std::unique_ptr<OwnedBootDescriptors>,
                         std::array<BootContentIdentity, 3>, uint64_t, BootSlot);
    VerifiedVbmetaCohort cohort_;
    std::unique_ptr<OwnedBootDescriptors> descriptors_;
    std::array<BootContentIdentity, 3> identities_;
    uint64_t verified_bytes_;
    BootSlot slot_;
    friend VerifiedBootContents verify_boot_contents_fds(const VerifiedVbmetaCohort&,
                                                         const std::array<int, 3>&, BootSlot);
};

// Read-only, buffered descriptors in boot/vendor_boot/dtbo order. Duplicates
// them before I/O and retains those handles in the result. Checks exact AVB
// prefixes plus the kernel slice in a v4 kernel-only boot image, using one
// 64KiB buffer. Regular files are inspection fixtures, not physical evidence.
// The caller still must prove physical topology, selected slot, source write
// exclusion, OEM/rollback state and role/key admission. No pathname is opened.
VerifiedBootContents verify_boot_contents_fds(const VerifiedVbmetaCohort&,
                                              const std::array<int, 3>& descriptors, BootSlot);
}
