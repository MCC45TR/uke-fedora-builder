// SPDX-License-Identifier: MIT
#include "hwkm-inlinecrypt-read.hpp"

#include <array>
#include <cerrno>
#include <chrono>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <linux/dm-ioctl.h>
#include <linux/fs.h>
#include <linux/keyctl.h>
#include <openssl/sha.h>
#include <stdexcept>
#include <string>
#include <system_error>
#include <sys/ioctl.h>
#include <sys/random.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <thread>
#include <unistd.h>
#include <utility>

namespace uke::protected_boot::hwkm {
namespace {
constexpr size_t block_bytes = 4096;
constexpr unsigned sector_count = block_bytes / 512;
[[noreturn]] void reject() { throw std::runtime_error("Inlinecrypt probe rejected"); }

struct Fd {
    int value;
    explicit Fd(int value) : value(value) { if (value < 0) reject(); }
    ~Fd() { close(value); }
    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;
};

std::string identifier() {
    std::array<unsigned char, 16> nonce{};
    if (getrandom(nonce.data(), nonce.size(), 0) != static_cast<ssize_t>(nonce.size())) reject();
    std::string name = "uke-hwkm-";
    constexpr char hex[] = "0123456789abcdef";
    for (const auto byte : nonce) {
        name += hex[byte >> 4];
        name += hex[byte & 15];
    }
    return name;
}

class LogonKey {
    long serial_;
public:
    LogonKey(const std::string& description, const WrappedKey& key) {
        const auto bytes = key.bytes();
        serial_ = syscall(SYS_add_key, "logon", description.c_str(), bytes.data(), bytes.size(), KEY_SPEC_PROCESS_KEYRING);
        if (serial_ <= 0) reject();
    }
    ~LogonKey() { (void)remove(); }
    bool remove() {
        if (serial_ <= 0) return true;
        const auto revoked = syscall(SYS_keyctl, KEYCTL_REVOKE, serial_);
        const auto unlinked = syscall(SYS_keyctl, KEYCTL_UNLINK, serial_, KEY_SPEC_PROCESS_KEYRING);
        if (unlinked == 0) serial_ = 0;
        return revoked == 0 && unlinked == 0;
    }
    LogonKey(const LogonKey&) = delete;
    LogonKey& operator=(const LogonKey&) = delete;
};

struct DmRequest {
    dm_ioctl header{};
    dm_target_spec target{};
    std::array<char, 256> parameters{};
    DmRequest(const std::string& uuid) {
        header.version[0] = DM_VERSION_MAJOR;
        header.data_size = sizeof(*this);
        header.data_start = sizeof(header);
        std::memcpy(header.uuid, uuid.c_str(), uuid.size() + 1);
    }
};
static_assert(offsetof(DmRequest, target) == sizeof(dm_ioctl));
static_assert(offsetof(DmRequest, parameters) == sizeof(dm_ioctl) + sizeof(dm_target_spec));

class InlinecryptTarget {
    Fd control_{open("/dev/mapper/control", O_RDWR | O_CLOEXEC | O_NOFOLLOW)};
    const std::string uuid_;
    bool created_ = false;
public:
    explicit InlinecryptTarget(const std::string& name) : uuid_("UKE-HWKM-PROBE-" + name) {
        DmRequest request(uuid_);
        std::memcpy(request.header.name, name.c_str(), name.size() + 1);
        if (ioctl(control_.value, DM_DEV_CREATE, &request.header) < 0) reject();
        created_ = true;
    }
    ~InlinecryptTarget() { (void)remove(); }
    InlinecryptTarget(const InlinecryptTarget&) = delete;
    InlinecryptTarget& operator=(const InlinecryptTarget&) = delete;
    void load(dev_t backing, const std::string& description, off_t offset, bool read_only) {
        DmRequest request(uuid_);
        request.header.flags = read_only ? DM_READONLY_FLAG : 0;
        request.header.target_count = 1;
        request.target.length = sector_count;
        std::memcpy(request.target.target_type, "inlinecrypt", sizeof("inlinecrypt"));
        // A one-unit mapping starting at DUN zero gives dm-inlinecrypt a
        // zero-byte DUN width. Start at DUN one without moving the backing read.
        const int length = std::snprintf(request.parameters.data(), request.parameters.size(),
            "aes-xts-plain64 :%zu:logon:%s %u %u:%u %lld 3 keytype:hw-wrapped sector_size:4096 iv_large_sectors",
            wrapped_key_bytes, description.c_str(), sector_count, major(backing), minor(backing),
            static_cast<long long>(offset / 512));
        if (length < 0 || static_cast<size_t>(length) >= request.parameters.size()) reject();
        request.target.next = (sizeof(dm_target_spec) + static_cast<size_t>(length) + 1 + 7) & ~size_t{7};
        if (ioctl(control_.value, DM_TABLE_LOAD, &request.header) < 0)
            throw std::system_error(errno, std::generic_category(), "Load inlinecrypt target");
    }
    dev_t activate(bool read_only) {
        DmRequest request(uuid_);
        if (ioctl(control_.value, DM_DEV_SUSPEND, &request.header) < 0) reject();
        DmRequest status(uuid_);
        if (ioctl(control_.value, DM_DEV_STATUS, &status.header) < 0 ||
            static_cast<bool>(status.header.flags & DM_READONLY_FLAG) != read_only ||
            !(status.header.flags & DM_ACTIVE_PRESENT_FLAG) ||
            (status.header.flags & DM_SUSPEND_FLAG) || status.header.target_count != 1 || !status.header.dev) reject();
        return static_cast<dev_t>(status.header.dev);
    }
    bool remove() {
        if (!created_) return true;
        DmRequest request(uuid_);
        if (ioctl(control_.value, DM_DEV_REMOVE, &request.header) < 0) return false;
        created_ = false;
        return true;
    }
};

dev_t activate_with_key(InlinecryptTarget& target, dev_t backing, const std::string& description,
                        const WrappedKey& key, off_t offset, bool read_only, const char*& phase) {
    {
        phase = "inlinecrypt-logon-key";
        LogonKey logon(description, key);
        phase = "inlinecrypt-load";
        target.load(backing, description, offset, read_only);
        phase = "inlinecrypt-remove-logon-key";
        if (!logon.remove()) reject();
    }
    phase = "inlinecrypt-activate";
    return target.activate(read_only);
}

int open_target(dev_t device, int access = O_RDONLY) {
    const std::string path = "/dev/dm-" + std::to_string(minor(device));
    for (unsigned attempt = 0; attempt < 20; ++attempt) {
        const int fd = open(path.c_str(), access | O_CLOEXEC | O_NOFOLLOW, 0);
        if (fd >= 0) return fd;
        if (errno != ENOENT) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(25));
    }
    reject();
}

std::string hex_digest(const std::array<unsigned char, SHA256_DIGEST_LENGTH>& digest) {
    constexpr char hex[] = "0123456789abcdef";
    std::string result;
    result.reserve(digest.size() * 2);
    for (const auto byte : digest) {
        result += hex[byte >> 4];
        result += hex[byte & 15];
    }
    return result;
}

void validate_target(int fd, dev_t device, bool read_only) {
    struct stat st{};
    int readonly = -1;
    uint64_t size = 0;
    if (fstat(fd, &st) || !S_ISBLK(st.st_mode) || st.st_rdev != device ||
        ioctl(fd, BLKROGET, &readonly) || readonly != static_cast<int>(read_only) ||
        ioctl(fd, BLKGETSIZE64, &size) || size != block_bytes) reject();
}
}

