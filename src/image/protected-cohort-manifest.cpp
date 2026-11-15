// SPDX-License-Identifier: MIT
// Typed manifest boundary for the future native protected-boot policy.
#include "protected-cohort-manifest.hpp"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <charconv>
#include <cstddef>
#include <initializer_list>
#include <set>
#include <stdexcept>
#include <string_view>
#include <tuple>
#include <type_traits>
#include <utility>
#include <vector>
#ifdef UKE_COHORT_MANIFEST_CLI
#include <iostream>
#endif

namespace uke::protected_boot {
namespace {
using Json = nlohmann::json;
static_assert(!std::is_default_constructible_v<VerifiedCohortBytes>);
static_assert(!std::is_aggregate_v<VerifiedCohortBytes>);
constexpr uint64_t alignment = 1048576, block = 4096, max_storage = 2199023255552;
constexpr std::string_view domain = "UKE-PROTECTED-COHORT-v1\n";
[[noreturn]] void refuse() { throw std::runtime_error("Cohort manifest rejected"); }
void keys(const Json& value, std::initializer_list<const char*> names) {
    if (!value.is_object() || value.size() != names.size()) refuse();
    for (const auto* name : names) if (!value.contains(name)) refuse();
}
uint64_t number(const Json& value) {
    if (!value.is_number_unsigned()) refuse();
    return value.get<uint64_t>();
}
std::string text(const Json& value, size_t limit) {
    if (!value.is_string()) refuse();
    auto result = value.get<std::string>();
    if (result.empty() || result.size() > limit) refuse();
    return result;
}
bool hex(const std::string& value, size_t size) {
    return value.size() == size && value.find_first_not_of("0123456789abcdef") == std::string::npos &&
           value.find_first_not_of('0') != std::string::npos;
}
std::string digest(const Json& value) {
    const auto result = text(value, 64);
    if (!hex(result, 64)) refuse();
    return result;
}
bool decimal(std::string_view value, uint64_t maximum, bool nonzero) {
    if (value.empty() || (value.size() > 1 && value.front() == '0') ||
        value.find_first_not_of("0123456789") != std::string_view::npos) return false;
    uint64_t number = 0;
    const auto result = std::from_chars(value.data(), value.data() + value.size(), number);
    return result.ec == std::errc{} && result.ptr == value.data() + value.size() &&
           number <= maximum && (!nonzero || number != 0);
}
bool release(const std::string& input) {
    constexpr std::string_view suffix = "-unstable";
    if (input.size() > 64 || !input.ends_with(suffix)) return false;
    std::string_view value(input.data(), input.size() - suffix.size());
    const auto hyphen = value.find('-');
    if (hyphen == std::string_view::npos || !decimal(value.substr(hyphen + 1), 999999, true)) return false;
    value = value.substr(0, hyphen);
    for (int part = 0; part < 3; ++part) {
        const auto dot = value.find('.');
        if (part < 2 && dot == std::string_view::npos) return false;
        if (part == 2 && dot != std::string_view::npos) return false;
        if (!decimal(value.substr(0, dot), 999, part == 0)) return false;
        if (part < 2) value.remove_prefix(dot + 1);
    }
    return true;
}
void storage(uint64_t bytes) {
    if (bytes < 4294967296 || bytes > max_storage || bytes % block) refuse();
}
uint64_t tree_blocks(uint64_t data) {
    uint64_t total = 0;
    while (data > 1) { data = (data + 127) / 128; total += data; }
    return total;
}
uint64_t largest_data(uint64_t capacity) {
    uint64_t low = 1, high = capacity / block, best = 0;
    while (low <= high) {
        const uint64_t middle = low + (high - low) / 2;
        if (middle + tree_blocks(middle) <= capacity / block) { best = middle; low = middle + 1; }
        else high = middle - 1;
    }
    if (best < 4096) refuse();
    return best;
}
CohortPayload payload(const Json& input, uint64_t maximum) {
    keys(input, {"bytes", "sha256"});
    CohortPayload result{number(input.at("bytes")), digest(input.at("sha256"))};
    if (!result.bytes || result.bytes > maximum) refuse();
    return result;
}
RescueVerityGeometry geometry(const Json& input) {
    keys(input, {"super_bytes", "userdata_bytes", "logical_block_bytes", "rescue_start_bytes",
                 "rescue_bytes", "swap_start_bytes", "swap_bytes", "verity"});
    RescueVerityGeometry out{};
    out.super_bytes = number(input.at("super_bytes"));
    out.userdata_bytes = number(input.at("userdata_bytes"));
    storage(out.super_bytes); storage(out.userdata_bytes);
    if (number(input.at("logical_block_bytes")) != block) refuse();
    const uint64_t usable = (out.super_bytes / alignment - 1) * alignment;
    const uint64_t swap = (usable / alignment * 80 / 100) * alignment;
    const uint64_t rescue = usable - swap;
    if (swap < alignment || rescue < 805306368) refuse();
    out.rescue_start_bytes = number(input.at("rescue_start_bytes"));
    out.rescue_bytes = number(input.at("rescue_bytes"));
    out.swap_start_bytes = number(input.at("swap_start_bytes"));
    out.swap_bytes = number(input.at("swap_bytes"));
    if (out.rescue_start_bytes != alignment || out.rescue_bytes != rescue ||
        out.swap_start_bytes != alignment + rescue || out.swap_bytes != swap) refuse();
    const auto& verity = input.at("verity");
    keys(verity, {"data_blocks", "hash_start_blocks", "hash_blocks", "root_sha256", "salt", "container_sha256"});
    out.data_blocks = number(verity.at("data_blocks"));
    out.hash_start_blocks = number(verity.at("hash_start_blocks"));
    out.hash_blocks = number(verity.at("hash_blocks"));
    const uint64_t data = largest_data(rescue);
    if (out.data_blocks != data || out.hash_start_blocks != data || out.hash_blocks != tree_blocks(data)) refuse();
    out.root_sha256 = digest(verity.at("root_sha256"));
    out.container_sha256 = digest(verity.at("container_sha256"));
    out.salt = text(verity.at("salt"), 64);
    // A public salt may legitimately consist entirely of zeroes.
    if (out.salt.size() != 64 || out.salt.find_first_not_of("0123456789abcdef") != std::string::npos) refuse();
    return out;
}
Json parse(const VerifiedCohortBytes& verified) {
    const auto& bytes = verified.bytes();
    if (bytes.size() <= domain.size() || bytes.size() > 65536 ||
        !std::equal(domain.begin(), domain.end(), bytes.begin()) ||
        !hex(verified.payload_sha256(), 64) || !hex(verified.signer_spki_sha256(), 64)) refuse();
    auto begin = bytes.begin() + static_cast<std::ptrdiff_t>(domain.size());
    // Some JSON lexers interpret a raw NUL as end-of-input even with an
    // iterator range. Never permit a second hidden interpretation of a suffix.
    if (std::find(begin, bytes.end(), static_cast<unsigned char>(0)) != bytes.end()) refuse();
    auto first = begin;
    while (first != bytes.end() && (*first == ' ' || *first == '\t' || *first == '\n' || *first == '\r')) ++first;
    // Reject a BOM, scalar root or alternate encoding before DOM construction.
    if (first == bytes.end() || *first != '{') refuse();
    std::vector<std::set<std::string>> object_keys;
    size_t events = 0;
    auto callback = [&](int depth, Json::parse_event_t event, Json& value) {
        if (depth > 8 || ++events > 1024) refuse();
        if (event == Json::parse_event_t::object_start) object_keys.emplace_back();
        if (event == Json::parse_event_t::key) {
            if (object_keys.empty()) refuse();
            const auto key = text(value, 64);
            if (!object_keys.back().insert(key).second) refuse();
        }
        if (event == Json::parse_event_t::value && value.is_string()) (void)text(value, 128);
        if (event == Json::parse_event_t::object_end) {
            if (object_keys.empty()) refuse();
            object_keys.pop_back();
        }
        return true;
    };
    auto result = Json::parse(begin, bytes.end(), callback, true, false);
    if (!object_keys.empty()) refuse();
    return result;
}
}

ValidatedCohortManifest validate_cohort_manifest(const VerifiedCohortBytes& verified,
                                                const ImmutableKernelContext& expected,
                                                const ObservedBootGeometry& observed) {
    if (!hex(expected.cohort_id, 32) || !hex(expected.kernel_source_commit, 40) ||
        !release(expected.kernel_release)) refuse();
    storage(observed.super_bytes); storage(observed.userdata_bytes);
    if (observed.logical_block_bytes != block) refuse();
    for (const auto* capacities : {&observed.boot_bytes, &observed.vendor_boot_bytes, &observed.dtbo_bytes})
        for (const auto bytes : *capacities)
            if (bytes < block || bytes > 536870912 || bytes % block) refuse();
    const auto root = parse(verified);
    keys(root, {"schema_version", "platform", "cohort_id", "kernel_release", "kernel_source_commit",
                "payloads", "geometries"});
    if (number(root.at("schema_version")) != 1 || text(root.at("platform"), 32) != "xiaomi,uke" ||
        text(root.at("cohort_id"), 32) != expected.cohort_id ||
        text(root.at("kernel_release"), 64) != expected.kernel_release ||
        text(root.at("kernel_source_commit"), 40) != expected.kernel_source_commit) refuse();
    const auto& images = root.at("payloads");
    keys(images, {"kernel_image", "boot", "vendor_boot", "dtbo", "super_seed", "userdata_seed"});
    const auto boot_max = std::min(observed.boot_bytes[0], observed.boot_bytes[1]);
    const auto vendor_max = std::min(observed.vendor_boot_bytes[0], observed.vendor_boot_bytes[1]);
    const auto dtbo_max = std::min(observed.dtbo_bytes[0], observed.dtbo_bytes[1]);
    ValidatedCohortManifest result{};
    result.kernel = expected;
    result.boot = payload(images.at("boot"), boot_max);
    result.vendor_boot = payload(images.at("vendor_boot"), vendor_max);
    result.dtbo = payload(images.at("dtbo"), dtbo_max);
    result.kernel_image = payload(images.at("kernel_image"), result.boot.bytes);
    result.super_seed = payload(images.at("super_seed"), observed.super_bytes);
    result.userdata_seed = payload(images.at("userdata_seed"), observed.userdata_bytes);
    if (result.super_seed.bytes % block || result.userdata_seed.bytes % block) refuse();
    const auto& candidates = root.at("geometries");
    if (!candidates.is_array() || candidates.empty() || candidates.size() > 8) refuse();
    std::tuple<uint64_t, uint64_t> previous{0, 0};
    bool found = false;
    for (const auto& candidate : candidates) {
        auto current = geometry(candidate);
        if (result.super_seed.bytes > current.super_bytes || result.userdata_seed.bytes > current.userdata_bytes) refuse();
        const auto order = std::tuple{current.super_bytes, current.userdata_bytes};
        if (order <= previous) refuse();
        previous = order;
        if (current.super_bytes == observed.super_bytes && current.userdata_bytes == observed.userdata_bytes) {
            if (found) refuse();
            found = true;
            result.rescue = std::move(current);
        }
    }
    if (!found) refuse();
    return result;
}
}

