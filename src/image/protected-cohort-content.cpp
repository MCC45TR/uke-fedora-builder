// SPDX-License-Identifier: MIT
#include "protected-cohort-content.hpp"
#include <openssl/evp.h>
#include <linux/fs.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <type_traits>
#ifdef UKE_COHORT_CONTENT_CLI
#include <charconv>
#include <climits>
#include <dirent.h>
#include <iostream>
#include <nlohmann/json.hpp>
#include <sys/resource.h>
#endif

namespace uke::protected_boot {
struct OwnedBootDescriptors {
    std::array<int, 3> values{-1, -1, -1};
    ~OwnedBootDescriptors() { for (const auto fd : values) if (fd >= 0) close(fd); }
};
namespace {
static_assert(!std::is_default_constructible_v<VerifiedBootContents>);
static_assert(!std::is_copy_constructible_v<VerifiedBootContents>);
constexpr size_t chunk_bytes = 65536;
constexpr uint64_t page = 4096, maximum_image = 536870912;
[[noreturn]] void refuse() { throw std::runtime_error("Boot content rejected"); }
using Clock = std::chrono::steady_clock;
void deadline(const Clock::time_point& until) { if (Clock::now() >= until) refuse(); }
struct Snapshot {
    struct stat state{};
    int flags;
    uint64_t capacity;
    bool block;
};
Snapshot snapshot(int fd, uint64_t slot_capacity, uint64_t prefix) {
    Snapshot result{};
    result.flags = fcntl(fd, F_GETFL);
    if (fd < 3 || result.flags < 0 || (result.flags & O_ACCMODE) != O_RDONLY ||
        (result.flags & (O_PATH | O_DIRECT)) || fstat(fd, &result.state)) refuse();
    result.block = S_ISBLK(result.state.st_mode);
    if (!result.block && !S_ISREG(result.state.st_mode)) refuse();
    if (result.block) {
        unsigned long long capacity = 0;
        int sector = 0;
        if (ioctl(fd, BLKGETSIZE64, &capacity) || ioctl(fd, BLKSSZGET, &sector) ||
            capacity != slot_capacity || sector != 4096) refuse();
        result.capacity = capacity;
    } else {
        if (result.state.st_size < 0) refuse();
        result.capacity = static_cast<uint64_t>(result.state.st_size);
        if (result.capacity > slot_capacity) refuse();
    }
    if (!prefix || prefix > maximum_image || prefix > result.capacity) refuse();
    return result;
}
bool same(const Snapshot& a, const Snapshot& b) {
    const auto& x = a.state;
    const auto& y = b.state;
    return a.flags == b.flags && a.capacity == b.capacity && a.block == b.block &&
        x.st_dev == y.st_dev && x.st_ino == y.st_ino && x.st_rdev == y.st_rdev &&
        x.st_mode == y.st_mode && x.st_size == y.st_size &&
        x.st_mtim.tv_sec == y.st_mtim.tv_sec && x.st_mtim.tv_nsec == y.st_mtim.tv_nsec &&
        x.st_ctim.tv_sec == y.st_ctim.tv_sec && x.st_ctim.tv_nsec == y.st_ctim.tv_nsec;
}
bool alias(const Snapshot& a, const Snapshot& b) {
    if (a.block && b.block) return a.state.st_rdev == b.state.st_rdev;
    return a.state.st_dev == b.state.st_dev && a.state.st_ino == b.state.st_ino;
}
struct Digest {
    std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> value{EVP_MD_CTX_new(), EVP_MD_CTX_free};
    Digest() { if (!value || EVP_DigestInit_ex(value.get(), EVP_sha256(), nullptr) != 1) refuse(); }
    void update(const unsigned char* bytes, size_t count) {
        if (EVP_DigestUpdate(value.get(), bytes, count) != 1) refuse();
    }
    std::array<unsigned char, 32> finish() {
        std::array<unsigned char, 32> out{};
        unsigned count = 0;
        if (EVP_DigestFinal_ex(value.get(), out.data(), &count) != 1 || count != out.size()) refuse();
        return out;
    }
};
std::string hex(const std::array<unsigned char, 32>& bytes) {
    constexpr char digits[] = "0123456789abcdef";
    std::string out;
    out.reserve(64);
    for (const auto byte : bytes) { out += digits[byte >> 4]; out += digits[byte & 15]; }
    return out;
}
uint32_t le32(const unsigned char* p) {
    return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
}
uint64_t le64(const unsigned char* p) { return le32(p) | uint64_t(le32(p + 4)) << 32; }
uint64_t kernel_end(const unsigned char* first, size_t size, const ValidatedCohortManifest& manifest) {
    if (size < page + 64 || std::memcmp(first, "ANDROID!", 8) || le32(first + 20) != 1584 ||
        le32(first + 40) != 4 || le32(first + 12) || le32(first + 1580) ||
        !std::memchr(first + 44, 0, 1536)) refuse();
    for (size_t i = 24; i < 40; ++i) if (first[i]) refuse();
    const uint64_t kernel = le32(first + 8);
    if (kernel < 64 || kernel != manifest.kernel_image.bytes || kernel > maximum_image ||
        page + (kernel + page - 1) / page * page > manifest.boot.bytes) refuse();
    const auto* image = first + page;
    const uint64_t memory_size = le64(image + 16);
    if (le32(image + 56) != 0x644d5241 || memory_size < kernel || memory_size > maximum_image ||
        (le64(image + 24) & 1)) refuse();
    return page + kernel;
}
}

VerifiedBootContents::VerifiedBootContents(VerifiedVbmetaCohort cohort,
    std::unique_ptr<OwnedBootDescriptors> descriptors, std::array<BootContentIdentity, 3> identities,
    uint64_t bytes, BootSlot slot)
    : cohort_(std::move(cohort)), descriptors_(std::move(descriptors)), identities_(identities),
      verified_bytes_(bytes), slot_(slot) {}
VerifiedBootContents::~VerifiedBootContents() = default;
VerifiedBootContents::VerifiedBootContents(VerifiedBootContents&&) noexcept = default;
VerifiedBootContents& VerifiedBootContents::operator=(VerifiedBootContents&&) noexcept = default;

VerifiedBootContents verify_boot_contents_fds(const VerifiedVbmetaCohort& cohort,
                                              const std::array<int, 3>& descriptors, BootSlot slot) {
    if (slot != BootSlot::A && slot != BootSlot::B) refuse();
    const auto until = Clock::now() + std::chrono::seconds(30);
    const size_t selected = slot == BootSlot::A ? 0 : 1;
    const auto& geometry = cohort.observed_geometry();
    const std::array<uint64_t, 3> capacities{geometry.boot_bytes[selected],
        geometry.vendor_boot_bytes[selected], geometry.dtbo_bytes[selected]};
    const auto& manifest = cohort.manifest();
    const std::array<const CohortPayload*, 3> payloads{&manifest.boot, &manifest.vendor_boot, &manifest.dtbo};
    std::array<Snapshot, 3> initial{};
    // Validate all originals before allocating duplicates, so an invalid input
    // number cannot accidentally become a descriptor allocated by this call.
    for (size_t i = 0; i < 3; ++i) initial[i] = snapshot(descriptors[i], capacities[i], payloads[i]->bytes);
    for (size_t i = 0; i < 3; ++i)
        for (size_t j = 0; j < i; ++j) if (alias(initial[i], initial[j])) refuse();
    auto owned = std::make_unique<OwnedBootDescriptors>();
    for (size_t i = 0; i < 3; ++i) {
        owned->values[i] = fcntl(descriptors[i], F_DUPFD_CLOEXEC, 3);
        if (owned->values[i] < 0 || !same(initial[i], snapshot(owned->values[i], capacities[i], payloads[i]->bytes))) refuse();
    }
    std::array<unsigned char, chunk_bytes> buffer{};
    uint64_t total = 0;
    for (size_t i = 0; i < 3; ++i) {
        Digest plain, salted;
        std::unique_ptr<Digest> kernel;
        if (i == 0) kernel = std::make_unique<Digest>();
        const auto& expected = cohort.boot_hashes()[i];
        salted.update(expected.salt.data(), expected.salt.size());
        uint64_t offset = 0, image_end = 0;
        while (offset < expected.image_bytes) {
            deadline(until);
            const size_t wanted = static_cast<size_t>(std::min<uint64_t>(buffer.size(), expected.image_bytes - offset));
            size_t have = 0;
            while (have < wanted) {
                deadline(until);
                const auto count = pread(owned->values[i], buffer.data() + have, wanted - have,
                                         static_cast<off_t>(offset + have));
                if (count < 0 && errno == EINTR) continue;
                if (count <= 0) refuse();
                have += static_cast<size_t>(count);
            }
            if (i == 0 && offset == 0) image_end = kernel_end(buffer.data(), have, manifest);
            plain.update(buffer.data(), have);
            salted.update(buffer.data(), have);
            if (kernel) {
                const auto begin = std::max<uint64_t>(offset, page);
                const auto end = std::min<uint64_t>(offset + have, image_end);
                if (end > begin) kernel->update(buffer.data() + (begin - offset), static_cast<size_t>(end - begin));
            }
            offset += have;
            total += have;
        }
        if (hex(plain.finish()) != payloads[i]->sha256 || salted.finish() != expected.digest ||
            (kernel && hex(kernel->finish()) != manifest.kernel_image.sha256)) refuse();
    }
    deadline(until);
    std::array<BootContentIdentity, 3> identities{};
    for (size_t i = 0; i < 3; ++i) {
        if (!same(initial[i], snapshot(owned->values[i], capacities[i], payloads[i]->bytes))) refuse();
        identities[i] = {initial[i].block, initial[i].state.st_dev, initial[i].state.st_ino,
                         initial[i].state.st_rdev, initial[i].capacity};
    }
    deadline(until);
    return {cohort, std::move(owned), identities, total, slot};
}
}

