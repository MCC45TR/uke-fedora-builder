// SPDX-License-Identifier: MIT
// Link-time syscall doubles exercise the production implementation without
// invoking firmware. Actual mmap/mlock/madvise/fork behavior is retained.
#include "hwkm-wrapped-key.hpp"
#include <linux/blk-crypto.h>
#include <linux/fs.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <functional>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <system_error>
#include <type_traits>
#include <utility>

#ifndef __aarch64__
#error Native AArch64 qualification required
#endif
using namespace uke::protected_boot::hwkm;
extern "C" int __real_fstat(int, struct stat*);
extern "C" void* __real_mmap(void*, size_t, int, int, int, off_t);
extern "C" int __real_munmap(void*, size_t);
extern "C" int __real_mlock(const void*, size_t);
extern "C" int __real_madvise(void*, size_t, int);
namespace {
void require(bool value) { if (!value) throw std::runtime_error("HWKM fixture assertion"); }
struct Allocation { void* address = nullptr; size_t bytes = 0; };
std::array<Allocation, 16> allocations{};
size_t unmapped_zero = 0, live = 0, maximum_live = 0, ioctl_calls = 0, rejected = 0;
size_t generate_calls = 0, prepare_calls = 0;
dev_t fixture_dev; ino_t fixture_ino;
bool emulate_block = true;
int logical_size = 4096, response_error = 0, response_change = 0;
enum class MemoryFailure { None, Map, Lock, Dump, Fork };
MemoryFailure memory_failure = MemoryFailure::None;
void reject(const std::function<void()>& f, int expected_errno = 0) {
    try { f(); }
    catch (const std::system_error& e) {
        require(!expected_errno || e.code().value() == expected_errno); ++rejected; return;
    }
    catch (const std::runtime_error&) { require(!expected_errno); ++rejected; return; }
    throw std::runtime_error("Invalid HWKM operation accepted");
}
size_t descriptor_count() {
    DIR* directory = opendir("/proc/self/fd"); require(directory);
    size_t count = 0;
    while (readdir(directory)) ++count;
    closedir(directory); return count;
}
bool mapping_protected(const void* address) {
    std::ifstream input("/proc/self/smaps");
    std::string line; bool selected = false;
    const auto point = reinterpret_cast<uintptr_t>(address);
    while (std::getline(input, line)) {
        unsigned long first = 0, last = 0;
        if (std::sscanf(line.c_str(), "%lx-%lx", &first, &last) == 2)
            selected = point >= first && point < last;
        if (selected && line.starts_with("VmFlags:")) {
            std::istringstream flags(line); std::string flag;
            bool locked = false, no_dump = false, wiped_fork = false;
            while (flags >> flag) {
                locked |= flag == "lo"; no_dump |= flag == "dd"; wiped_fork |= flag == "wf";
            }
            return locked && no_dump && wiped_fork;
        }
    }
    return false;
}
}
extern "C" int __wrap_fstat(int fd, struct stat* st) {
    const int result = __real_fstat(fd, st);
    if (!result && emulate_block && st->st_dev == fixture_dev && st->st_ino == fixture_ino)
        st->st_mode = (st->st_mode & ~S_IFMT) | S_IFBLK;
    return result;
}
extern "C" void* __wrap_mmap(void* at, size_t length, int prot, int flags, int fd, off_t offset) {
    if (memory_failure == MemoryFailure::Map) { errno = ENOMEM; return MAP_FAILED; }
    void* p = __real_mmap(at, length, prot, flags, fd, offset);
    if (p != MAP_FAILED) {
        auto it = std::find_if(allocations.begin(), allocations.end(), [](auto a) { return !a.address; });
        if (it == allocations.end()) std::abort();
        *it = {p, length}; ++live; maximum_live = std::max(maximum_live, live);
    }
    return p;
}
extern "C" int __wrap_munmap(void* at, size_t length) {
    auto it = std::find_if(allocations.begin(), allocations.end(), [at](auto a) { return a.address == at; });
    if (it == allocations.end() || it->bytes != length) std::abort();
    const auto* bytes = static_cast<const unsigned char*>(at);
    if (!std::all_of(bytes, bytes + length, [](auto c) { return c == 0; })) std::abort();
    ++unmapped_zero; --live; *it = {};
    return __real_munmap(at, length);
}
extern "C" int __wrap_mlock(const void* at, size_t length) {
    if (memory_failure == MemoryFailure::Lock) { errno = ENOMEM; return -1; }
    return __real_mlock(at, length);
}
extern "C" int __wrap_madvise(void* at, size_t length, int advice) {
    if ((memory_failure == MemoryFailure::Dump && advice == MADV_DONTDUMP) ||
        (memory_failure == MemoryFailure::Fork && advice == MADV_WIPEONFORK)) {
        errno = EINVAL; return -1;
    }
    return __real_madvise(at, length, advice);
}
extern "C" int __wrap_ioctl(int fd, unsigned long command, ...) {
    va_list args; va_start(args, command); void* p = va_arg(args, void*); va_end(args);
    struct stat st{};
    require(__real_fstat(fd, &st) == 0 && st.st_dev == fixture_dev && st.st_ino == fixture_ino);
    require(fcntl(fd, F_GETFD) & FD_CLOEXEC);
    ++ioctl_calls;
    if (command == BLKSSZGET) { *static_cast<int*>(p) = logical_size; return 0; }
    __u64* size = nullptr; __u64* address = nullptr; __u64* reserved = nullptr;
    if (command == BLKCRYPTOGENERATEKEY) {
        ++generate_calls;
        auto& a = *static_cast<blk_crypto_generate_key_arg*>(p);
        size = &a.lt_key_size; address = &a.lt_key_ptr; reserved = a.reserved;
    } else if (command == BLKCRYPTOPREPAREKEY) {
        ++prepare_calls;
        auto& a = *static_cast<blk_crypto_prepare_key_arg*>(p);
        require(a.lt_key_size == wrapped_key_bytes);
        const auto* input = reinterpret_cast<const unsigned char*>(a.lt_key_ptr);
        require(std::all_of(input, input + wrapped_key_bytes, [](auto c) { return c == 0xa3; }));
        size = &a.eph_key_size; address = &a.eph_key_ptr; reserved = a.reserved;
    } else throw std::runtime_error("Unexpected ioctl or raw-key import");
    require(*size == wrapped_key_bytes && *address);
    require(std::all_of(reserved, reserved + 4, [](auto c) { return c == 0; }));
    auto* output = reinterpret_cast<unsigned char*>(*address);
    require(mapping_protected(output));
    require(std::all_of(output, output + wrapped_key_bytes, [](auto c) { return c == 0; }));
    std::memset(output, command == BLKCRYPTOGENERATEKEY ? 0xa3 : 0x5c, wrapped_key_bytes);
    if (response_error) { errno = response_error; return -1; }
    if (response_change == 1) *size = 0;
    if (response_change == 2) *size = 99;
    if (response_change == 3) *size = 101;
    if (response_change == 4) *size = UINT64_MAX;
    if (response_change == 5) ++*address;
    if (response_change == 6) reserved[3] = 1;
    if (response_change == 7) ++static_cast<blk_crypto_prepare_key_arg*>(p)->lt_key_size;
    if (response_change == 8) ++static_cast<blk_crypto_prepare_key_arg*>(p)->lt_key_ptr;
    return 0;
}
int main() {
    char name[] = "hwkm-source-fixture-XXXXXX";
    int created = -1, fd = -1;
    try {
        static_assert(!std::is_copy_constructible_v<WrappedKey>);
        static_assert(!std::is_default_constructible_v<WrappedKey>);
        created = mkstemp(name); require(created >= 0);
        require(ftruncate(created, 4096) == 0);
        struct stat st{}; require(__real_fstat(created, &st) == 0);
        fixture_dev = st.st_dev; fixture_ino = st.st_ino;
        fd = open(name, O_RDONLY | O_CLOEXEC); require(fd >= 0); require(unlink(name) == 0);
        const auto baseline_fds = descriptor_count();
        std::array<unsigned char, wrapped_key_bytes> blob{};
        blob.fill(0xa3); // Public synthetic wrapped-shaped bytes; not a real key.
        {
            auto generated = generate_v2(fd);
            require(generated.lifetime() == Lifetime::LongTerm &&
                std::equal(generated.bytes().begin(), generated.bytes().end(), blob.begin()));
            require(mapping_protected(generated.bytes().data()));
            auto moved = std::move(generated);
            reject([&] { (void)generated.bytes(); });
            auto prepared = prepare_v2(fd, std::move(moved));
            reject([&] { (void)moved.bytes(); });
            require(prepared.lifetime() == Lifetime::PerBoot && prepared.bytes().size() == wrapped_key_bytes);
            require(std::all_of(prepared.bytes().begin(), prepared.bytes().end(), [](auto c) { return c == 0x5c; }));
            auto second = prepare_v2(fd, load_long_term_v2(blob));
            second = std::move(prepared); // Replaces and wipes an existing allocation.
            const auto before = ioctl_calls;
            reject([&] { (void)prepare_v2(fd, std::move(second)); });
            require(ioctl_calls == before);
        }
        require(live == 0);
        for (size_t size : {size_t{0}, size_t{99}, size_t{101}}) {
            std::array<unsigned char, 101> other{};
            reject([&] { (void)load_long_term_v2({other.data(), size}); });
        }
        for (int error : {EOPNOTSUPP, EIO, EINTR, EOVERFLOW, EBADMSG}) {
            response_error = error;
            auto before = generate_calls;
            reject([&] { (void)generate_v2(fd); }, error);
            require(generate_calls == before + 1); // No automatic key regeneration/retry.
            before = prepare_calls;
            auto input = load_long_term_v2(blob);
            reject([&] { (void)prepare_v2(fd, std::move(input)); }, error);
            require(prepare_calls == before + 1);
            reject([&] { (void)input.bytes(); });
            require(live == 0);
        }
        response_error = 0;
        for (int change = 1; change <= 8; ++change) {
            response_change = change;
            if (change <= 6) reject([&] { (void)generate_v2(fd); });
            reject([&] { (void)prepare_v2(fd, load_long_term_v2(blob)); });
            require(live == 0);
        }
        response_change = 0;
        for (const auto failure : {MemoryFailure::Map, MemoryFailure::Lock, MemoryFailure::Dump, MemoryFailure::Fork}) {
            memory_failure = failure;
            const auto before = generate_calls + prepare_calls;
            reject([&] { (void)generate_v2(fd); });
            reject([&] { (void)load_long_term_v2(blob); });
            require(before == generate_calls + prepare_calls && live == 0);
        }
        memory_failure = MemoryFailure::None;
        reject([&] { (void)generate_v2(-1); }, EBADF);
        reject([&] { (void)generate_v2(created); }); // O_RDWR is not accepted.
        emulate_block = false;
        reject([&] { (void)generate_v2(fd); });
        emulate_block = true; logical_size = 512;
        reject([&] { (void)generate_v2(fd); });
        logical_size = 4096;
        auto input = load_long_term_v2(blob);
        reject([&] { (void)prepare_v2(-1, std::move(input)); }, EBADF);
        reject([&] { (void)input.bytes(); });
        require(live == 0);
        {
            auto parent = load_long_term_v2(blob);
            const auto* pointer = parent.bytes().data();
            const pid_t pid = fork(); require(pid >= 0);
            if (pid == 0) {
                if (!std::all_of(pointer, pointer + wrapped_key_bytes, [](auto c) { return c == 0; })) _exit(3);
                try { (void)parent.bytes(); _exit(4); } catch (const std::runtime_error&) { _exit(0); }
            }
            int status = 0; require(waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0);
            require(std::equal(parent.bytes().begin(), parent.bytes().end(), blob.begin()));
        }
        require(live == 0 && descriptor_count() == baseline_fds && maximum_live <= 3 && unmapped_zero > 40);
        close(fd); close(created); fd = created = -1;
        std::cout << "{\"schema_version\":1,\"native_architecture\":\"aarch64\",\"production_implementation_tested\":true,"
            "\"syscall_doubles_for_firmware_and_block_facts\":true,\"real_locked_nondumpable_fork_wiped_memory\":true,"
            "\"all_unmapped_key_pages_zero\":true,\"consumed_input_on_failure\":true,\"no_automatic_ioctl_retry\":true,"
            "\"no_descriptor_or_memory_leak\":true,\"maximum_live_key_pages\":" << maximum_live << ",\"refused_cases\":" << rejected << ","
            "\"zeroed_unmaps\":" << unmapped_zero << ",\"physical_key_generated\":false,\"boot_policy_admitted\":false}\n";
        return 0;
    } catch (const std::exception& error) {
        if (fd >= 0) close(fd);
        if (created >= 0) { close(created); unlink(name); }
        std::cerr << error.what() << '\n'; return 1;
    }
}
