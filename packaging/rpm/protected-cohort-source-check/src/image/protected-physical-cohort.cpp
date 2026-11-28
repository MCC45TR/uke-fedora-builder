// SPDX-License-Identifier: MIT
#include "protected-physical-cohort.hpp"
#include <systemd/sd-device.h>
#include <linux/fs.h>
#include <linux/magic.h>
#include <linux/openat2.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <fcntl.h>
#include <unistd.h>
#include <algorithm>
#include <array>
#include <cerrno>
#include <charconv>
#include <chrono>
#include <cstring>
#include <map>
#include <set>
#include <stdexcept>
#include <string_view>
#include <type_traits>

namespace uke::protected_boot {
namespace {
constexpr std::array<std::string_view, 10> labels{"boot_a", "boot_b", "vendor_boot_a", "vendor_boot_b",
    "dtbo_a", "dtbo_b", "vbmeta_a", "vbmeta_b", "super", "userdata"};
constexpr std::string_view controller = "/sys/devices/platform/soc/1d84000.ufshc";
constexpr uint64_t maximum_capacity = 2199023255552;
using Clock = std::chrono::steady_clock;
[[noreturn]] void refuse() { throw std::runtime_error("Physical cohort rejected"); }
void budget(const Clock::time_point& until) { if (Clock::now() >= until) refuse(); }
size_t role(std::string_view label) {
    for (size_t i = 0; i < labels.size(); ++i) if (label == labels[i]) return i;
    refuse();
}
bool disk_name(std::string_view name) {
    return name.size() >= 3 && name.size() <= 12 && name.starts_with("sd") &&
        name.substr(2).find_first_not_of("abcdefghijklmnopqrstuvwxyz") == std::string_view::npos;
}
bool real_device_path(std::string_view path) {
    return path.starts_with("/sys/devices/") && path.size() <= 512 && !path.ends_with('/') &&
        path.find("//") == path.npos && path.find("/./") == path.npos && path.find("/../") == path.npos &&
        !path.ends_with("/.") && !path.ends_with("/..") && path.find_first_of("\r\n") == path.npos;
}
uint64_t number(std::string_view text, uint64_t maximum) {
    if (!text.empty() && text.back() == '\n') text.remove_suffix(1);
    if (text.empty() || text.size() > 20 || (text.size() > 1 && text.front() == '0') ||
        text.find_first_not_of("0123456789") != std::string_view::npos) refuse();
    uint64_t out = 0;
    const auto result = std::from_chars(text.data(), text.data() + text.size(), out);
    if (result.ec != std::errc{} || result.ptr != text.data() + text.size() || out > maximum) refuse();
    return out;
}
struct Fd {
    int value = -1;
    Fd() = default;
    explicit Fd(int input) : value(input) {
        if (value < 3) { if (value >= 0) close(value); value = -1; refuse(); }
    }
    ~Fd() { if (value >= 0) close(value); }
    Fd(Fd&& other) noexcept : value(std::exchange(other.value, -1)) {}
    Fd& operator=(Fd&& other) noexcept {
        if (this != &other) { if (value >= 0) close(value); value = std::exchange(other.value, -1); }
        return *this;
    }
    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;
};
Fd beneath(int parent, std::string_view path, bool directory = false) {
    const std::string name(path);
    struct open_how how{};
    how.flags = O_RDONLY | O_CLOEXEC | (directory ? O_DIRECTORY : 0);
    how.resolve = RESOLVE_BENEATH | RESOLVE_NO_SYMLINKS | RESOLVE_NO_MAGICLINKS;
    return Fd(static_cast<int>(syscall(SYS_openat2, parent, name.c_str(), &how, sizeof(how))));
}
void sysfs(int fd) {
    struct statfs filesystem{};
    if (fstatfs(fd, &filesystem) || filesystem.f_type != SYSFS_MAGIC) refuse();
}
std::string attribute(int parent, std::string_view name, size_t limit, const Clock::time_point& until) {
    auto fd = beneath(parent, name);
    sysfs(fd.value);
    std::string out;
    std::array<char, 512> buffer{};
    for (;;) {
        budget(until);
        const auto wanted = std::min(buffer.size(), limit + 1 - out.size());
        const auto count = read(fd.value, buffer.data(), wanted);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) refuse();
        if (!count) return out;
        out.append(buffer.data(), static_cast<size_t>(count));
        if (out.size() > limit) refuse();
    }
}
using Fields = std::map<std::string, std::string>;
Fields event(std::string_view text) {
    if (text.empty() || text.size() > 4096 || text.back() != '\n' || text.find('\0') != text.npos ||
        text.find('\r') != text.npos) refuse();
    Fields selected;
    std::set<std::string_view> seen;
    while (!text.empty()) {
        const auto end = text.find('\n');
        const auto line = text.substr(0, end);
        const auto equal = line.find('=');
        if (end == text.npos || equal == text.npos || equal == 0 || equal > 32) refuse();
        const auto key = line.substr(0, equal);
        if (key.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_") != key.npos ||
            !seen.insert(key).second || seen.size() > 64) refuse();
        if (key == "MAJOR" || key == "MINOR" || key == "DEVNAME" || key == "DEVTYPE" ||
            key == "PARTN" || key == "PARTNAME") selected.emplace(key, line.substr(equal + 1));
        text.remove_prefix(end + 1);
    }
    return selected;
}
std::string device_string(sd_device* device, int (*getter)(sd_device*, const char**), size_t limit = 512) {
    const char* text = nullptr;
    if (getter(device, &text) < 0 || !text || strnlen(text, limit + 1) > limit) refuse();
    return text;
}
struct DeviceUnref { void operator()(sd_device* value) const noexcept { sd_device_unref(value); } };
struct EnumeratorUnref { void operator()(sd_device_enumerator* value) const noexcept { sd_device_enumerator_unref(value); } };
using Device = std::unique_ptr<sd_device, DeviceUnref>;
using Enumerator = std::unique_ptr<sd_device_enumerator, EnumeratorUnref>;
Fd device_directory(int root, std::string_view path) {
    if (!path.starts_with("/sys/devices/")) refuse();
    auto out = beneath(root, path.substr(5), true);
    sysfs(out.value);
    return out;
}
PhysicalPartitionFacts observe(sd_device* device, const Fields& values, int root, const Clock::time_point& until) {
    PhysicalPartitionFacts out;
    auto field = [&values](const std::string& key) -> const std::string& {
        const auto value = values.find(key);
        if (value == values.end()) refuse();
        return value->second;
    };
    out.label = field("PARTNAME");
    out.name = field("DEVNAME");
    out.partition = number(field("PARTN"), 65535);
    out.syspath = device_string(device, sd_device_get_syspath);
    if (field("DEVTYPE") != "partition" || device_string(device, sd_device_get_devtype) != "partition" ||
        device_string(device, sd_device_get_subsystem) != "block" ||
        device_string(device, sd_device_get_sysname) != out.name) refuse();
    dev_t dev = 0;
    if (sd_device_get_devnum(device, &dev) < 0 ||
        major(dev) != number(field("MAJOR"), 4095) || minor(dev) != number(field("MINOR"), 1048575)) refuse();
    out.device_number = dev;
    sd_device* disk = nullptr;
    if (sd_device_get_parent(device, &disk) < 0 || !disk ||
        device_string(disk, sd_device_get_subsystem) != "block" ||
        device_string(disk, sd_device_get_devtype) != "disk") refuse();
    out.disk_name = device_string(disk, sd_device_get_sysname);
    out.disk_syspath = device_string(disk, sd_device_get_syspath);
    if (sd_device_get_devnum(disk, &dev) < 0) refuse();
    out.disk_number = dev;
    sd_device* ancestor = disk;
    for (size_t depth = 0;; ++depth) {
        if (depth > 32) refuse();
        if (device_string(ancestor, sd_device_get_syspath) == controller) break;
        sd_device* parent = nullptr;
        if (sd_device_get_parent(ancestor, &parent) < 0 || !parent) refuse();
        ancestor = parent;
    }
    if (device_string(ancestor, sd_device_get_subsystem) != "platform") refuse();
    out.controller = device_string(ancestor, sd_device_get_syspath);
    out.driver = device_string(ancestor, sd_device_get_driver);
    auto node = device_directory(root, out.syspath);
    auto parent = device_directory(root, out.disk_syspath);
    const auto dev_text = std::to_string(major(static_cast<dev_t>(out.device_number))) + ":" +
        std::to_string(minor(static_cast<dev_t>(out.device_number))) + "\n";
    const auto disk_text = std::to_string(major(dev)) + ":" + std::to_string(minor(dev)) + "\n";
    if (attribute(node.value, "dev", 32, until) != dev_text ||
        attribute(parent.value, "dev", 32, until) != disk_text ||
        number(attribute(node.value, "partition", 16, until), 65535) != out.partition) refuse();
    out.capacity_bytes = number(attribute(node.value, "size", 32, until), maximum_capacity / 512) * 512;
    out.start_bytes = number(attribute(node.value, "start", 32, until), maximum_capacity / 512) * 512;
    out.disk_capacity_bytes = number(attribute(parent.value, "size", 32, until), maximum_capacity / 512) * 512;
    out.disk_sequence = number(attribute(parent.value, "diskseq", 32, until), UINT64_MAX);
    out.logical_bytes = number(attribute(parent.value, "queue/logical_block_size", 16, until), 65536);
    return out;
}
std::array<PhysicalPartitionFacts, 10> catalogue(int root, const Clock::time_point& until) {
    sd_device_enumerator* raw = nullptr;
    if (sd_device_enumerator_new(&raw) < 0 || !raw) refuse();
    Enumerator enumerator(raw);
    if (sd_device_enumerator_add_match_subsystem(raw, "block", 1) < 0 ||
        sd_device_enumerator_allow_uninitialized(raw) < 0) refuse();
    std::vector<PhysicalPartitionFacts> found;
    size_t count = 0;
    for (auto* device = sd_device_enumerator_get_device_first(raw); device;
         device = sd_device_enumerator_get_device_next(raw)) {
        budget(until);
        if (++count > 1024) refuse();
        auto node = device_directory(root, device_string(device, sd_device_get_syspath));
        const auto values = event(attribute(node.value, "uevent", 4096, until));
        const auto label = values.find("PARTNAME");
        if (label == values.end() || std::find(labels.begin(), labels.end(), label->second) == labels.end()) continue;
        if (found.size() == 10) refuse();
        found.push_back(observe(device, values, root, until));
    }
    return detail::validate_physical_facts(found);
}
bool same_node(const struct stat& x, const struct stat& y) {
    return x.st_dev == y.st_dev && x.st_ino == y.st_ino && x.st_rdev == y.st_rdev && x.st_mode == y.st_mode &&
        x.st_ctim.tv_sec == y.st_ctim.tv_sec && x.st_ctim.tv_nsec == y.st_ctim.tv_nsec;
}
void block_fd(int fd, const PhysicalPartitionFacts& expected) {
    struct stat state{};
    unsigned long long capacity = 0, sequence = 0;
    int logical = 0;
    const auto flags = fcntl(fd, F_GETFL);
    if (fd < 3 || flags < 0 || (flags & O_ACCMODE) != O_RDONLY || (flags & (O_PATH | O_DIRECT)) ||
        fstat(fd, &state) || !S_ISBLK(state.st_mode) || state.st_rdev != expected.device_number ||
        ioctl(fd, BLKGETSIZE64, &capacity) || capacity != expected.capacity_bytes ||
        ioctl(fd, BLKSSZGET, &logical) || logical != 4096 ||
        ioctl(fd, BLKGETDISKSEQ, &sequence) || sequence != expected.disk_sequence) refuse();
}
}