InlinecryptReadResult exercise_inlinecrypt_read(int block_fd, WrappedKey&& input, const char*& phase) {
    phase = "inlinecrypt-input";
    WrappedKey key(std::move(input));
    struct stat backing{};
    const int flags = fcntl(block_fd, F_GETFL);
    if (key.lifetime() != Lifetime::PerBoot || flags < 0 || (flags & (O_ACCMODE | O_PATH)) != O_RDONLY ||
        fstat(block_fd, &backing) || !S_ISBLK(backing.st_mode)) reject();

    const auto name = identifier();
    const auto description = "uke-hwkm:" + name;
    phase = "inlinecrypt-create";
    InlinecryptTarget target(name);
    const auto device = activate_with_key(target, backing.st_rdev, description, key, 0, true, phase);
    std::array<unsigned char, SHA256_DIGEST_LENGTH> raw_digest{}, mapped_digest{};
    {
        phase = "inlinecrypt-read";
        Fd mapped(open_target(device));
        validate_target(mapped.value, device, true);
        std::array<unsigned char, block_bytes> raw{}, transformed{};
        const auto raw_read = pread(block_fd, raw.data(), raw.size(), 0);
        const auto hardware_read = pread(mapped.value, transformed.data(), transformed.size(), 0);
        const bool compared = raw_read == static_cast<ssize_t>(raw.size()) &&
            hardware_read == static_cast<ssize_t>(transformed.size()) && raw != transformed &&
            SHA256(raw.data(), raw.size(), raw_digest.data()) &&
            SHA256(transformed.data(), transformed.size(), mapped_digest.data());
        explicit_bzero(raw.data(), raw.size());
        explicit_bzero(transformed.data(), transformed.size());
        if (!compared) reject();
    }
    phase = "inlinecrypt-remove-mapping";
    if (!target.remove()) reject();
    return {hex_digest(raw_digest), hex_digest(mapped_digest)};
}

