// SPDX-License-Identifier: MIT
#include "hwkm-inlinecrypt-read.hpp"

#include <array>
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cerrno>
#include <cstdarg>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <linux/blk-crypto.h>
#include <linux/dm-ioctl.h>
#include <linux/fs.h>
#include <linux/keyctl.h>
#include <stdexcept>
#include <string>
#include <string_view>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <system_error>
#include <utility>

using namespace uke::protected_boot::hwkm;
namespace {
constexpr int block = 10, duplicate = 11, control = 12, mapped = 13;
constexpr std::string_view name = "uke-hwkm-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
const std::string uuid = "UKE-HWKM-PROBE-" + std::string(name);
const std::string description = "uke-hwkm:" + std::string(name);
enum class Failure { None, Load, MissingReadOnly, Identical, ShortRead, Removal };
enum class Rescue { Off, Write, Read };
Failure failure;
Rescue rescue = Rescue::Off;
bool owned_mapping, owned_key, failed_removal;
unsigned block_reads;
unsigned block_writes;
std::array<unsigned char, 4096> rescue_plaintext{};
bool rescue_ciphertext;
}
extern "C" int __wrap_open(const char* path, int flags, ...) {
    if (std::string_view(path) == "/dev/mapper/control") {
        assert(flags == (O_RDWR | O_CLOEXEC | O_NOFOLLOW));
        return control;
    }
    assert(std::string_view(path) == "/dev/dm-5" && owned_mapping && !owned_key);
    const int expected = rescue == Rescue::Off ? O_RDONLY :
        (rescue == Rescue::Write ? O_RDWR : O_RDONLY) | O_DIRECT;
    assert(flags == (expected | O_CLOEXEC | O_NOFOLLOW));
    return mapped;
}
extern "C" int __wrap_close(int fd) {
    assert(fd == duplicate || fd == mapped || fd == control);
    return 0;
}
extern "C" int __wrap_fcntl(int fd, int op, ...) {
    assert(fd == block || fd == duplicate);
    if (op == F_GETFL) return O_RDONLY | (rescue == Rescue::Off ? 0 : O_DIRECT);
    assert(fd == block && op == F_DUPFD_CLOEXEC);
    return duplicate;
}
extern "C" int __wrap_fstat(int fd, struct stat* st) {
    assert(fd == block || fd == duplicate || fd == mapped);
    st->st_mode = S_IFBLK;
    st->st_rdev = fd == mapped ? makedev(253, 5) : makedev(8, 32);
    return 0;
}
extern "C" ssize_t __wrap_getrandom(void* data, size_t bytes, unsigned flags) {
    assert(bytes == 16 && flags == 0);
    std::memset(data, 0xee, bytes);
    return bytes;
}
extern "C" long __wrap_syscall(long number, ...) {
    va_list args;
    va_start(args, number);
    if (number == SYS_add_key) {
        assert(owned_mapping && !owned_key);
        assert(std::string_view(va_arg(args, const char*)) == "logon");
        assert(std::string_view(va_arg(args, const char*)) == description);
        assert(*va_arg(args, const unsigned char*) == 0x5b);
        assert(va_arg(args, size_t) == wrapped_key_bytes);
        assert(va_arg(args, int) == KEY_SPEC_PROCESS_KEYRING);
        owned_key = true;
        va_end(args);
        return 99;
    }
    assert(number == SYS_keyctl && owned_key);
    const int op = va_arg(args, int);
    assert(va_arg(args, long) == 99);
    if (op == KEYCTL_UNLINK) {
        assert(va_arg(args, int) == KEY_SPEC_PROCESS_KEYRING);
        owned_key = false;
    } else assert(op == KEYCTL_REVOKE);
    va_end(args);
    return 0;
}
extern "C" int __wrap_ioctl(int fd, unsigned long op, ...) {
    va_list args;
    va_start(args, op);
    if (fd == duplicate || fd == mapped) {
        if (op == BLKSSZGET) *va_arg(args, int*) = 4096;
        else if (op == BLKROGET) *va_arg(args, int*) = failure != Failure::MissingReadOnly && rescue != Rescue::Write;
        else if (op == BLKGETSIZE64) *va_arg(args, uint64_t*) = 4096;
        else {
            assert(op == BLKCRYPTOPREPAREKEY);
            auto* arg = va_arg(args, blk_crypto_prepare_key_arg*);
            std::memset(reinterpret_cast<void*>(arg->eph_key_ptr), 0x5b, arg->eph_key_size);
        }
        va_end(args);
        return 0;
    }
    assert(fd == control);
    auto* request = va_arg(args, dm_ioctl*);
    va_end(args);
    assert(request->uuid == uuid && request->version[0] == 4);
    switch (op) {
    case DM_DEV_CREATE:
        assert(!owned_mapping && request->name == name);
        owned_mapping = true;
        return 0;
    case DM_TABLE_LOAD: {
        assert(owned_mapping && owned_key && request->flags == (rescue == Rescue::Write ? 0 : DM_READONLY_FLAG) &&
               request->target_count == 1);
        auto* spec = reinterpret_cast<dm_target_spec*>(reinterpret_cast<char*>(request) + request->data_start);
        assert(spec->sector_start == 0 && spec->length == 8 && spec->next % 8 == 0);
        assert(std::string_view(spec->target_type) == "inlinecrypt");
        const std::string offset = rescue == Rescue::Off ? "0" : "4002048";
        const std::string expected = "aes-xts-plain64 :100:logon:" + description +
            " 8 8:32 " + offset + " 3 keytype:hw-wrapped sector_size:4096 iv_large_sectors";
        assert(reinterpret_cast<char*>(spec + 1) == expected);
        if (failure == Failure::Load) errno = EINVAL;
        return failure == Failure::Load ? -1 : 0;
    }
    case DM_DEV_SUSPEND:
        assert(owned_mapping && !owned_key && request->flags == 0);
        return 0;
    case DM_DEV_STATUS:
        request->flags = DM_ACTIVE_PRESENT_FLAG | (rescue == Rescue::Write ? 0 : DM_READONLY_FLAG);
        request->dev = makedev(253, 5);
        request->target_count = 1;
        return 0;
    case DM_DEV_REMOVE:
        assert(owned_mapping && !owned_key);
        if (failure == Failure::Removal && !failed_removal) {
            failed_removal = true;
            return -1;
        }
        owned_mapping = false;
        return 0;
    default:
        throw std::runtime_error("Unexpected ioctl");
    }
}
extern "C" ssize_t __wrap_pread(int fd, void* out, size_t bytes, off_t offset) {
    if (rescue != Rescue::Off) {
        assert(bytes == 4096 && (fd == block || fd == mapped));
        if (fd == block) {
            assert(offset == rescue_block_offset && !owned_mapping);
            std::memset(out, rescue_ciphertext ? 0x37 : 0, bytes);
        } else {
            assert(offset == 0 && owned_mapping && rescue_ciphertext);
            std::memcpy(out, rescue_plaintext.data(), bytes);
        }
        return bytes;
    }
    assert((fd == block || fd == mapped) && offset == 0 && bytes == 4096 && owned_mapping);
    std::memset(out, fd == block || failure == Failure::Identical ? 0x15 : 0x37, bytes);
    ++block_reads;
    return fd == mapped && failure == Failure::ShortRead ? bytes - 1 : bytes;
}

