// SPDX-License-Identifier: MIT
#include "protected-cohort-vbmeta.hpp"
#include <chrono>
#include <libavb/libavb.h>
#include <linux/fs.h>
#include <openssl/evp.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <stdexcept>
#include <string_view>
#include <type_traits>
#include <vector>
#ifdef UKE_COHORT_VBMETA_CLI
#include <charconv>
#include <iostream>
#include <nlohmann/json.hpp>
#endif

namespace uke::protected_boot {
struct OwnedVbmetaDescriptor {
    int value = -1;
    ~OwnedVbmetaDescriptor() { if (value >= 0) close(value); }
};
namespace {
static_assert(!std::is_default_constructible_v<VerifiedVbmetaCohort>);
static_assert(!std::is_aggregate_v<VerifiedVbmetaCohort>);
constexpr size_t maximum_vbmeta = 65536;
constexpr std::array<std::string_view, 8> property_names{
    "com.uke.protected.cohort", "com.uke.protected.signature", "com.uke.protected.public_key",
    "com.android.build.system.os_version", "com.android.build.system.security_patch",
    "com.android.build.vendor.security_patch", "com.android.build.boot.os_version",
    "com.android.build.boot.security_patch"};
constexpr std::array<std::string_view, 3> partition_names{"boot", "vendor_boot", "dtbo"};
[[noreturn]] void refuse() { throw std::runtime_error("VBMeta cohort rejected"); }
bool hex(const std::string& value) {
    return value.size() == 64 && value.find_first_not_of("0123456789abcdef") == std::string::npos &&
           value.find_first_not_of('0') != std::string::npos;
}
bool zero(std::span<const unsigned char> bytes) {
    return std::all_of(bytes.begin(), bytes.end(), [](unsigned char value) { return value == 0; });
}
std::string sha256(std::span<const unsigned char> bytes) {
    std::array<unsigned char, 32> digest{};
    size_t written = 0;
    if (EVP_Q_digest(nullptr, "SHA256", nullptr, bytes.data(), bytes.size(), digest.data(), &written) != 1 ||
        written != digest.size()) refuse();
    constexpr char digits[] = "0123456789abcdef";
    std::string out;
    out.reserve(64);
    for (const auto value : digest) { out += digits[value >> 4]; out += digits[value & 15]; }
    return out;
}
template<size_t N> size_t index_of(std::string_view name, const std::array<std::string_view, N>& names) {
    for (size_t i = 0; i < N; ++i) if (name == names[i]) return i;
    refuse();
}
struct Descriptors {
    size_t count = 0;
    std::array<bool, property_names.size()> property_seen{};
    std::array<bool, partition_names.size()> hash_seen{};
    std::array<std::vector<unsigned char>, property_names.size()> properties;
    std::array<AvbBootHash, 3> hashes{};
};
void property(const AvbDescriptor* raw, const AvbDescriptor& header, Descriptors& output) {
    if (header.num_bytes_following < sizeof(AvbPropertyDescriptor) - sizeof(AvbDescriptor) + 2) refuse();
    AvbPropertyDescriptor descriptor{};
    if (!avb_property_descriptor_validate_and_byteswap(
            reinterpret_cast<const AvbPropertyDescriptor*>(raw), &descriptor)) refuse();
    const auto* bytes = reinterpret_cast<const unsigned char*>(raw);
    const auto length = sizeof(AvbDescriptor) + header.num_bytes_following;
    const auto key_end = sizeof(AvbPropertyDescriptor) + descriptor.key_num_bytes;
    const auto value_end = key_end + 1 + descriptor.value_num_bytes;
    // Upstream's bounds check above proves these additions fit the descriptor.
    if (key_end >= length || value_end >= length || bytes[key_end] || bytes[value_end]) refuse();
    const auto expected_length = (value_end + 1 + 7) / 8 * 8;
    if (length != expected_length || !zero({bytes + value_end + 1, static_cast<size_t>(length - value_end - 1)})) refuse();
    const auto index = index_of(std::string_view(reinterpret_cast<const char*>(bytes + sizeof(AvbPropertyDescriptor)),
                                                static_cast<size_t>(descriptor.key_num_bytes)), property_names);
    if (output.property_seen[index]) refuse();
    const auto size = descriptor.value_num_bytes;
    const bool os_version = index == 3 || index == 6;
    if ((index == 0 && (size == 0 || size > 65536)) || (index == 1 && size != 512) ||
        (index == 2 && (size == 0 || size > 8192)) ||
        (index >= 3 && (os_version ? (size == 0 || size > 8) : size != 10))) refuse();
    output.property_seen[index] = true;
    output.properties[index].assign(bytes + key_end + 1, bytes + value_end);
}

uint32_t decimal_component(std::string_view value) {
    uint32_t number = 0;
    const auto parsed = std::from_chars(value.data(), value.data() + value.size(), number);
    if (value.empty() || parsed.ec != std::errc{} || parsed.ptr != value.data() + value.size()) refuse();
    return number;
}

uint32_t keymint_os_version(std::string_view value) {
    // Android encodes A.B.C as A*10000 + B*100 + C.
    uint32_t version = 0;
    for (unsigned slot = 0; slot < 3; ++slot) {
        version *= 100;
        if (value.empty()) continue;
        const size_t dot = value.find('.');
        const auto component = value.substr(0, dot);
        if (component.size() > 2 || (component.size() > 1 && component.front() == '0')) refuse();
        version += decimal_component(component);
        if (dot == value.npos) {
            value = {};
        } else {
            value.remove_prefix(dot + 1);
            if (value.empty() || slot == 2) refuse();
        }
    }
    if (!version) refuse();
    return version;
}

uint32_t keymint_patch_date(std::string_view value) {
    if (value.size() != 10 || value[4] != '-' || value[7] != '-') refuse();
    const auto year = decimal_component(value.substr(0, 4));
    const auto month = decimal_component(value.substr(5, 2));
    const auto day = decimal_component(value.substr(8, 2));
    if (!year || !std::chrono::year_month_day{std::chrono::year(static_cast<int>(year)),
            std::chrono::month(month), std::chrono::day(day)}.ok()) refuse();
    return year * 10000 + month * 100 + day;
}

std::optional<KeyMintVersionBinding> keymint_version_binding(const Descriptors& descriptors) {
    const auto& seen = descriptors.property_seen;
    if (std::none_of(seen.begin() + 3, seen.end(), [](bool value) { return value; })) return std::nullopt;
    if (!seen[3] || !seen[4] || !seen[5] || seen[6] != seen[7]) refuse();
    auto property_text = [&](size_t index) {
        const auto& bytes = descriptors.properties[index];
        return std::string_view(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    };
    const auto version = keymint_os_version(property_text(3));
    const auto patch = keymint_patch_date(property_text(4));
    KeyMintVersionBinding binding{version, patch / 100, keymint_patch_date(property_text(5)), std::nullopt};
    if (!seen[6]) return binding;

    // ABL consumes the boot properties. The Fedora cohort describes one OS
    // release for both consumers. Keep the representations distinct.
    if (keymint_os_version(property_text(6)) != version ||
        keymint_patch_date(property_text(7)) != patch) refuse();
    const uint32_t year = patch / 10000;
    if (year < 2000 || year > 2127) refuse();
    const uint32_t packed_version = ((version / 10000) << 14) |
        (((version / 100) % 100) << 7) | (version % 100);
    const uint32_t packed_patch = ((patch % 100) << 11) |
        ((year - 2000) << 4) | (patch / 100 % 100);
    binding.abl_boot = AblBootVersion{packed_version, packed_patch};
    return binding;
}
void hash_descriptor(const AvbDescriptor* raw, const AvbDescriptor& header, Descriptors& output) {
    if (header.num_bytes_following < sizeof(AvbHashDescriptor) - sizeof(AvbDescriptor)) refuse();
    AvbHashDescriptor descriptor{};
    if (!avb_hash_descriptor_validate_and_byteswap(reinterpret_cast<const AvbHashDescriptor*>(raw), &descriptor)) refuse();
    constexpr std::array<unsigned char, 32> algorithm{'s', 'h', 'a', '2', '5', '6'};
    if (std::memcmp(descriptor.hash_algorithm, algorithm.data(), algorithm.size()) || descriptor.flags ||
        !zero(descriptor.reserved) || descriptor.salt_len != 32 || descriptor.digest_len != 32 ||
        !descriptor.image_size || descriptor.image_size > 536870912) refuse();
    const auto* bytes = reinterpret_cast<const unsigned char*>(raw);
    const auto length = sizeof(AvbDescriptor) + header.num_bytes_following;
    const auto name_end = sizeof(AvbHashDescriptor) + descriptor.partition_name_len;
    const auto digest_end = name_end + descriptor.salt_len + descriptor.digest_len;
    if (digest_end > length || length != (digest_end + 7) / 8 * 8 ||
        !zero({bytes + digest_end, static_cast<size_t>(length - digest_end)})) refuse();
    const auto index = index_of(std::string_view(reinterpret_cast<const char*>(bytes + sizeof(AvbHashDescriptor)),
                                                descriptor.partition_name_len), partition_names);
    if (output.hash_seen[index]) refuse();
    auto& hash = output.hashes[index];
    hash.image_bytes = descriptor.image_size;
    std::copy_n(bytes + name_end, 32, hash.salt.begin());
    std::copy_n(bytes + name_end + 32, 32, hash.digest.begin());
    if (zero(hash.digest)) refuse();
    output.hash_seen[index] = true;
}
bool collect(const AvbDescriptor* descriptor, void* data) noexcept {
    // Never unwind a C++ exception through upstream C library frames.
    try {
        auto& output = *static_cast<Descriptors*>(data);
        if (++output.count > property_names.size() + partition_names.size()) return false;
        AvbDescriptor header{};
        if (!avb_descriptor_validate_and_byteswap(descriptor, &header)) return false;
        if (header.tag == AVB_DESCRIPTOR_TAG_PROPERTY) property(descriptor, header, output);
        else if (header.tag == AVB_DESCRIPTOR_TAG_HASH) hash_descriptor(descriptor, header, output);
        else return false;
        return true;
    } catch (...) { return false; }
}
struct FdState {
    struct stat value{};
    int flags = 0;
    bool block = false;
    bool operator==(const FdState& other) const {
        const auto& x = value; const auto& y = other.value;
        return flags == other.flags && block == other.block && x.st_dev == y.st_dev &&
            x.st_ino == y.st_ino && x.st_rdev == y.st_rdev && x.st_mode == y.st_mode &&
            x.st_size == y.st_size && x.st_mtim.tv_sec == y.st_mtim.tv_sec &&
            x.st_mtim.tv_nsec == y.st_mtim.tv_nsec && x.st_ctim.tv_sec == y.st_ctim.tv_sec &&
            x.st_ctim.tv_nsec == y.st_ctim.tv_nsec;
    }
};
FdState fd_state(int fd, uint64_t capacity) {
    FdState out;
    out.flags = fcntl(fd, F_GETFL);
    if (fd < 3 || out.flags < 0 || (out.flags & O_ACCMODE) != O_RDONLY ||
        (out.flags & (O_PATH | O_DIRECT)) || fstat(fd, &out.value)) refuse();
    out.block = S_ISBLK(out.value.st_mode);
    if (out.block) {
        unsigned long long bytes = 0;
        int sector = 0;
        if (ioctl(fd, BLKGETSIZE64, &bytes) || bytes != capacity ||
            ioctl(fd, BLKSSZGET, &sector) || sector != 4096) refuse();
    } else if (!S_ISREG(out.value.st_mode) || out.value.st_size < 0 ||
               static_cast<uint64_t>(out.value.st_size) != capacity) refuse();
    return out;
}
}

VerifiedVbmetaCohort verify_vbmeta_cohort_bytes(std::span<const unsigned char> candidate,
                                              const VbmetaTrustPins& trusted,
                                              const ImmutableKernelContext& expected,
                                              const ObservedBootGeometry& observed) {
    if (candidate.size() < AVB_VBMETA_IMAGE_HEADER_SIZE || candidate.size() > maximum_vbmeta ||
        !hex(trusted.avb_key_sha256) || !hex(trusted.cohort_spki_sha256)) refuse();
    // The original descriptor API requires word alignment. This owned copy
    // also prevents caller path changes from replacing bytes during parsing.
    const std::vector<unsigned char> bytes(candidate.begin(), candidate.end());
    const uint8_t* key = nullptr;
    size_t key_size = 0;
    if (avb_vbmeta_image_verify(bytes.data(), bytes.size(), &key, &key_size) != AVB_VBMETA_VERIFY_RESULT_OK ||
        !key || key_size != 1032 || sha256({key, key_size}) != trusted.avb_key_sha256) refuse();
    AvbVBMetaImageHeader header{};
    avb_vbmeta_image_header_to_host_byte_order(reinterpret_cast<const AvbVBMetaImageHeader*>(bytes.data()), &header);
    if (header.required_libavb_version_major != 1 || header.required_libavb_version_minor != 0 ||
        header.algorithm_type != AVB_ALGORITHM_TYPE_SHA256_RSA4096 || header.flags ||
        header.rollback_index_location || !zero(header.reserved) ||
        header.hash_offset != 0 || header.hash_size != 32 || header.signature_offset != 32 ||
        header.signature_size != 512 || header.authentication_data_block_size != 576 ||
        header.public_key_metadata_size || header.public_key_metadata_offset > header.auxiliary_data_block_size) refuse();
    const auto aux_size = header.auxiliary_data_block_size;
    if (header.descriptors_offset > aux_size || header.descriptors_size > aux_size - header.descriptors_offset ||
        header.descriptors_offset % 8 || header.descriptors_size % 8 || !header.descriptors_size ||
        header.public_key_offset > aux_size || header.public_key_size > aux_size - header.public_key_offset) refuse();
    const auto descriptor_end = header.descriptors_offset + header.descriptors_size;
    const auto key_end = header.public_key_offset + header.public_key_size;
    if (!(descriptor_end <= header.public_key_offset || key_end <= header.descriptors_offset)) refuse();
    const auto end = AVB_VBMETA_IMAGE_HEADER_SIZE + header.authentication_data_block_size + aux_size;
    if (end > bytes.size() || !zero({bytes.data() + end, bytes.size() - static_cast<size_t>(end)}) ||
        !zero({bytes.data() + AVB_VBMETA_IMAGE_HEADER_SIZE + 544, 32})) refuse();
    Descriptors descriptors;
    if (!avb_descriptor_foreach(bytes.data(), bytes.size(), collect, &descriptors) ||
        !std::all_of(descriptors.property_seen.begin(), descriptors.property_seen.begin() + 3, [](bool value) { return value; }) ||
        !std::all_of(descriptors.hash_seen.begin(), descriptors.hash_seen.end(), [](bool value) { return value; })) refuse();
    const auto verified = verify_cohort_signature_bytes(descriptors.properties[2], trusted.cohort_spki_sha256,
                                                        descriptors.properties[0], descriptors.properties[1]);
    auto manifest = validate_cohort_manifest(verified, expected, observed);
    const std::array<uint64_t, 3> sizes{manifest.boot.bytes, manifest.vendor_boot.bytes, manifest.dtbo.bytes};
    for (size_t i = 0; i < sizes.size(); ++i)
        if (sizes[i] != descriptors.hashes[i].image_bytes) refuse();
    return {std::move(manifest), std::move(descriptors.hashes), observed,
            sha256({bytes.data(), static_cast<size_t>(end)}), header.rollback_index, keymint_version_binding(descriptors)};
}

std::vector<unsigned char> VerifiedVbmetaCohort::prepare_keymint_configure(std::string_view bootloader_digest) const {
    if (bootloader_digest != vbmeta_sha256_ || !keymint_ || !keymint_->abl_boot) refuse();

    // Both fitted keymaster64 variants use little-endian command 0x2116,
    // followed by a CBOR map. Entry 22 counts the following three values.
    std::vector<unsigned char> frame{0x16, 0x21, 0, 0, 0xa4, 22, 3};
    auto append_unsigned = [&](uint32_t value) {
        if (value < 24) {
            frame.push_back(static_cast<unsigned char>(value));
            return;
        }
        const unsigned width = value <= 0xff ? 1 : value <= 0xffff ? 2 : 4;
        frame.push_back(width == 1 ? 0x18 : width == 2 ? 0x19 : 0x1a);
        for (unsigned i = width; i > 0; --i)
            frame.push_back(static_cast<unsigned char>(value >> (8 * (i - 1))));
    };
    append_unsigned(0x300002c1);
    append_unsigned(keymint_->os_version);
    append_unsigned(0x300002c2);
    append_unsigned(keymint_->os_patchlevel);
    append_unsigned(0x300002ce);
    append_unsigned(keymint_->vendor_patchlevel);
    return frame;
}

VerifiedVbmetaFd::VerifiedVbmetaFd(VerifiedVbmetaCohort cohort,
    std::unique_ptr<OwnedVbmetaDescriptor> descriptor, bool block)
    : cohort_(std::move(cohort)), descriptor_(std::move(descriptor)), block_(block) {}
VerifiedVbmetaFd::~VerifiedVbmetaFd() = default;
VerifiedVbmetaFd::VerifiedVbmetaFd(VerifiedVbmetaFd&&) noexcept = default;
VerifiedVbmetaFd& VerifiedVbmetaFd::operator=(VerifiedVbmetaFd&&) noexcept = default;

VerifiedVbmetaFd verify_vbmeta_cohort_fd(int fd, uint64_t capacity, const VbmetaTrustPins& trusted,
                                        const ImmutableKernelContext& expected,
                                        const ObservedBootGeometry& observed) {
    static_assert(!std::is_default_constructible_v<VerifiedVbmetaFd>);
    if (capacity < maximum_vbmeta || capacity > 1048576 || capacity % 4096) refuse();
    const auto initial = fd_state(fd, capacity);
    auto owned = std::make_unique<OwnedVbmetaDescriptor>();
    owned->value = fcntl(fd, F_DUPFD_CLOEXEC, 3);
    if (owned->value < 0 || !(initial == fd_state(owned->value, capacity))) refuse();
    std::array<unsigned char, maximum_vbmeta> bytes{};
    const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    size_t have = 0;
    while (have < bytes.size()) {
        if (std::chrono::steady_clock::now() >= until) refuse();
        const auto count = pread(owned->value, bytes.data() + have, bytes.size() - have, static_cast<off_t>(have));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) refuse();
        have += static_cast<size_t>(count);
    }
    auto cohort = verify_vbmeta_cohort_bytes(bytes, trusted, expected, observed);
    if (std::chrono::steady_clock::now() >= until || !(initial == fd_state(owned->value, capacity))) refuse();
    return {std::move(cohort), std::move(owned), initial.block};
}
}

