// SPDX-License-Identifier: MIT
// Interface facts: Qualcomm TPM v4, 19 October 2026 (UID81), and the original
// MINK userspace API. Upstream C/assembly adapters are compiled unchanged;
// original Fedora libqcomtee handles credentials and object marshalling.
#include "qtee-tpm-discovery.hpp"
#include <MinkCom.h>
#include <linux/tee.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <array>
#include <cerrno>
#include <cstdint>
#include <stdexcept>
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
    ObjectArg open[2]{};
    open[0].bi = {service_uid.data(), service_uid.size()};
    open[1].o = Object_NULL;
    const auto status = Object_invoke(environment.get(), 0, open, ObjectCounts_pack(1, 0, 0, 1));
    service.adopt(open[1].o);
    result(status);
    service.present();
    require(open[0].bi.ptr == service_uid.data() && open[0].bi.size == service_uid.size() && word(service_uid.data()) == uid);
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
}