extern "C" ssize_t __wrap_pwrite(int fd, const void* in, size_t bytes, off_t offset) {
    assert(rescue == Rescue::Write && fd == mapped && offset == 0 && bytes == 4096);
    assert(owned_mapping && !rescue_ciphertext);
    std::memcpy(rescue_plaintext.data(), in, bytes);
    rescue_ciphertext = true;
    ++block_writes;
    return bytes;
}

extern "C" int __wrap_fsync(int fd) {
    assert(rescue == Rescue::Write && fd == mapped && rescue_ciphertext);
    return 0;
}
int main() {
    for (const auto fault : {Failure::None, Failure::Load, Failure::MissingReadOnly, Failure::Identical,
                             Failure::ShortRead, Failure::Removal}) {
        failure = fault;
        block_reads = 0;
        bool accepted = false;
        const char* phase = nullptr;
        std::array<unsigned char, wrapped_key_bytes> seed{};
        auto key = prepare_v2(block, load_long_term_v2(seed));
        try {
            const auto result = exercise_inlinecrypt_read(block, std::move(key), phase);
            assert(result.backing_sha256 == "a3ee21d0ee09617b7d834e76b0e08967e9a45576a299c3281af1ba34de4330fd");
            assert(result.mapped_sha256 == "1223dde07e0e3571d377800cde8d6e97188dd70a6d15e2c47ef530dc5b3ffc27");
            accepted = true;
        } catch (const std::system_error& error) {
            assert(fault == Failure::Load && error.code().value() == EINVAL);
        } catch (const std::runtime_error&) {
            assert(fault != Failure::Load);
        }
        if (accepted != (fault == Failure::None))
            std::cerr << "Unexpected inlinecrypt result for fixture " << static_cast<int>(fault)
                      << " at " << phase << '\n';
        assert(accepted == (fault == Failure::None));
        const bool reads = fault == Failure::None || fault == Failure::Identical ||
            fault == Failure::ShortRead || fault == Failure::Removal;
        assert(block_reads == (reads ? 2u : 0u));
        assert(!owned_mapping && !owned_key);
    }
    failure = Failure::None;
    const char* phase = nullptr;
    const std::array<unsigned char, wrapped_key_bytes> seed{};
    constexpr std::string_view zeros = "ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7";
    constexpr std::string_view ciphertext = "1223dde07e0e3571d377800cde8d6e97188dd70a6d15e2c47ef530dc5b3ffc27";
    rescue = Rescue::Write;
    bool wrong_digest_refused = false;
    try {
        auto key = prepare_v2(block, load_long_term_v2(seed));
        (void)exercise_inlinecrypt_rescue_block(block, std::move(key), ciphertext, true, phase);
    } catch (const std::runtime_error&) {
        assert(std::string_view(phase) == "rescue-raw-before");
        wrong_digest_refused = true;
    }
    assert(wrong_digest_refused && !owned_mapping && !owned_key && block_writes == 0);
    auto write_key = prepare_v2(block, load_long_term_v2(seed));
    const auto write_report = exercise_inlinecrypt_rescue_block(block, std::move(write_key), zeros, true, phase);
    assert(write_report.backing_sha256 == ciphertext && block_writes == 1 && !owned_mapping && !owned_key);
    rescue = Rescue::Read;
    auto read_key = prepare_v2(block, load_long_term_v2(seed));
    const auto read_report = exercise_inlinecrypt_rescue_block(block, std::move(read_key), ciphertext, false, phase);
    assert(write_report.mapped_sha256 == read_report.mapped_sha256 && read_report.backing_sha256 == ciphertext);
    assert(block_writes == 1 && !owned_mapping && !owned_key);
    std::cout << "{\"readonly_mapping_fixture\":true,\"sha256_fixture\":true,"
                 "\"rescue_single_block_fixture\":true,\"wrong_rescue_digest_refused\":true,"
                 "\"refused_cases\":5,\"physical_encrypted_io\":false}\n";
}