InlinecryptReadResult exercise_inlinecrypt_rescue_block(int block_fd, WrappedKey&& input,
        std::string_view expected_backing, bool write, const char*& phase) {
    phase = "rescue-raw-before";
    WrappedKey key(std::move(input));
    struct stat backing{};
    const int flags = fcntl(block_fd, F_GETFL);
    if (key.lifetime() != Lifetime::PerBoot || flags < 0 ||
        (flags & (O_ACCMODE | O_PATH | O_DIRECT)) != (O_RDONLY | O_DIRECT) ||
        fstat(block_fd, &backing) || !S_ISBLK(backing.st_mode)) reject();

    alignas(block_bytes) std::array<unsigned char, block_bytes> raw_before{}, raw_after{}, sample{}, readback{};
    std::array<unsigned char, SHA256_DIGEST_LENGTH> raw_digest{}, mapped_digest{};
    if (pread(block_fd, raw_before.data(), raw_before.size(), rescue_block_offset) !=
            static_cast<ssize_t>(block_bytes) ||
        !SHA256(raw_before.data(), raw_before.size(), raw_digest.data()) ||
        hex_digest(raw_digest) != expected_backing) reject();
    if (write && raw_before != raw_after) reject();  // Initial writes require the known zero block.
    sample.fill(0x5a);
    constexpr char marker[] = "Uke disposable Fedora Live Rescue HWKM block";
    std::memcpy(sample.data(), marker, sizeof(marker) - 1);

    const auto name = identifier();
    phase = "inlinecrypt-create";
    InlinecryptTarget target(name);
    const auto device = activate_with_key(target, backing.st_rdev, "uke-hwkm:" + name, key,
                                           rescue_block_offset, !write, phase);
    {
        phase = "rescue-mapper-geometry";
        Fd mapped(open_target(device, (write ? O_RDWR : O_RDONLY) | O_DIRECT));
        validate_target(mapped.value, device, !write);
        if (write) {
            phase = "rescue-mapped-write";
            if (pwrite(mapped.value, sample.data(), sample.size(), 0) != static_cast<ssize_t>(block_bytes) ||
                fsync(mapped.value) != 0) reject();
        }
        phase = "rescue-mapped-read";
        if (pread(mapped.value, readback.data(), readback.size(), 0) != static_cast<ssize_t>(block_bytes) ||
            readback != sample || !SHA256(readback.data(), readback.size(), mapped_digest.data())) reject();
    }
    phase = "inlinecrypt-remove-mapping";
    if (!target.remove()) reject();
    phase = "rescue-raw-after";
    if (pread(block_fd, raw_after.data(), raw_after.size(), rescue_block_offset) !=
            static_cast<ssize_t>(block_bytes) || raw_after == sample ||
        (write ? raw_after == raw_before : raw_after != raw_before) ||
        !SHA256(raw_after.data(), raw_after.size(), raw_digest.data())) reject();
    return {hex_digest(raw_digest), hex_digest(mapped_digest)};
}
}
