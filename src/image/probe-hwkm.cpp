// SPDX-License-Identifier: MIT
// Disposable diagnostic only. A private test record is never a volume key
// or authorization for production key release, mapping or boot policy.
#include "hwkm-wrapped-key.hpp"
#include "hwkm-disposable-record.hpp"
#include "protected-physical-cohort.hpp"
#include <nlohmann/json.hpp>
#include <linux/fs.h>
#include <linux/magic.h>
#include <linux/openat2.h>
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
int beneath(int parent, const std::string& name) {
    struct open_how how{};
    how.flags = O_RDONLY | O_CLOEXEC;
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
enum class Mode { Inspect, Exercise, CreateRecord, PrepareRecord, RemoveRecord };
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
std::pair<nlohmann::json, int> probe(Mode mode, const char*& phase) {
    phase = "physical-owner-open";
    auto devices = open_physical_boot_devices();
    const auto& part = devices.partitions()[static_cast<size_t>(PhysicalRole::Userdata)];
    Fd sys(open("/sys", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    struct statfs fs{};
    if (fstatfs(sys.fd, &fs) || fs.f_type != SYSFS_MAGIC) reject();
    phase = "capabilities-before";
    const auto before = capabilities(sys.fd, part);
    const bool exercise = mode == Mode::Exercise;
    const bool key_operation = exercise || mode == Mode::CreateRecord || mode == Mode::PrepareRecord;
    auto report = nlohmann::json{{"schema_version", 1}, {"physical_ufs_topology_verified", true},
        {"hardware_wrapped_keys_advertised", before.wrapped}, {"raw_keys_advertised", before.raw},
        {"aes_256_xts_4096_advertised", before.xts_4k}, {"num_keyslots", before.slots},
        {"exercise_requested", exercise}, {"key_ioctl_attempts", 0},
        {"disposable_hardware_key_generated", false}, {"prepared_twice", false},
        {"altered_blob_refused", false}, {"key_persisted", false}, {"volume_or_mapping_written", false},
        {"disposable_record_written", false}, {"disposable_record_removed", false},
        {"prepared_from_persistent_record", false},
        {"module_parameter_changed", false}, {"cold_boot_reuse_proved", false},
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
        Fd block(beneath(dev.fd, part.name));
        struct stat st{};
        uint64_t size = 0, sequence = 0;
        int logical = 0;
        if (fstat(block.fd, &st) || !S_ISBLK(st.st_mode) || st.st_rdev != part.device_number ||
            ioctl(block.fd, BLKGETSIZE64, &size) || size != part.capacity_bytes ||
            ioctl(block.fd, BLKGETDISKSEQ, &sequence) || sequence != part.disk_sequence ||
            ioctl(block.fd, BLKSSZGET, &logical) || logical != 4096) reject();
        phase = "physical-owner-before-key";
        devices.revalidate();
        if (!exercise) {
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
    if (argc != 2) return 2;
    const std::string_view mode(argv[1]);
    Mode action;
    if (mode == "--inspect") action = Mode::Inspect;
    else if (mode == "--exercise-disposable-key") action = Mode::Exercise;
    else if (mode == "--create-disposable-key-record") action = Mode::CreateRecord;
    else if (mode == "--prepare-disposable-key-record") action = Mode::PrepareRecord;
    else if (mode == "--remove-disposable-key-record") action = Mode::RemoveRecord;
    else return 2;
    const char* phase = "descriptor-baseline";
    try {
        const auto initial = descriptor_count();
        auto [report, status] = probe(action, phase);
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
