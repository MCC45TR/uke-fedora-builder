// SPDX-License-Identifier: MIT
#include "hwkm-wrapped-key.hpp"
#include <linux/blk-crypto.h>
#include <linux/fs.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <system_error>
#include <utility>

namespace uke::protected_boot::hwkm {
namespace {
static_assert(sizeof(blk_crypto_generate_key_arg) == 48);
static_assert(sizeof(blk_crypto_prepare_key_arg) == 64);
static_assert(BLKCRYPTOGENERATEKEY == 0xc030128aUL);
static_assert(BLKCRYPTOPREPAREKEY == 0xc040128bUL);
[[noreturn]] void failed(const char* operation) {
    throw std::system_error(errno, std::generic_category(), operation);
}
class PinnedBlock {
public:
    explicit PinnedBlock(int fd) {
        fd_ = fcntl(fd, F_DUPFD_CLOEXEC, 3);
        if (fd_ < 0) failed("Pin HWKM descriptor");
        try {
            struct stat st{};
            if (fstat(fd_, &st) < 0) failed("Inspect HWKM descriptor");
            const int flags = fcntl(fd_, F_GETFL);
            if (flags < 0) failed("Inspect HWKM descriptor flags");
            if (!S_ISBLK(st.st_mode) || (flags & O_ACCMODE) != O_RDONLY || (flags & O_PATH))
                throw std::runtime_error("HWKM requires a read-only block descriptor");
            int logical = 0;
            if (ioctl(fd_, BLKSSZGET, &logical) < 0) failed("Inspect HWKM logical size");
            if (logical != 4096) throw std::runtime_error("HWKM requires 4-KiB logical blocks");
        } catch (...) { close(fd_); fd_ = -1; throw; }
    }
    ~PinnedBlock() { if (fd_ >= 0) close(fd_); }
    int fd() const noexcept { return fd_; }
    PinnedBlock(const PinnedBlock&) = delete;
    PinnedBlock& operator=(const PinnedBlock&) = delete;
private:
    int fd_ = -1;
};
uint64_t pointer(const void* p) { return reinterpret_cast<uintptr_t>(p); }
}
struct KeyMemory {
    unsigned char* data = nullptr;
    size_t length = 0;
    pid_t creator = getpid();
    KeyMemory() {
        const long page = sysconf(_SC_PAGESIZE);
        if (page < static_cast<long>(wrapped_key_bytes) || page > 65536)
            throw std::runtime_error("Unsupported HWKM memory page size");
        length = static_cast<size_t>(page);
        void* p = mmap(nullptr, length, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) failed("Allocate HWKM memory");
        data = static_cast<unsigned char*>(p);
        // Set both exclusions and lock the entire distinct mapping before the
        // first key byte. A fork gets zeros; a child cannot use the parent key.
        if (madvise(data, length, MADV_DONTDUMP) < 0 ||
            madvise(data, length, MADV_WIPEONFORK) < 0 || mlock(data, length) < 0) {
            const int saved = errno;
            munmap(data, length); data = nullptr; errno = saved;
            failed("Protect HWKM memory");
        }
    }
    ~KeyMemory() {
        if (data) {
            explicit_bzero(data, length);
            // munmap also unlocks the page; avoid a pageable interval with
            // live contents and avoid unlocking another allocation's page.
            munmap(data, length);
        }
    }
    KeyMemory(const KeyMemory&) = delete;
    KeyMemory& operator=(const KeyMemory&) = delete;
};
WrappedKey::WrappedKey(std::unique_ptr<KeyMemory> memory, Lifetime lifetime)
    : memory_(std::move(memory)), lifetime_(lifetime) {}
WrappedKey::~WrappedKey() = default;
WrappedKey::WrappedKey(WrappedKey&&) noexcept = default;
WrappedKey& WrappedKey::operator=(WrappedKey&&) noexcept = default;
std::span<const unsigned char> WrappedKey::bytes() const {
    if (!memory_ || memory_->creator != getpid())
        throw std::runtime_error("HWKM key is not owned by this process");
    return {memory_->data, wrapped_key_bytes};
}
Lifetime WrappedKey::lifetime() const { (void)bytes(); return lifetime_; }
WrappedKey generate_v2(int block_fd) {
    PinnedBlock block(block_fd);
    auto output = std::make_unique<KeyMemory>();
    blk_crypto_generate_key_arg arg{};
    arg.lt_key_ptr = pointer(output->data);
    arg.lt_key_size = wrapped_key_bytes;
    if (ioctl(block.fd(), BLKCRYPTOGENERATEKEY, &arg) < 0)
        failed("Generate hardware-wrapped key");
    if (arg.lt_key_size != wrapped_key_bytes || arg.lt_key_ptr != pointer(output->data) ||
        arg.reserved[0] || arg.reserved[1] || arg.reserved[2] || arg.reserved[3])
        throw std::runtime_error("Unexpected HWKM v2 generation response");
    return WrappedKey(std::move(output), Lifetime::LongTerm);
}
WrappedKey load_long_term_v2(std::span<const unsigned char> blob) {
    if (blob.size() != wrapped_key_bytes)
        throw std::runtime_error("Invalid HWKM v2 long-term blob size");
    auto memory = std::make_unique<KeyMemory>();
    std::memcpy(memory->data, blob.data(), blob.size());
    return WrappedKey(std::move(memory), Lifetime::LongTerm);
}
WrappedKey prepare_v2(int block_fd, WrappedKey&& long_term) {
    // Move before validation so even an invalid descriptor consumes the input.
    WrappedKey input(std::move(long_term));
    if (input.lifetime() != Lifetime::LongTerm)
        throw std::runtime_error("HWKM preparation requires a long-term blob");
    PinnedBlock block(block_fd);
    auto output = std::make_unique<KeyMemory>();
    blk_crypto_prepare_key_arg arg{};
    arg.lt_key_ptr = pointer(input.memory_->data);
    arg.lt_key_size = wrapped_key_bytes;
    arg.eph_key_ptr = pointer(output->data);
    arg.eph_key_size = wrapped_key_bytes;
    if (ioctl(block.fd(), BLKCRYPTOPREPAREKEY, &arg) < 0)
        failed("Prepare hardware-wrapped key");
    if (arg.lt_key_size != wrapped_key_bytes || arg.lt_key_ptr != pointer(input.memory_->data) ||
        arg.eph_key_size != wrapped_key_bytes || arg.eph_key_ptr != pointer(output->data) ||
        arg.reserved[0] || arg.reserved[1] || arg.reserved[2] || arg.reserved[3])
        throw std::runtime_error("Unexpected HWKM v2 preparation response");
    return WrappedKey(std::move(output), Lifetime::PerBoot);
}
}