void detail::validate_uke_compatible(std::span<const unsigned char> bytes) {
    if (bytes.empty() || bytes.size() > 1024 || bytes.back()) refuse();
    const std::string_view text(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    std::set<std::string_view> seen;
    size_t pos = 0;
    while (pos < text.size()) {
        const auto end = text.find('\0', pos);
        const auto value = text.substr(pos, end - pos);
        if (value.empty() || value.size() > 128 || seen.size() == 16 || !seen.insert(value).second) refuse();
        pos = end + 1;
    }
    if (!seen.contains("xiaomi,uke") || !seen.contains("qcom,sm7675")) refuse();
}

std::array<PhysicalPartitionFacts, 10> detail::validate_physical_facts(std::span<const PhysicalPartitionFacts> input) {
    if (input.size() != 10) refuse();
    std::array<PhysicalPartitionFacts, 10> out;
    std::array<bool, 10> seen{};
    for (const auto& value : input) {
        const auto index = role(value.label);
        if (seen[index] || !disk_name(value.disk_name) || !value.partition || value.partition > 65535 ||
            value.name != value.disk_name + std::to_string(value.partition) ||
            value.controller != controller || value.driver != "ufshcd-qcom" ||
            !real_device_path(value.disk_syspath) || !real_device_path(value.syspath) ||
            !value.disk_syspath.starts_with(std::string(controller) + "/") ||
            !value.disk_syspath.ends_with("/block/" + value.disk_name) ||
            value.syspath != value.disk_syspath + "/" + value.name ||
            !value.device_number || !value.disk_number || value.device_number == value.disk_number ||
            !value.disk_sequence || value.logical_bytes != 4096 || !value.capacity_bytes ||
            value.capacity_bytes > maximum_capacity || value.capacity_bytes % 4096 ||
            !value.disk_capacity_bytes || value.disk_capacity_bytes > maximum_capacity || value.disk_capacity_bytes % 4096 ||
            !value.start_bytes || value.start_bytes % 4096 || value.start_bytes >= value.disk_capacity_bytes ||
            value.capacity_bytes > value.disk_capacity_bytes - value.start_bytes) refuse();
        if (index < 6 && value.capacity_bytes > 536870912) refuse();
        if ((index == 6 || index == 7) && (value.capacity_bytes < 65536 || value.capacity_bytes > 1048576)) refuse();
        seen[index] = true;
        out[index] = value;
    }
    for (size_t i = 0; i < out.size(); ++i) for (size_t j = 0; j < i; ++j) {
        const auto& a = out[i]; const auto& b = out[j];
        if (a.device_number == b.device_number || a.device_number == b.disk_number || b.device_number == a.disk_number) refuse();
        if (a.disk_number == b.disk_number) {
            if (a.disk_syspath != b.disk_syspath || a.disk_sequence != b.disk_sequence ||
                a.disk_capacity_bytes != b.disk_capacity_bytes ||
                !(a.start_bytes + a.capacity_bytes <= b.start_bytes || b.start_bytes + b.capacity_bytes <= a.start_bytes)) refuse();
        } else if (a.disk_syspath == b.disk_syspath || a.disk_sequence == b.disk_sequence) refuse();
    }
    return out;
}

struct PhysicalCohortState {
    Fd sys, dev;
    std::array<PhysicalPartitionFacts, 10> facts;
    std::array<Fd, 10> nodes, blocks;
    std::array<struct stat, 10> node_states{}, block_states{};
};
PhysicalBootDevices::PhysicalBootDevices(std::unique_ptr<PhysicalCohortState> state) : state_(std::move(state)) {}
PhysicalBootDevices::~PhysicalBootDevices() = default;
PhysicalBootDevices::PhysicalBootDevices(PhysicalBootDevices&&) noexcept = default;
PhysicalBootDevices& PhysicalBootDevices::operator=(PhysicalBootDevices&&) noexcept = default;
const std::array<PhysicalPartitionFacts, 10>& PhysicalBootDevices::partitions() const { if (!state_) refuse(); return state_->facts; }
ObservedBootGeometry PhysicalBootDevices::geometry() const {
    const auto& p = partitions();
    return {p[8].capacity_bytes, p[9].capacity_bytes, 4096,
        {p[0].capacity_bytes, p[1].capacity_bytes}, {p[2].capacity_bytes, p[3].capacity_bytes},
        {p[4].capacity_bytes, p[5].capacity_bytes}};
}
void PhysicalBootDevices::revalidate() const {
    if (!state_) refuse();
    const auto until = Clock::now() + std::chrono::seconds(30);
    sysfs(state_->sys.value);
    const auto compatible = attribute(state_->sys.value, "firmware/devicetree/base/compatible", 1024, until);
    detail::validate_uke_compatible({reinterpret_cast<const unsigned char*>(compatible.data()), compatible.size()});
    if (catalogue(state_->sys.value, until) != state_->facts) refuse();
    for (size_t i = 0; i < 10; ++i) {
        block_fd(state_->blocks[i].value, state_->facts[i]);
        auto fresh = device_directory(state_->sys.value, state_->facts[i].syspath);
        struct stat node{}, current{}, block{};
        if (fstat(fresh.value, &node) || fstat(state_->nodes[i].value, &current) ||
            !same_node(node, current) || !same_node(current, state_->node_states[i]) ||
            fstat(state_->blocks[i].value, &block) || !same_node(block, state_->block_states[i])) refuse();
    }
    budget(until);
}
PhysicalBootDevices open_physical_boot_devices() {
    static_assert(!std::is_default_constructible_v<PhysicalBootDevices>);
    static_assert(!std::is_copy_constructible_v<PhysicalBootDevices>);
    if (geteuid() != 0) refuse();
    auto state = std::make_unique<PhysicalCohortState>();
    state->sys = Fd(open("/sys", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    state->dev = Fd(open("/dev", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    sysfs(state->sys.value);
    const auto until = Clock::now() + std::chrono::seconds(30);
    const auto compatible = attribute(state->sys.value, "firmware/devicetree/base/compatible", 1024, until);
    detail::validate_uke_compatible({reinterpret_cast<const unsigned char*>(compatible.data()), compatible.size()});
    state->facts = catalogue(state->sys.value, until);
    for (size_t i = 0; i < 10; ++i) {
        budget(until);
        state->nodes[i] = device_directory(state->sys.value, state->facts[i].syspath);
        state->blocks[i] = beneath(state->dev.value, state->facts[i].name);
        block_fd(state->blocks[i].value, state->facts[i]);
        if (fstat(state->nodes[i].value, &state->node_states[i]) ||
            fstat(state->blocks[i].value, &state->block_states[i])) refuse();
    }
    PhysicalBootDevices out(std::move(state));
    out.revalidate();
    budget(until);
    return out;
}
InspectedPhysicalBoot::InspectedPhysicalBoot(PhysicalBootDevices devices, VerifiedVbmetaFd metadata,
    VerifiedBootContents contents) : devices_(std::move(devices)), metadata_(std::move(metadata)), contents_(std::move(contents)) {}
InspectedPhysicalBoot inspect_physical_boot(PhysicalBootDevices devices, BootSlot slot,
                                            const VbmetaTrustPins& trusted, const ImmutableKernelContext& expected) {
    if (!devices.state_ || (slot != BootSlot::A && slot != BootSlot::B)) refuse();
    const size_t side = slot == BootSlot::A ? 0 : 1;
    auto& state = *devices.state_;
    devices.revalidate();
    auto metadata = verify_vbmeta_cohort_fd(state.blocks[6 + side].value, state.facts[6 + side].capacity_bytes,
                                           trusted, expected, devices.geometry());
    auto contents = verify_boot_contents_fds(metadata.cohort(),
        {state.blocks[side].value, state.blocks[2 + side].value, state.blocks[4 + side].value}, slot);
    devices.revalidate();
    return {std::move(devices), std::move(metadata), std::move(contents)};
}
}