#ifdef UKE_COHORT_CONTENT_CLI
namespace {
struct CloseDirectory { void operator()(DIR* value) const noexcept { if (value) closedir(value); } };
size_t descriptor_count() {
    std::unique_ptr<DIR, CloseDirectory> directory(opendir("/proc/self/fd"));
    if (!directory) throw std::runtime_error("fd count");
    size_t result = 0;
    while (const auto* entry = readdir(directory.get()))
        if (entry->d_name[0] != '.') ++result;
    return result;
}
}
// Inspection fixtures only. Numbers, slot and pins are not physical authority.
int main(int argc, char** argv) {
    if (argc != 20) return 2;
    size_t before_content = 0;
    bool counting = false;
    try {
        auto number = [](const char* input) {
            std::string_view value(input);
            uint64_t result = 0;
            if (value.empty() || value.size() > 13 || (value.size() > 1 && value.front() == '0') ||
                value.find_first_not_of("0123456789") != std::string_view::npos) throw std::runtime_error("number");
            const auto converted = std::from_chars(value.data(), value.data() + value.size(), result);
            if (converted.ec != std::errc{} || converted.ptr != value.data() + value.size()) throw std::runtime_error("number");
            return result;
        };
        const uke::protected_boot::VbmetaTrustPins trust{argv[2], argv[3]};
        const uke::protected_boot::ImmutableKernelContext expected{argv[4], argv[5], argv[6]};
        const uke::protected_boot::ObservedBootGeometry observed{number(argv[7]), number(argv[8]), number(argv[9]),
            {number(argv[10]), number(argv[11])}, {number(argv[12]), number(argv[13])}, {number(argv[14]), number(argv[15])}};
        const std::string_view slot(argv[16]);
        if (slot != "a" && slot != "b") throw std::runtime_error("slot");
        std::array<int, 3> fds{};
        std::array<off_t, 3> positions{};
        for (size_t i = 0; i < fds.size(); ++i) {
            const auto value = number(argv[17 + i]);
            if (value < 3 || value > INT_MAX) throw std::runtime_error("fd");
            fds[i] = static_cast<int>(value);
            positions[i] = lseek(fds[i], 0, SEEK_CUR);
        }
        const auto bytes = uke::protected_boot::read_cohort_metadata_file(argv[1], 65536);
        const auto metadata = uke::protected_boot::verify_vbmeta_cohort_bytes(bytes, trust, expected, observed);
        before_content = descriptor_count();
        counting = true;
        nlohmann::json report;
        {
        const auto verified = uke::protected_boot::verify_boot_contents_fds(metadata, fds,
            slot == "a" ? uke::protected_boot::BootSlot::A : uke::protected_boot::BootSlot::B);
        size_t block_count = 0;
        for (size_t i = 0; i < fds.size(); ++i) {
            if (verified.identities()[i].block_device) ++block_count;
            if (positions[i] < 0 || lseek(fds[i], 0, SEEK_CUR) != positions[i]) throw std::runtime_error("position");
        }
        struct rusage usage{};
        if (getrusage(RUSAGE_SELF, &usage)) throw std::runtime_error("usage");
        report = nlohmann::json{{"avb_and_cohort_metadata_verified", true}, {"fd_contents_verified", true},
            {"plain_and_salted_prefixes_matched", true}, {"kernel_image_slice_matched", true},
            {"verified_bytes", verified.verified_bytes()}, {"block_input_count", block_count},
            {"io_buffer_bytes", 65536}, {"peak_rss_kib", usage.ru_maxrss}, {"caller_positions_unchanged", true},
            {"physical_identity_verified", false}, {"selected_slot_bound", false}, {"booted_kernel_verified", false},
            {"rollback_state_verified", false}, {"hardware_trust_qualified", false}, {"role_admitted", false},
            {"operating_system_booted", false}, {"storage_or_key_release_executed", false}};
        }
        if (descriptor_count() != before_content) throw std::runtime_error("fd leak");
        counting = false;
        report["owned_handles_released"] = true;
        std::cout << report.dump() << '\n';
        return 0;
    } catch (const std::exception&) {
        if (counting) {
            try {
                if (descriptor_count() != before_content) {
                    std::cerr << "UKE_COHORT_CONTENT_DESCRIPTOR_LEAK\n";
                    return 3;
                }
            } catch (...) { return 3; }
        }
        std::cerr << "UKE_COHORT_CONTENT_REJECTED\n";
        return 1;
    }
}
#endif
