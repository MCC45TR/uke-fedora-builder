// SPDX-License-Identifier: MIT
// Interface facts: Qualcomm TPM v4, 19 October 2026 (UID81), and the original
// MINK userspace API. Upstream C/assembly adapters are compiled unchanged;
// original Fedora libqcomtee handles credentials and object marshalling.
#include "qtee-tpm-discovery.hpp"
#include <MinkCom.h>
#include <linux/tee.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <array>
#include <cerrno>
#include <cstdint>
#include <limits>
#include <algorithm>
#include <bit>
#include <cstring>
#include <new>
#include <span>
#include <stdexcept>
#include <string_view>
#include <system_error>

namespace uke::protected_boot::qtee_tpm {
namespace {
constexpr std::uint32_t uid = 81, get_version = 0x1000, get_type = 0x80000;
constexpr std::uint32_t ftpm = 0x6654504d, dtpm = 0x6454504d, none = 0x4e6f6e65;
void require(bool value) { if (!value) throw std::runtime_error("QTEE TPM information rejected"); }
void result(int value) { if (value) throw RemoteRefusal(static_cast<std::uint32_t>(value)); }
struct Fd {
    int value;
    explicit Fd(int fd) : value(fd) {}
    ~Fd() { if (value >= 0) close(value); }
    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;
};
class Ref {
    Object value_ = Object_NULL;
public:
    Ref() = default;
    Ref(const Ref&) = delete;
    Ref& operator=(const Ref&) = delete;
    ~Ref() { (void)release(); }
    Object get() const { return value_; }
    Object* output() { require(Object_isNull(value_)); return &value_; }
    void adopt(Object value) { require(Object_isNull(value_)); value_ = value; }
    void present() const { require(!Object_isNull(value_)); }
    bool release() noexcept {
        if (Object_isNull(value_)) return true;
        const auto old = value_;
        value_ = Object_NULL;
        return Object_release(old) == Object_OK;
    }
};
std::array<unsigned char, 4> le32(std::uint32_t value) {
    return {static_cast<unsigned char>(value), static_cast<unsigned char>(value >> 8),
            static_cast<unsigned char>(value >> 16), static_cast<unsigned char>(value >> 24)};
}
std::uint32_t word(const unsigned char* p) {
    return std::uint32_t(p[0]) | std::uint32_t(p[1]) << 8 | std::uint32_t(p[2]) << 16 | std::uint32_t(p[3]) << 24;
}
void open_object(Object parent, const void* input, size_t size, Ref& child) {
    ObjectArg args[2]{};
    args[0].bi = {input, size};
    args[1].o = Object_NULL;
    const auto status = Object_invoke(parent, 0, args, ObjectCounts_pack(1, 0, 0, 1));
    child.adopt(args[1].o);
    result(status);
    child.present();
    require(args[0].bi.ptr == input && args[0].bi.size == size);
}
void provider(int fd) {
    struct stat actual{}, adapter{};
    if (fstat(fd, &actual) || lstat("/dev/tee0", &adapter))
        throw std::system_error(errno, std::generic_category(), "Inspect QTEE provider");
    const int flags = fcntl(fd, F_GETFL), descriptor = fcntl(fd, F_GETFD);
    require(flags >= 0 && descriptor >= 0 && (flags & O_ACCMODE) == O_RDWR && !(flags & O_PATH) &&
        (descriptor & FD_CLOEXEC) && S_ISCHR(actual.st_mode) && S_ISCHR(adapter.st_mode) &&
        actual.st_uid == 0 && adapter.st_uid == 0 && !(actual.st_mode & 0022) && !(adapter.st_mode & 0022) &&
        actual.st_dev == adapter.st_dev && actual.st_ino == adapter.st_ino && actual.st_rdev == adapter.st_rdev);
    tee_ioctl_version_data version{};
    if (ioctl(fd, TEE_IOC_VERSION, &version))
        throw std::system_error(errno, std::generic_category(), "Read QTEE version");
    require(version.impl_id == TEE_IMPL_ID_QTEE && (version.gen_caps & TEE_GEN_CAP_OBJREF));
}
std::array<unsigned char, 12> query(Object service, std::uint32_t command) {
    require(command == get_version || command == get_type);
    unsigned char locality = 0;
    auto input = le32(command);
    std::array<unsigned char, 12> response{};
    ObjectArg parameters[3]{};
    parameters[0].bi = {&locality, sizeof(locality)};
    parameters[1].bi = {input.data(), input.size()};
    parameters[2].b = {response.data(), response.size()};
    result(Object_invoke(service, 0, parameters, ObjectCounts_pack(2, 1, 0, 0)));
    require(!locality && word(input.data()) == command && parameters[0].bi.ptr == &locality &&
        parameters[0].bi.size == 1 && parameters[1].bi.ptr == input.data() && parameters[1].bi.size == input.size() &&
        parameters[2].b.ptr == response.data() && parameters[2].b.size == response.size());
    return response;
}
}
Information inspect_owned_provider(int provider_fd, const char*& phase) {
    phase = "qtee-provider-admission";
    require(provider_fd >= 3);
    Fd owned(provider_fd);
    provider(provider_fd);
    Ref root, environment, service;
    phase = "qtee-userspace-root";
    result(MinkCom_getRootEnvObject(root.output()));
    root.present();
    phase = "qtee-userspace-credentials";
    // Original adapter: operation 2 with a real libqcomtee credential callback.
    // The kernel-only operation 5 / NULL credential is never requested here.
    result(MinkCom_getClientEnvObject(root.get(), environment.output()));
    environment.present();
    phase = "qtee-tpm-service-open";
    auto service_uid = le32(uid);
    open_object(environment.get(), service_uid.data(), service_uid.size(), service);
    require(word(service_uid.data()) == uid);
    phase = "qtee-tpm-version-query";
    const auto version = query(service.get(), get_version);
    require(!word(version.data()) && word(version.data() + 4) == get_version);
    Information info;
    info.major = static_cast<std::uint16_t>(word(version.data() + 8) >> 16);
    info.minor = static_cast<std::uint16_t>(word(version.data() + 8));
    phase = "qtee-tpm-type-query";
    const auto type = query(service.get(), get_type);
    require(word(type.data()) == get_type && !word(type.data() + 4));
    switch (word(type.data() + 8)) {
    case ftpm: info.kind = Kind::Firmware; break;
    case dtpm: info.kind = Kind::Discrete; break;
    case none: info.kind = Kind::None; break;
    default: throw std::runtime_error("Unknown QTEE TPM type");
    }
    phase = "qtee-object-release";
    const bool a = service.release(), b = environment.release(), c = root.release();
    require(a && b && c);
    phase = "qtee-provider-after";
    provider(provider_fd);
    info.information_queries = 2;
    return info;
}

namespace {
class KeymasterSession {
    Ref root, environment, client, opener;
public:
    Ref service;
    explicit KeymasterSession(const char*& phase);
    void close(const char*& phase);
};

KeymasterSession::KeymasterSession(const char*& phase) {
    phase = "qtee-userspace-root";
    result(MinkCom_getRootEnvObject(root.output()));
    root.present();
    phase = "qtee-userspace-credentials";
    result(MinkCom_getClientEnvObject(root.get(), environment.output()));
    environment.present();

    // SmciInvokeUtils.h and KeymasterClient.c at aef4e860 describe the
    // named object, its opener and the version request. No loader is used.
    constexpr std::uint32_t app_client_uid = 0x97, hal_uid = 150;
    phase = "qtee-keymaster-client-open";
    auto client_uid = le32(app_client_uid);
    open_object(environment.get(), client_uid.data(), client_uid.size(), client);
    require(word(client_uid.data()) == app_client_uid);
    phase = "qtee-keymaster-name-lookup";
    char name[] = "keymaster64";
    open_object(client.get(), name, sizeof(name) - 1, opener);
    require(std::string_view(name, sizeof(name) - 1) == "keymaster64" && !name[sizeof(name) - 1]);
    phase = "qtee-keymaster-service-open";
    auto service_uid = le32(hal_uid);
    open_object(opener.get(), service_uid.data(), service_uid.size(), service);
    require(word(service_uid.data()) == hal_uid);
}

KeymasterVersion keymaster_version(Object service, const char*& phase) {
    constexpr std::uint32_t version_command = 0x200;
    phase = "qtee-keymaster-version-query";
    auto input = le32(version_command);
    std::array<unsigned char, 20> response;
    response.fill(0xff);
    ObjectArg args[2]{};
    args[0].bi = {input.data(), input.size()};
    args[1].b = {response.data(), response.size()};
    result(Object_invoke(service, 0, args, ObjectCounts_pack(1, 1, 0, 0)));

    phase = "qtee-keymaster-version-response";
    constexpr auto sentinel = std::numeric_limits<std::uint32_t>::max();
    require(args[0].bi.ptr == input.data() && args[0].bi.size == input.size() &&
        word(input.data()) == version_command && args[1].b.ptr == response.data() &&
        args[1].b.size == response.size() && word(response.data()) != sentinel);
    result(static_cast<int>(word(response.data())));
    const KeymasterVersion version{word(response.data() + 4), word(response.data() + 8),
        word(response.data() + 12), word(response.data() + 16)};
    require(version.hal_major >= 2 && version.hal_major != sentinel && version.hal_minor != sentinel &&
        version.app_major != sentinel && version.app_minor != sentinel);
    return version;
}

void KeymasterSession::close(const char*& phase) {
    phase = "qtee-object-release";
    const bool a = service.release(), b = opener.release(), c = client.release(),
        d = environment.release(), e = root.release();
    require(a && b && c && d && e);
}

// Command IDs, CBOR map labels and header were recovered from the fitted
// Global 304 keymaster64 dispatch. The key description follows AOSP vold.
constexpr std::uint32_t generate_storage = 0x3108, convert_storage = 0x311d;
constexpr std::uint32_t tag_algorithm = 0x10000002, tag_size = 0x30000003,
    tag_purpose = 0x20000001, tag_storage = 0x700002d2;
constexpr unsigned count_label = 22, key_blob_label = 23, certificate_count_label = 32,
    ephemeral_label = 36;
constexpr size_t max_blob = 4096, max_ephemeral = 128;

struct StorageBuffers {
    std::array<unsigned char, max_blob + 32> request;
    std::array<unsigned char, 8192> response;
    std::array<unsigned char, max_blob> blob;
};

class LockedBuffers {
    void* memory;
public:
    LockedBuffers() : memory(mmap(nullptr, sizeof(StorageBuffers), PROT_READ | PROT_WRITE,
                                  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0)) {
        if (memory == MAP_FAILED)
            throw std::system_error(errno, std::generic_category(), "Allocate QTEE buffers");
        if (mlock(memory, sizeof(StorageBuffers)) ||
            madvise(memory, sizeof(StorageBuffers), MADV_DONTDUMP) ||
            madvise(memory, sizeof(StorageBuffers), MADV_WIPEONFORK)) {
            const int error = errno;
            munmap(memory, sizeof(StorageBuffers));
            throw std::system_error(error, std::generic_category(), "Protect QTEE buffers");
        }
        new (memory) StorageBuffers{};
    }
    ~LockedBuffers() {
        explicit_bzero(memory, sizeof(StorageBuffers));
        munmap(memory, sizeof(StorageBuffers));
    }
    LockedBuffers(const LockedBuffers&) = delete;
    LockedBuffers& operator=(const LockedBuffers&) = delete;
    StorageBuffers& get() { return *static_cast<StorageBuffers*>(memory); }
};

void encode_cbor(unsigned char*& out, unsigned major, std::uint32_t value) {
    if (value < 24) {
        *out++ = static_cast<unsigned char>((major << 5) | value);
        return;
    }
    const unsigned width = value <= 0xff ? 1 : value <= 0xffff ? 2 : 4;
    *out++ = static_cast<unsigned char>((major << 5) | (width == 1 ? 24 : width == 2 ? 25 : 26));
    for (unsigned i = width; i > 0; --i)
        *out++ = static_cast<unsigned char>(value >> (8 * (i - 1)));
}

size_t storage_request(StorageBuffers& buffers, std::span<const unsigned char> blob) {
    const auto cmd = le32(blob.empty() ? generate_storage : convert_storage);
    auto* out = std::copy(cmd.begin(), cmd.end(), buffers.request.data());
    if (blob.empty()) {
        encode_cbor(out, 5, 6);
        const std::array<std::pair<std::uint32_t, std::uint32_t>, 6> description{{
            {count_label, 5}, {tag_algorithm, 32}, {tag_size, 256},
            {tag_purpose, 0}, {tag_purpose, 1}, {tag_storage, 1},
        }};
        for (const auto& [tag, value] : description) {
            encode_cbor(out, 0, tag);
            encode_cbor(out, 0, value);
        }
    } else {
        require(blob.size() <= max_blob);
        encode_cbor(out, 5, 1);
        encode_cbor(out, 0, key_blob_label);
        encode_cbor(out, 2, static_cast<std::uint32_t>(blob.size()));
        out = std::copy(blob.begin(), blob.end(), out);
    }
    return static_cast<size_t>(out - buffers.request.data());
}

std::uint32_t decode_cbor(std::span<const unsigned char>& data, unsigned major) {
    require(!data.empty() && (data.front() >> 5) == major);
    const auto info = data.front() & 31u;
    data = data.subspan(1);
    if (info < 24) return info;
    require(info <= 26);
    const size_t width = size_t{1} << (info - 24);
    require(data.size() >= width);
    std::uint32_t value = 0;
    for (const auto byte : data.first(width))
        value = (value << 8) | byte;
    data = data.subspan(width);
    return value;
}

std::span<const unsigned char> response_blob(std::span<const unsigned char> payload, bool generated) {
    const auto entries = decode_cbor(payload, 5);
    require(entries == 1 || (generated && entries == 2));
    require(decode_cbor(payload, 0) == (generated ? key_blob_label : ephemeral_label));
    const auto size = decode_cbor(payload, 2);
    require(size && size <= payload.size() && size <= (generated ? max_blob : max_ephemeral));
    const auto blob = payload.first(size);
    payload = payload.subspan(size);
    if (entries == 2)
        require(decode_cbor(payload, 0) == certificate_count_label && decode_cbor(payload, 0) == 0);
    require(payload.empty());
    return blob;
}

std::span<const unsigned char> request_storage(Object service, StorageBuffers& buffers,
    std::span<const unsigned char> input_blob, bool reject_altered) {
    constexpr std::int32_t invalid_key_blob = -33;
    const auto input_size = storage_request(buffers, input_blob);
    buffers.response.fill(0xff);
    ObjectArg args[2]{};
    args[0].bi = {buffers.request.data(), input_size};
    args[1].b = {buffers.response.data(), buffers.response.size()};
    result(Object_invoke(service, 0, args, ObjectCounts_pack(1, 1, 0, 0)));
    require(args[0].bi.ptr == buffers.request.data() && args[0].bi.size == input_size &&
        args[1].b.ptr == buffers.response.data() && args[1].b.size >= 8 &&
        args[1].b.size <= buffers.response.size());
    const auto status = std::bit_cast<std::int32_t>(word(buffers.response.data()));
    if (reject_altered) {
        require(status == invalid_key_blob);
        return {};
    }
    result(status);
    const auto size = word(buffers.response.data() + 4);
    require(size && size <= args[1].b.size - 8);
    return response_blob(std::span<const unsigned char>(buffers.response.data() + 8, size), input_blob.empty());
}
}

KeymasterVersion inspect_keymaster_owned_provider(int provider_fd, const char*& phase) {
    phase = "qtee-provider-admission";
    require(provider_fd >= 3);
    Fd owned(provider_fd);
    provider(provider_fd);
    KeymasterSession keymaster(phase);
    const auto version = keymaster_version(keymaster.service.get(), phase);
    keymaster.close(phase);
    phase = "qtee-provider-after";
    provider(provider_fd);
    return version;
}

KeymasterStorageResult exercise_keymaster_storage(int provider_fd, const char*& phase) {
    phase = "qtee-provider-admission";
    require(provider_fd >= 3);
    Fd owned(provider_fd);
    provider(provider_fd);
    KeymasterSession keymaster(phase);
    const auto version = keymaster_version(keymaster.service.get(), phase);
    phase = "qtee-keymaster-storage-version";
    require(version.hal_major == 5 && version.hal_minor == 3 &&
        version.app_major == 5 && version.app_minor == 3000);

    phase = "qtee-keymaster-private-disk-record";
    Fd record(open("/var/tmp", O_TMPFILE | O_RDWR | O_CLOEXEC, 0600));
    require(record.value >= 0);
    LockedBuffers locked;
    auto& buffers = locked.get();
    phase = "qtee-keymaster-storage-generate";
    const auto generated = request_storage(keymaster.service.get(), buffers, {}, false);
    const auto size = static_cast<std::uint32_t>(generated.size());
    phase = "qtee-keymaster-private-disk-record-write";
    require(write(record.value, generated.data(), size) == size && !fsync(record.value));
    explicit_bzero(buffers.response.data(), buffers.response.size());
    phase = "qtee-keymaster-private-disk-record-read";
    require(pread(record.value, buffers.blob.data(), size, 0) == size);
    const auto blob = std::span(buffers.blob).first(size);
    phase = "qtee-keymaster-storage-prepare";
    const auto ephemeral = request_storage(keymaster.service.get(), buffers, blob, false);
    const auto ephemeral_size = static_cast<std::uint32_t>(ephemeral.size());
    blob[blob.size() / 2] ^= 1;
    phase = "qtee-keymaster-storage-tamper-refusal";
    request_storage(keymaster.service.get(), buffers, blob, true);
    keymaster.close(phase);
    phase = "qtee-provider-after";
    provider(provider_fd);
    return {size, ephemeral_size};
}
}
