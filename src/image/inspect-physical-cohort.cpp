// SPDX-License-Identifier: MIT
// Diagnostic frontend only. Supplied pins/context are never boot authority.
#include "protected-physical-cohort.hpp"
#include <nlohmann/json.hpp>
#include <sys/resource.h>
#include <sys/sysmacros.h>
#include <unistd.h>
#include <dirent.h>
#include <array>
#include <charconv>
#include <climits>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string_view>

namespace {
using namespace uke::protected_boot;
[[noreturn]] void refuse() { throw std::runtime_error("Inspection rejected"); }
uint64_t number(std::string_view value) {
    if (value.empty() || value.size() > 13 || (value.size() > 1 && value.front() == '0') ||
        value.find_first_not_of("0123456789") != value.npos) refuse();
    uint64_t result = 0;
    const auto parsed = std::from_chars(value.data(), value.data() + value.size(), result);
    if (parsed.ec != std::errc{} || parsed.ptr != value.data() + value.size()) refuse();
    return result;
}
int descriptor(const char* value) {
    const auto result = number(value);
    if (result < 3 || result > INT_MAX) refuse();
    return static_cast<int>(result);
}
BootSlot slot(const char* value) {
    if (std::string_view(value) == "a") return BootSlot::A;
    if (std::string_view(value) == "b") return BootSlot::B;
    refuse();
}
struct CloseDirectory { void operator()(DIR* value) const noexcept { if (value) closedir(value); } };
size_t descriptors() {
    std::unique_ptr<DIR, CloseDirectory> directory(opendir("/proc/self/fd"));
    if (!directory) refuse();
    size_t out = 0;
    while (const auto* entry = readdir(directory.get())) if (entry->d_name[0] != '.') ++out;
    return out;
}
nlohmann::json unavailable_authority() {
    return {{"selected_slot_bound", false}, {"booted_kernel_verified", false}, {"hardware_trust_qualified", false},
        {"rollback_state_verified", false}, {"source_write_exclusion_verified", false}, {"role_admitted", false},
        {"operating_system_booted", false}, {"storage_or_key_release_executed", false}};
}
nlohmann::json describe(const PhysicalBootDevices& devices) {
    auto result = unavailable_authority();
    result["physical_ufs_topology_verified"] = true;
    result["observed_roles"] = nlohmann::json::array();
    for (const auto& p : devices.partitions()) {
        const auto dev = static_cast<dev_t>(p.device_number);
        result["observed_roles"].push_back({{"label", p.label}, {"name", p.name},
            {"major", major(dev)}, {"minor", minor(dev)}, {"capacity_bytes", p.capacity_bytes},
            {"logical_bytes", p.logical_bytes}, {"start_bytes", p.start_bytes}, {"partition", p.partition},
            {"controller", "1d84000.ufshc"}, {"driver", p.driver}, {"disk_name", p.disk_name}});
    }
    return result;
}
nlohmann::json inspect(int argc, char** argv) {
    const std::string_view mode(argv[1]);
    if (mode == "--identity-only" && argc == 2) {
        const auto devices = open_physical_boot_devices();
        auto result = describe(devices);
        devices.revalidate();
        result["metadata_read"] = false;
        result["metadata_verified"] = false;
        result["boot_contents_verified"] = false;
        return result;
    }
    if (mode == "--inspect-slot" && argc == 8) {
        const auto side = slot(argv[2]);
        const auto result = inspect_physical_boot(open_physical_boot_devices(), side,
            VbmetaTrustPins{argv[3], argv[4]}, ImmutableKernelContext{argv[5], argv[6], argv[7]});
        auto report = describe(result.devices());
        report["metadata_read"] = true;
        report["metadata_verified"] = true;
        report["boot_contents_verified"] = true;
        report["requested_slot"] = argv[2];
        report["verified_boot_bytes"] = result.contents().verified_bytes();
        return report;
    }
    if (mode == "--fixture-vbmeta-fd" && argc == 22) {
        const int metadata_fd = descriptor(argv[2]);
        const uint64_t capacity = number(argv[3]);
        const VbmetaTrustPins trust{argv[4], argv[5]};
        const ImmutableKernelContext expected{argv[6], argv[7], argv[8]};
        const ObservedBootGeometry observed{number(argv[9]), number(argv[10]), number(argv[11]),
            {number(argv[12]), number(argv[13])}, {number(argv[14]), number(argv[15])},
            {number(argv[16]), number(argv[17])}};
        const auto side = slot(argv[18]);
        const std::array<int, 3> fds{descriptor(argv[19]), descriptor(argv[20]), descriptor(argv[21])};
        const std::array<int, 4> originals{metadata_fd, fds[0], fds[1], fds[2]};
        std::array<off_t, 4> offsets{};
        for (size_t i = 0; i < originals.size(); ++i) offsets[i] = lseek(originals[i], 0, SEEK_CUR);
        const auto metadata = verify_vbmeta_cohort_fd(metadata_fd, capacity, trust, expected, observed);
        const auto contents = verify_boot_contents_fds(metadata.cohort(), fds, side);
        for (size_t i = 0; i < originals.size(); ++i)
            if (offsets[i] < 0 || lseek(originals[i], 0, SEEK_CUR) != offsets[i]) refuse();
        auto result = unavailable_authority();
        size_t block_inputs = 0;
        for (const auto& id : contents.identities()) if (id.block_device) ++block_inputs;
        result["physical_ufs_topology_verified"] = false;
        result["fixture_inputs"] = true;
        result["metadata_verified"] = true;
        result["metadata_prefix_bytes"] = 65536;
        result["metadata_block_input"] = metadata.block_input();
        result["boot_block_input_count"] = block_inputs;
        result["boot_contents_verified"] = true;
        result["verified_boot_bytes"] = contents.verified_bytes();
        result["caller_positions_unchanged"] = true;
        return result;
    }
    refuse();
}
}
int main(int argc, char** argv) {
    if (argc < 2) return 2;
    size_t initial = 0;
    bool counting = false;
    try {
        initial = descriptors();
        counting = true;
        auto report = inspect(argc, argv);
        if (descriptors() != initial) refuse();
        counting = false;
        struct rusage usage{};
        if (getrusage(RUSAGE_SELF, &usage)) refuse();
        report["owned_handles_released"] = true;
        report["peak_rss_kib"] = usage.ru_maxrss;
        std::cout << report.dump() << '\n';
        return 0;
    } catch (const std::exception&) {
        if (counting) {
            try { if (descriptors() != initial) { std::cerr << "UKE_PHYSICAL_DESCRIPTOR_LEAK\n"; return 3; } }
            catch (...) { return 3; }
        }
        std::cerr << "UKE_PHYSICAL_COHORT_REJECTED\n";
        return 1;
    }
}
