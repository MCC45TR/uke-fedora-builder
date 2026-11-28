// SPDX-License-Identifier: MIT
#pragma once
#include "protected-cohort-content.hpp"
#include <array>
#include <memory>
#include <span>
#include <string>
#include <vector>

namespace uke::protected_boot {
enum class PhysicalRole : size_t {
    BootA, BootB, VendorA, VendorB, DtboA, DtboB, VbmetaA, VbmetaB, Super, Userdata
};
struct PhysicalPartitionFacts {
    std::string label, name, syspath, disk_name, disk_syspath, controller, driver;
    uint64_t device_number = 0, disk_number = 0, partition = 0, start_bytes = 0;
    uint64_t capacity_bytes = 0, disk_capacity_bytes = 0, disk_sequence = 0, logical_bytes = 0;
    bool operator==(const PhysicalPartitionFacts&) const = default;
};
namespace detail {
// Pure checks for untrusted observations. These never construct the physical
// owner or perform I/O. Tests may supply synthetic facts without gaining that
// owner's authority. All ten labels must occur exactly once.
void validate_uke_compatible(std::span<const unsigned char>);
std::array<PhysicalPartitionFacts, 10> validate_physical_facts(std::span<const PhysicalPartitionFacts>);
}
struct PhysicalCohortState;
class InspectedPhysicalBoot;
class PhysicalBootDevices {
public:
    ~PhysicalBootDevices();
    PhysicalBootDevices(PhysicalBootDevices&&) noexcept;
    PhysicalBootDevices& operator=(PhysicalBootDevices&&) noexcept;
    PhysicalBootDevices(const PhysicalBootDevices&) = delete;
    PhysicalBootDevices& operator=(const PhysicalBootDevices&) = delete;
    const std::array<PhysicalPartitionFacts, 10>& partitions() const;
    ObservedBootGeometry geometry() const;
    void revalidate() const;
private:
    explicit PhysicalBootDevices(std::unique_ptr<PhysicalCohortState>);
    std::unique_ptr<PhysicalCohortState> state_;
    friend PhysicalBootDevices open_physical_boot_devices();
    friend InspectedPhysicalBoot inspect_physical_boot(PhysicalBootDevices, BootSlot,
        const VbmetaTrustPins&, const ImmutableKernelContext&);
};
// Root-only, real sysfs and device-tree roots. Uses original sd-device for
// enumeration/parent discovery, then checks raw kernel attributes and opened
// RO block descriptors. No alternate root, env override or write operation.
PhysicalBootDevices open_physical_boot_devices();

class InspectedPhysicalBoot {
public:
    ~InspectedPhysicalBoot() = default;
    InspectedPhysicalBoot(InspectedPhysicalBoot&&) noexcept = default;
    InspectedPhysicalBoot& operator=(InspectedPhysicalBoot&&) noexcept = default;
    InspectedPhysicalBoot(const InspectedPhysicalBoot&) = delete;
    InspectedPhysicalBoot& operator=(const InspectedPhysicalBoot&) = delete;
    const PhysicalBootDevices& devices() const noexcept { return devices_; }
    const VerifiedBootContents& contents() const noexcept { return contents_; }
    const std::optional<KeyMintVersionBinding>& keymint_version_binding() const noexcept {
        return metadata_.cohort().keymint_version_binding();
    }
private:
    InspectedPhysicalBoot(PhysicalBootDevices, VerifiedVbmetaFd, VerifiedBootContents);
    PhysicalBootDevices devices_;
    VerifiedVbmetaFd metadata_;
    VerifiedBootContents contents_;
    friend InspectedPhysicalBoot inspect_physical_boot(PhysicalBootDevices, BootSlot,
        const VbmetaTrustPins&, const ImmutableKernelContext&);
};
// Retains all ten physical handles, the metadata handle and content handles.
// The requested slot is an inspection input, NOT evidence of the booted slot.
// OEM anchor, protected rollback, immutable running context, write exclusion,
// role/key release and authenticated resume remain the enclosing policy's job.
InspectedPhysicalBoot inspect_physical_boot(PhysicalBootDevices, BootSlot,
                                            const VbmetaTrustPins&, const ImmutableKernelContext&);
}
