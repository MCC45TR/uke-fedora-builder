// SPDX-License-Identifier: MIT
// Native pure-fact tests. Synthetic facts never construct the physical owner.
#include "protected-physical-cohort.hpp"
#include <sys/sysmacros.h>
#include <algorithm>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <type_traits>

#ifndef __aarch64__
#error This qualification must compile and run on native AArch64
#endif
using namespace uke::protected_boot;
namespace {
using Facts = std::vector<PhysicalPartitionFacts>;
Facts baseline() {
    constexpr std::array<const char*, 10> labels{"boot_a", "boot_b", "vendor_boot_a", "vendor_boot_b",
        "dtbo_a", "dtbo_b", "vbmeta_a", "vbmeta_b", "super", "userdata"};
    constexpr std::array<unsigned, 10> parts{11, 39, 21, 49, 15, 43, 14, 42, 31, 32};
    constexpr std::array<uint64_t, 10> capacities{100663296, 100663296, 100663296, 100663296,
        25165824, 25165824, 131072, 131072, 11274289152, 497535680512};
    Facts out;
    uint64_t boot_start = 1048576, data_start = 1048576;
    for (size_t i = 0; i < 10; ++i) {
        PhysicalPartitionFacts p;
        p.label = labels[i]; p.partition = parts[i];
        p.disk_name = i < 8 ? "sde" : "sda";
        p.name = p.disk_name + std::to_string(p.partition);
        p.controller = "/sys/devices/platform/soc/1d84000.ufshc";
        p.driver = "ufshcd-qcom";
        p.disk_syspath = p.controller + "/host0/target0:0:0/0:0:0:" + (i < 8 ? "4" : "0") + "/block/" + p.disk_name;
        p.syspath = p.disk_syspath + "/" + p.name;
        p.device_number = makedev(259, 100 + i);
        p.disk_number = makedev(8, i < 8 ? 64 : 0);
        p.disk_sequence = i < 8 ? 2 : 1;
        p.start_bytes = i < 8 ? boot_start : data_start;
        p.capacity_bytes = capacities[i];
        p.disk_capacity_bytes = i < 8 ? 2147483648 : 549755813888;
        p.logical_bytes = 4096;
        if (i < 8) boot_start += capacities[i]; else data_start += capacities[i];
        out.push_back(std::move(p));
    }
    return out;
}
void compatible(const std::string& value) {
    detail::validate_uke_compatible({reinterpret_cast<const unsigned char*>(value.data()), value.size()});
}
size_t refused = 0;
void reject(const std::function<void()>& operation) {
    try { operation(); }
    catch (const std::runtime_error&) { ++refused; return; }
    throw std::runtime_error("Invalid fixture was admitted");
}
}
int main() {
    try {
        static_assert(!std::is_default_constructible_v<PhysicalBootDevices>);
        static_assert(!std::is_copy_constructible_v<PhysicalBootDevices>);
        static_assert(!std::is_default_constructible_v<InspectedPhysicalBoot>);
        static_assert(!std::is_copy_constructible_v<InspectedPhysicalBoot>);
        const auto original = baseline();
        const auto expected = detail::validate_physical_facts(original);
        auto other = original;
        std::reverse(other.begin(), other.end());
        if (detail::validate_physical_facts(other) != expected) throw std::runtime_error("Ordering");
        other = original;
        for (auto& p : other) {
            p.disk_name = p.disk_sequence == 2 ? "sdf" : "sdc";
            p.disk_syspath = p.controller + "/host9/target9:0:0/9:0:0:0/block/" + p.disk_name;
            p.name = p.disk_name + std::to_string(p.partition);
            p.syspath = p.disk_syspath + "/" + p.name;
        }
        (void)detail::validate_physical_facts(other);
        other = original;
        other[1].capacity_bytes += 4096;
        for (size_t i = 2; i < 8; ++i) other[i].start_bytes += 4096;
        (void)detail::validate_physical_facts(other);
        const std::string board("xiaomi,uke\0qcom,sm7675\0qcom,cliffs\0", 35);
        compatible(board);
        std::vector<std::function<void(Facts&)>> faults;
        faults.emplace_back([](auto& f) { f[0].label = "other"; });
        faults.emplace_back([](auto& f) { f[0].label = "boot_b"; });
        faults.emplace_back([](auto& f) { f.pop_back(); });
        faults.emplace_back([](auto& f) { f.push_back(f[0]); });
        faults.emplace_back([](auto& f) { f[0].controller += "-other"; });
        faults.emplace_back([](auto& f) { f[0].driver = "other"; });
        faults.emplace_back([](auto& f) { f[0].disk_name = "nvme0n1"; });
        faults.emplace_back([](auto& f) { f[0].name = "sdf11"; });
        faults.emplace_back([](auto& f) { f[0].partition = 0; });
        faults.emplace_back([](auto& f) { f[0].partition = 65536; });
        faults.emplace_back([](auto& f) { f[0].syspath += "-other"; });
        faults.emplace_back([](auto& f) { f[0].disk_syspath = "/sys/devices/virtual/block/sde"; });
        faults.emplace_back([](auto& f) { f[0].disk_syspath += "/other"; });
        faults.emplace_back([](auto& f) { f[0].disk_syspath = f[0].controller + "/../block/sde"; });
        faults.emplace_back([](auto& f) { f[0].device_number = f[1].device_number; });
        faults.emplace_back([](auto& f) { f[0].device_number = f[8].disk_number; });
        faults.emplace_back([](auto& f) { f[0].device_number = 0; });
        faults.emplace_back([](auto& f) { f[0].disk_number = 0; });
        faults.emplace_back([](auto& f) { f[0].disk_sequence = 0; });
        faults.emplace_back([](auto& f) { f[0].logical_bytes = 512; });
        faults.emplace_back([](auto& f) { f[0].capacity_bytes = 0; });
        faults.emplace_back([](auto& f) { ++f[0].capacity_bytes; });
        faults.emplace_back([](auto& f) { f[0].capacity_bytes = 2199023259648; });
        faults.emplace_back([](auto& f) { f[0].capacity_bytes = 536875008; });
        faults.emplace_back([](auto& f) { f[6].capacity_bytes = 61440; });
        faults.emplace_back([](auto& f) { f[6].capacity_bytes = 1052672; });
        faults.emplace_back([](auto& f) { ++f[0].disk_capacity_bytes; });
        faults.emplace_back([](auto& f) { f[0].disk_capacity_bytes = 0; });
        faults.emplace_back([](auto& f) { f[0].disk_capacity_bytes = 2199023259648; });
        faults.emplace_back([](auto& f) { f[0].start_bytes = 0; });
        faults.emplace_back([](auto& f) { ++f[0].start_bytes; });
        faults.emplace_back([](auto& f) { f[0].start_bytes = UINT64_MAX; });
        faults.emplace_back([](auto& f) { f[0].start_bytes = f[0].disk_capacity_bytes - 4096; });
        faults.emplace_back([](auto& f) { f[1].start_bytes = f[0].start_bytes; });
        faults.emplace_back([](auto& f) { f[0].disk_capacity_bytes += 4096; });
        faults.emplace_back([](auto& f) { f[0].disk_sequence = 9; });
        faults.emplace_back([](auto& f) { f[0].disk_number = f[8].disk_number; });
        faults.emplace_back([](auto& f) { f[0].disk_number = makedev(8, 80); });
        faults.emplace_back([](auto& f) { f[0].disk_syspath += "\n"; });
        faults.emplace_back([](auto& f) { f[0].name = "sde011"; });
        for (const auto& fault : faults) {
            auto input = original;
            fault(input);
            reject([&input] { (void)detail::validate_physical_facts(input); });
        }
        const auto topology_refused = refused;
        std::vector<std::string> bad_boards{"", std::string("xiaomi,other\0qcom,sm7675\0", 25),
            std::string("xiaomi,uke\0qcom,other\0", 22), board.substr(0, board.size() - 1),
            board + std::string(1, '\0'), board + std::string("xiaomi,uke\0", 11),
            board + std::string(1030, 'x'), board + std::string(129, 'x') + std::string(1, '\0')};
        for (const auto& bad : bad_boards) reject([&bad] { compatible(bad); });
        if (topology_refused != 40 || refused != 48) throw std::runtime_error("Case count");
        reject([] { (void)open_physical_boot_devices(); });
        std::cout << "{\"schema_version\":1,\"native_architecture\":\"aarch64\","
            "\"pure_synthetic_facts_only\":true,\"positive_layouts\":4,\"topology_cases_refused\":40,"
            "\"board_cases_refused\":8,\"non_target_owner_refused\":true,"
            "\"private_owner_not_constructible_from_facts\":true,\"distinct_ufs_logical_units_supported\":true,"
            "\"device_names_and_slot_capacities_not_fixed\":true,\"physical_ufs_qualified\":false,"
            "\"slot_or_running_kernel_bound\":false,\"role_admitted\":false}\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
