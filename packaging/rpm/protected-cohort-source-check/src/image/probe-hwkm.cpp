// SPDX-License-Identifier: MIT
// Disposable diagnostic only. A private test record is never a volume key
// or authorization for production key release, mapping or boot policy.
#include "hwkm-wrapped-key.hpp"
#include "hwkm-disposable-record.hpp"
#include "hwkm-inlinecrypt-read.hpp"
#include "protected-physical-cohort.hpp"
#include <nlohmann/json.hpp>
#include <openssl/sha.h>
#include <linux/fs.h>
#include <linux/magic.h>
#include <linux/openat2.h>
#include <systemd/sd-id128.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <array>
#include <cerrno>
#include <charconv>
#include <iostream>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <system_error>
#include <string_view>
#include <utility>

namespace {
using namespace uke::protected_boot;
[[noreturn]] void reject() { throw std::runtime_error("HWKM probe rejected"); }
struct Fd {
    int fd;
    explicit Fd(int value) : fd(value) { if (fd < 0) reject(); }
    ~Fd() { close(fd); }
    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;
};
size_t descriptor_count() {
    DIR* directory = opendir("/proc/self/fd");
    if (!directory) reject();
    size_t count = 0;
    while (readdir(directory)) ++count;
    closedir(directory);
    return count;
}
int beneath(int parent, const std::string& name, int access = O_RDONLY) {
    struct open_how how{};
    how.flags = static_cast<unsigned>(access) | O_CLOEXEC;
    how.resolve = RESOLVE_BENEATH | RESOLVE_NO_SYMLINKS | RESOLVE_NO_MAGICLINKS;
    return static_cast<int>(syscall(SYS_openat2, parent, name.c_str(), &how, sizeof(how)));
}
std::optional<std::string> attribute(int root, const std::string& path) {
    int value = beneath(root, path);
    if (value < 0 && errno == ENOENT) return std::nullopt;
    Fd fd(value);
    struct statfs fs{};
    if (fstatfs(fd.fd, &fs) || fs.f_type != SYSFS_MAGIC) reject();
    std::array<char, 65> text{};
    const auto bytes = read(fd.fd, text.data(), text.size());
    if (bytes <= 0 || bytes > 64) reject();
    char extra = 0;
    if (read(fd.fd, &extra, 1) != 0) reject();
    return std::string(text.data(), static_cast<size_t>(bytes));
}
bool supported(const std::optional<std::string>& value) {
    if (!value) return false;
    if (*value != "supported\n") reject();
    return true;
}
uint64_t number(const std::optional<std::string>& input, int base) {
    if (!input) reject();
    std::string_view value(*input);
    if (value.empty() || value.back() != '\n') reject();
    value.remove_suffix(1);
    if (base == 16) { if (!value.starts_with("0x")) reject(); value.remove_prefix(2); }
    uint64_t out = 0;
    const auto parsed = std::from_chars(value.data(), value.data() + value.size(), out, base);
    if (parsed.ec != std::errc{} || parsed.ptr != value.data() + value.size()) reject();
    return out;
}
struct Caps {
    bool wrapped, raw, xts_4k;
    uint64_t slots;
    bool operator==(const Caps&) const = default;
};
Caps capabilities(int sys, const PhysicalPartitionFacts& part) {
    if (!part.disk_syspath.starts_with("/sys/devices/")) reject();
    const auto path = part.disk_syspath.substr(5) + "/queue/crypto/";
    const auto xts = attribute(sys, path + "modes/AES-256-XTS");
    const auto slots = number(attribute(sys, path + "num_keyslots"), 10);
    if (!slots || slots > 4096) reject();
    return {supported(attribute(sys, path + "hw_wrapped_keys")),
        supported(attribute(sys, path + "raw_keys")),
        xts && (number(xts, 16) & 4096), slots};
}
enum class Mode {
    Inspect, Exercise, ReadInlinecrypt, ReadInlinecryptRecord, CreateRecord, PrepareRecord, RemoveRecord,
    WriteRescueBlock, ReadRescueBlock
};

struct VbmetaPin {
    PhysicalRole role;
    std::string_view digest;
};

struct RescuePins {
    std::string_view layout_digest;
    std::string_view raw_digest;
};

bool is_sha256(std::string_view value) {
    return value.size() == SHA256_DIGEST_LENGTH * 2 &&
        value.find_first_not_of("0123456789abcdef") == value.npos;
}

bool matches_sha256(std::span<const unsigned char> bytes, std::string_view expected) {
    std::array<unsigned char, SHA256_DIGEST_LENGTH> digest{};
    if (!SHA256(bytes.data(), bytes.size(), digest.data())) reject();
    constexpr char hex[] = "0123456789abcdef";
    for (size_t i = 0; i < digest.size(); ++i) {
        if (expected[2 * i] != hex[digest[i] >> 4] || expected[2 * i + 1] != hex[digest[i] & 15])
            return false;
    }
    return true;
}

// This digest identifies a physical VBMeta partition in a test profile.
// It is independent of the verified-boot hash or any KeyMint authorization.
bool match_vbmeta(int dev, const PhysicalPartitionFacts& part, std::string_view expected) {
    constexpr size_t vbmeta_bytes = 128 * 1024;
    if (part.capacity_bytes != vbmeta_bytes) reject();
    Fd fd(beneath(dev, part.name));
    struct stat st{};
    uint64_t capacity = 0, sequence = 0;
    if (fstat(fd.fd, &st) || !S_ISBLK(st.st_mode) || st.st_rdev != part.device_number ||
        ioctl(fd.fd, BLKGETSIZE64, &capacity) || capacity != vbmeta_bytes ||
        ioctl(fd.fd, BLKGETDISKSEQ, &sequence) || sequence != part.disk_sequence) reject();

    std::array<unsigned char, vbmeta_bytes> bytes{};
    if (pread(fd.fd, bytes.data(), bytes.size(), 0) != static_cast<ssize_t>(bytes.size()) ||
        std::string_view(reinterpret_cast<const char*>(bytes.data()), 4) != "AVB0") reject();
    return matches_sha256(bytes, expected);
}

void verify_rescue_layout(int block, const PhysicalPartitionFacts& part, std::string_view expected) {
    // This fixed lab geometry is the 11,274,289,152-byte super device with
    // the Fedora rescue extent beginning at the end of its 1 MiB metadata area.
    if (part.capacity_bytes != 11274289152ULL) reject();
    DIR* holders = opendir((part.syspath + "/holders").c_str());
    if (!holders) reject();
    bool occupied = false;
    errno = 0;
    while (const auto* entry = readdir(holders)) {
        const std::string_view name(entry->d_name);
        occupied |= name != "." && name != "..";
    }
    const int read_error = errno;
    if (closedir(holders) || read_error || occupied) reject();
    alignas(4096) std::array<unsigned char, 1024 * 1024> bytes{};
    if (pread(block, bytes.data(), bytes.size(), 0) != static_cast<ssize_t>(bytes.size()) ||
        !matches_sha256(bytes, expected)) reject();
}
// The fixed root-owned directory contains only this diagnostic's disposable
// record. Never accept a caller-supplied key path or follow a parent symlink.
int record_directory(bool create) {
    if (geteuid() != 0) reject();
    Fd root(open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    Fd parent(beneath(root.fd, "var/lib"));
    struct stat st{};
    if (fstat(parent.fd, &st) || !S_ISDIR(st.st_mode) || st.st_uid != 0 || (st.st_mode & 0022)) reject();
    if (create && mkdirat(parent.fd, "uke-hwkm-probe", 0700) < 0 && errno != EEXIST) reject();
    const int result = openat(parent.fd, "uke-hwkm-probe", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (result < 0 && !create && errno == ENOENT) return -1;
    if (result < 0) reject();
    if (create && fsync(parent.fd) < 0) { close(result); reject(); }
    return result;
}
std::pair<nlohmann::json, int> probe(Mode mode, const std::optional<VbmetaPin>& pin,
        const std::optional<RescuePins>& rescue, const char*& phase) {
    phase = "physical-owner-open";
    auto devices = open_physical_boot_devices();
    const bool use_record = mode == Mode::ReadInlinecryptRecord || rescue.has_value();
    const bool read_inlinecrypt = mode == Mode::ReadInlinecrypt || use_record;
    // The mounted root has an exclusive block holder. Use a fixed physical
    // DTBO partition for the read-only data-path test and admit its queue.
    const auto role = rescue ? PhysicalRole::Super :
        (read_inlinecrypt ? PhysicalRole::DtboA : PhysicalRole::Userdata);
    const auto& part = devices.partitions()[static_cast<size_t>(role)];
    Fd sys(open("/sys", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    struct statfs fs{};
    if (fstatfs(sys.fd, &fs) || fs.f_type != SYSFS_MAGIC) reject();
    phase = "capabilities-before";
    const auto before = capabilities(sys.fd, part);
    const bool exercise = mode == Mode::Exercise;
    const bool key_operation = exercise || read_inlinecrypt || mode == Mode::CreateRecord || mode == Mode::PrepareRecord;
    auto report = nlohmann::json{{"schema_version", 1}, {"physical_ufs_topology_verified", true},
        {"hardware_wrapped_keys_advertised", before.wrapped}, {"raw_keys_advertised", before.raw},
        {"aes_256_xts_4096_advertised", before.xts_4k}, {"num_keyslots", before.slots},
        {"exercise_requested", exercise}, {"key_ioctl_attempts", 0},
        {"disposable_hardware_key_generated", false}, {"prepared_twice", false},
        {"altered_blob_refused", false}, {"key_persisted", false}, {"volume_or_mapping_written", false},
        {"disposable_record_written", false}, {"disposable_record_removed", false},
        {"prepared_from_persistent_record", false},
        {"module_parameter_changed", false}, {"cold_boot_reuse_proved", false},
        {"temporary_read_only_mapping_used", false}, {"hardware_read_transformed", false},
        {"encrypted_io_proved", false}, {"boot_policy_admitted", false}, {"automatic_unlock_proved", false}};
    int status = 0;
    if (key_operation && (!before.wrapped || before.raw || !before.xts_4k)) {
        report["result"] = "requires-wrapped-only-early-profile";
        status = 77;
    } else if (mode == Mode::RemoveRecord) {
        phase = "record-cleanup";
        const int directory = record_directory(false);
        if (directory >= 0) {
            Fd parent(directory);
            hwkm::disposable::Record record(parent.fd);
            report["disposable_record_removed"] = record.remove();
        }
        report["result"] = "disposable-record-cleanup-complete";
    } else if (key_operation) {
        phase = "physical-key-descriptor";
        Fd dev(open("/dev", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
        Fd block(beneath(dev.fd, part.name, O_RDONLY | (rescue ? O_DIRECT : 0)));
        struct stat st{};
        uint64_t size = 0, sequence = 0;
        int logical = 0;
        if (fstat(block.fd, &st) || !S_ISBLK(st.st_mode) || st.st_rdev != part.device_number ||
            ioctl(block.fd, BLKGETSIZE64, &size) || size != part.capacity_bytes ||
            ioctl(block.fd, BLKGETDISKSEQ, &sequence) || sequence != part.disk_sequence ||
            ioctl(block.fd, BLKSSZGET, &logical) || logical != 4096) reject();
        phase = "physical-owner-before-key";
        devices.revalidate();
        if (pin) {
            phase = "vbmeta-profile-before-key";
            const auto& metadata = devices.partitions()[static_cast<size_t>(pin->role)];
            report["vbmeta_profile_partition"] = metadata.label;
            report["vbmeta_profile_match"] = match_vbmeta(dev.fd, metadata, pin->digest);
            if (!report["vbmeta_profile_match"].get<bool>()) {
                devices.revalidate();
                report["result"] = "vbmeta-profile-mismatch";
                return {std::move(report), 78};
            }
        }
        if (rescue) {
            phase = "rescue-layout-before-key";
            verify_rescue_layout(block.fd, part, rescue->layout_digest);
        }
        if (read_inlinecrypt) {
            auto key = [&] {
                if (use_record) {
                    phase = "record-directory";
                    Fd parent(record_directory(false));
                    phase = "record-read";
                    hwkm::disposable::Record record(parent.fd);
                    return record.read();
                }
                phase = "inlinecrypt-key-generate";
                report["key_ioctl_attempts"] = 1;
                auto generated = hwkm::generate_v2(block.fd);
                report["disposable_hardware_key_generated"] = true;
                return generated;
            }();
            phase = "inlinecrypt-key-prepare";
            report["key_ioctl_attempts"] = use_record ? 1 : 2;
            auto prepared = hwkm::prepare_v2(block.fd, std::move(key));
            devices.revalidate();
            const bool write = mode == Mode::WriteRescueBlock;
            const auto read = rescue
                ? hwkm::exercise_inlinecrypt_rescue_block(block.fd, std::move(prepared), rescue->raw_digest, write, phase)
                : hwkm::exercise_inlinecrypt_read(block.fd, std::move(prepared), phase);
            report["temporary_read_only_mapping_used"] = !write;
            report["hardware_read_transformed"] = true;
            report["source_partition"] = rescue ? "super/system_b" : "dtbo_a";
            report["prepared_from_persistent_record"] = use_record;
            if (rescue) {
                phase = "rescue-layout-after-io";
                verify_rescue_layout(block.fd, part, rescue->layout_digest);
                report["rescue_block_offset_bytes"] = hwkm::rescue_block_offset;
                report["volume_or_mapping_written"] = write;
                report["encrypted_io_proved"] = true;
            }
            if (use_record) {
                phase = "boot-id";
                sd_id128_t boot_id{};
                std::array<char, SD_ID128_STRING_MAX> boot_id_text{};
                if (sd_id128_get_boot(&boot_id) < 0 || sd_id128_is_null(boot_id)) reject();
                report["boot_id"] = sd_id128_to_string(boot_id, boot_id_text.data());
                report["backing_sha256"] = read.backing_sha256;
                report["mapped_sha256"] = read.mapped_sha256;
                report["result"] = rescue
                    ? (write ? "rescue-block-write-and-read-passed" : "rescue-block-read-passed")
                    : "disposable-inlinecrypt-record-read-passed";
            } else {
                report["result"] = "disposable-inlinecrypt-read-passed";
            }
        } else if (!exercise) {
            phase = "record-directory";
            Fd parent(record_directory(mode == Mode::CreateRecord));
            phase = "record-lock";
            hwkm::disposable::Record record(parent.fd);
            if (mode == Mode::CreateRecord) {
                // Refuse an existing record before requesting a new key. An
                // uncertain durable commit must never silently regenerate it.
                phase = "record-presence";
                if (record.exists()) reject();
                report["key_ioctl_attempts"] = 1;
                phase = "record-key-generate";
                auto key = hwkm::generate_v2(block.fd);
                report["disposable_hardware_key_generated"] = true;
                phase = "record-create";
                record.create(key);
                report["key_persisted"] = true;
                report["disposable_record_written"] = true;
                report["result"] = "disposable-record-created";
            } else {
                phase = "record-read";
                auto key = record.read();
                report["key_ioctl_attempts"] = 1;
                phase = "record-key-prepare";
                auto prepared = hwkm::prepare_v2(block.fd, std::move(key));
                if (prepared.lifetime() != hwkm::Lifetime::PerBoot) reject();
                report["prepared_from_persistent_record"] = true;
                report["result"] = "disposable-record-prepared";
            }
        } else {
            phase = "exercise-key-lifecycle";
            report["key_ioctl_attempts"] = 1;
            auto generated = hwkm::generate_v2(block.fd);
            report["disposable_hardware_key_generated"] = true;
            auto again = hwkm::load_long_term_v2(generated.bytes());
            auto damaged = hwkm::load_long_term_v2(generated.bytes());
            {
                report["key_ioctl_attempts"] = 2;
                auto first = hwkm::prepare_v2(block.fd, std::move(generated));
                report["key_ioctl_attempts"] = 3;
                auto second = hwkm::prepare_v2(block.fd, std::move(again));
                if (first.lifetime() != hwkm::Lifetime::PerBoot || second.lifetime() != hwkm::Lifetime::PerBoot) reject();
                report["prepared_twice"] = true;
            }
            // Alter only the disposable copy, inside its locked allocation. No
            // real volume key, key file, import ioctl or firmware state setter.
            auto* bytes = const_cast<unsigned char*>(damaged.bytes().data());
            bytes[hwkm::wrapped_key_bytes / 2] ^= 0x80;
            report["key_ioctl_attempts"] = 4;
            try { (void)hwkm::prepare_v2(block.fd, std::move(damaged)); }
            catch (const std::system_error& error) {
                // An unrelated transport/interruption/unsupported error is not
                // proof of blob authentication. Require a malformed-key error.
                if (error.code().value() != EINVAL && error.code().value() != EBADMSG &&
                    error.code().value() != EKEYREJECTED) throw;
                report["altered_blob_refused"] = true;
            }
            if (!report["altered_blob_refused"].get<bool>()) reject();
            report["result"] = "disposable-key-lifecycle-passed";
        }
    } else report["result"] = "capability-inspection-only";
    phase = "physical-owner-after";
    devices.revalidate();
    phase = "capabilities-after";
    if (before != capabilities(sys.fd, part)) reject();
    return {std::move(report), status};
}
}
int main(int argc, char** argv) {
    if (argc < 2) return 2;
    const std::string_view mode(argv[1]);
    std::optional<VbmetaPin> pin;
    std::optional<RescuePins> rescue;
    Mode action;
    const bool rescue_write = mode == "--write-disposable-rescue-block";
    const bool rescue_read = mode == "--read-disposable-rescue-block";
    if (mode == "--read-disposable-vbmeta-profile-record" || rescue_write || rescue_read) {
        if (argc != (rescue_write || rescue_read ? 6 : 4)) return 2;
        const std::string_view slot(argv[2]), digest(argv[3]);
        if ((slot != "a" && slot != "b") || !is_sha256(digest)) return 2;
        pin = VbmetaPin{slot == "a" ? PhysicalRole::VbmetaA : PhysicalRole::VbmetaB, digest};
        action = Mode::ReadInlinecryptRecord;
        if (rescue_write || rescue_read) {
            if (!is_sha256(argv[4]) || !is_sha256(argv[5])) return 2;
            rescue = RescuePins{argv[4], argv[5]};
            action = rescue_write ? Mode::WriteRescueBlock : Mode::ReadRescueBlock;
        }
    } else if (argc != 2) return 2;
    else if (mode == "--inspect") action = Mode::Inspect;
    else if (mode == "--exercise-disposable-key") action = Mode::Exercise;
    else if (mode == "--read-disposable-inlinecrypt") action = Mode::ReadInlinecrypt;
    else if (mode == "--read-disposable-inlinecrypt-record") action = Mode::ReadInlinecryptRecord;
    else if (mode == "--create-disposable-key-record") action = Mode::CreateRecord;
    else if (mode == "--prepare-disposable-key-record") action = Mode::PrepareRecord;
    else if (mode == "--remove-disposable-key-record") action = Mode::RemoveRecord;
    else return 2;
    const char* phase = "descriptor-baseline";
    try {
        const auto initial = descriptor_count();
        auto [report, status] = probe(action, pin, rescue, phase);
        report["mode"] = std::string(mode);
        phase = "owned-handle-release";
        if (descriptor_count() != initial) reject();
        struct rusage usage{};
        phase = "resource-report";
        if (getrusage(RUSAGE_SELF, &usage)) reject();
        report["owned_handles_released"] = true;
        report["peak_rss_kib"] = usage.ru_maxrss;
        std::cout << report.dump() << '\n';
        return status;
    } catch (const std::system_error& error) {
        std::cerr << "UKE_HWKM_PROBE_REJECTED stage=" << phase << " errno=" << error.code().value() << '\n'; return 1;
    } catch (const std::exception&) {
        std::cerr << "UKE_HWKM_PROBE_REJECTED stage=" << phase << '\n'; return 1;
    }
}