#ifdef UKE_COHORT_VBMETA_CLI
// Inspection only; supplied CLI pins/context are ephemeral fixtures.
int main(int argc, char** argv) {
    if (argc != 16 && argc != 17) return 2;
    try {
        auto number = [](const char* input) {
            std::string_view value(input);
            uint64_t result = 0;
            if (value.empty() || value.size() > 13 || (value.size() > 1 && value.front() == '0') ||
                value.find_first_not_of("0123456789") != std::string_view::npos) throw std::runtime_error("number");
            const auto conversion = std::from_chars(value.data(), value.data() + value.size(), result);
            if (conversion.ec != std::errc{} || conversion.ptr != value.data() + value.size()) throw std::runtime_error("number");
            return result;
        };
        const uke::protected_boot::VbmetaTrustPins trust{argv[2], argv[3]};
        const uke::protected_boot::ImmutableKernelContext expected{argv[4], argv[5], argv[6]};
        const uke::protected_boot::ObservedBootGeometry observed{number(argv[7]), number(argv[8]), number(argv[9]),
            {number(argv[10]), number(argv[11])}, {number(argv[12]), number(argv[13])}, {number(argv[14]), number(argv[15])}};
        const auto bytes = uke::protected_boot::read_cohort_metadata_file(argv[1], 65536);
        const auto result = uke::protected_boot::verify_vbmeta_cohort_bytes(bytes, trust, expected, observed);
        nlohmann::json report{{"avb_signature_verified", true}, {"cohort_signature_verified", true},
            {"manifest_schema_valid", true}, {"exact_geometry_selected", true}, {"both_slot_limits_checked", true},
            {"boot_hash_descriptors_bound", true}, {"vbmeta_sha256", result.vbmeta_sha256()},
            {"signed_rollback_index", result.signed_rollback_index()}, {"boot_payloads_verified", false},
            {"rollback_state_verified", false}, {"physical_identity_verified", false},
            {"hardware_trust_qualified", false}, {"role_admitted", false}, {"storage_or_key_release_executed", false}};
        if (const auto& version = result.keymint_version_binding()) {
            report["keymint_version_binding"] = {{"os_version", version->os_version},
                {"os_patchlevel", version->os_patchlevel}, {"vendor_patchlevel", version->vendor_patchlevel}};
            if (const auto& boot = version->abl_boot) {
                report["abl_boot_version"] = {{"os_version", boot->os_version},
                    {"security_patch", boot->security_patch}};
            }
        }
        if (argc == 17) {
            report["keymint_configure_frame"] = result.prepare_keymint_configure(argv[16]);
            report["keymint_configure_sent"] = false;
        }
        std::cout << report.dump() << '\n';
        return 0;
    } catch (const std::exception&) {
        std::cerr << "UKE_COHORT_VBMETA_REJECTED\n";
        return 1;
    }
}
#endif