#ifdef UKE_COHORT_MANIFEST_CLI
// Inspection fixture only: its CLI context/geometry are not trusted authority.
int main(int argc, char** argv) {
    if (argc != 17) return 2;
    try {
        auto number = [](const char* input) {
            std::string_view value(input);
            if (value.empty() || value.size() > 13 || (value.size() > 1 && value.front() == '0') ||
                value.find_first_not_of("0123456789") != std::string_view::npos) throw std::runtime_error("number");
            uint64_t result = 0;
            const auto conversion = std::from_chars(value.data(), value.data() + value.size(), result);
            if (conversion.ec != std::errc{} || conversion.ptr != value.data() + value.size()) throw std::runtime_error("number");
            return result;
        };
        const uke::protected_boot::ImmutableKernelContext expected{argv[5], argv[6], argv[7]};
        const uke::protected_boot::ObservedBootGeometry observed{
            number(argv[8]), number(argv[9]), number(argv[10]),
            {number(argv[11]), number(argv[12])}, {number(argv[13]), number(argv[14])},
            {number(argv[15]), number(argv[16])}};
        const auto verified = uke::protected_boot::verify_cohort_signature(argv[1], argv[2], argv[3], argv[4]);
        const auto result = uke::protected_boot::validate_cohort_manifest(verified, expected, observed);
        const nlohmann::json report{
            {"signature_verified", true}, {"manifest_schema_valid", true}, {"kernel_context_matched", true},
            {"exact_geometry_selected", true}, {"cohort_id", result.kernel.cohort_id},
            {"super_bytes", result.rescue.super_bytes}, {"userdata_bytes", result.rescue.userdata_bytes},
            {"rescue_bytes", result.rescue.rescue_bytes}, {"data_blocks", result.rescue.data_blocks},
            {"hash_blocks", result.rescue.hash_blocks}, {"root_sha256", result.rescue.root_sha256},
            {"boot_payloads_verified", false}, {"physical_identity_verified", false},
            {"avb_signature_verified", false}, {"hardware_trust_qualified", false},
            {"role_admitted", false}, {"snapshot_authenticated", false}, {"storage_or_key_release_executed", false}};
        std::cout << report.dump() << '\n';
        return 0;
    } catch (const std::exception&) {
        std::cerr << "UKE_COHORT_MANIFEST_REJECTED\n";
        return 1;
    }
}
#endif
