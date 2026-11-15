// SPDX-License-Identifier: MIT
// Real private files, locking, fsync and rename. Faults affect only this
// disposable host fixture; no physical block device or firmware is used.
#include "hwkm-disposable-record.hpp"
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <linux/fs.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdarg>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>

#ifndef __aarch64__
#error Native AArch64 qualification required
#endif
using namespace uke::protected_boot::hwkm;
using disposable::Record;
extern "C" ssize_t __real_pread(int, void*, size_t, off_t);
extern "C" ssize_t __real_pwrite(int, const void*, size_t, off_t);
extern "C" int __real_fsync(int);
extern "C" int __real_fstatvfs(int, struct statvfs*);
extern "C" long __real_syscall(long, ...);
extern "C" void* __real_mmap(void*, size_t, int, int, int, off_t);
extern "C" int __real_munmap(void*, size_t);
namespace {
void require(bool v) { if (!v) throw std::runtime_error("Disposable record fixture assertion"); }
enum class Fault { None, WriteError, WriteZero, WriteInterrupted, WriteShort,
 ReadError, ReadZero, ReadInterrupted, ReadShort, ReadBlobError, ReadBlobZero,
 FileSync, DirectorySync, Rename, NoSpace };
Fault fault = Fault::None;
size_t refused = 0, zeroed_unmaps = 0, live = 0;
struct Allocation { void* address = nullptr; size_t bytes = 0; };
std::array<Allocation, 8> allocations{};
constexpr char filename[] = "disposable-key-v1";
size_t descriptors() {
 DIR* d = opendir("/proc/self/fd"); require(d);
 size_t n = 0; while (readdir(d)) ++n; closedir(d); return n;
}
void rejects(const std::function<void()>& f) {
 const auto before = descriptors(), pages = live;
 bool threw = false;
 try { f(); } catch (const std::exception&) { threw = true; }
 require(threw && descriptors() == before && live == pages); ++refused;
}
struct Temp {
 std::string path;
 int fd;
 Temp() : fd(-1) {
  char name[] = "/tmp/uke-hwkm-record.XXXXXX";
  const auto p = mkdtemp(name); require(p); path = p;
  fd = open(path.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC); require(fd >= 0);
 }
 ~Temp() { if (fd >= 0) close(fd); std::error_code e; std::filesystem::remove_all(path, e); }
};
void overwrite(int directory, unsigned char byte, off_t offset) {
 int fd = openat(directory, filename, O_WRONLY | O_CLOEXEC | O_NOFOLLOW); require(fd >= 0);
 const auto result = pwrite(fd, &byte, 1, offset); close(fd); require(result == 1);
}
bool no_temporaries(const Temp& dir) {
 for (const auto& entry : std::filesystem::directory_iterator(dir.path))
  if (entry.path().filename().string().starts_with(".new-key-")) return false;
 return true;
}
}
extern "C" int __wrap_ioctl(int, unsigned long, ...) { std::abort(); }
extern "C" ssize_t __wrap_pwrite(int fd, const void* p, size_t bytes, off_t offset) {
 if (fault == Fault::WriteError) { errno = EIO; return -1; }
 if (fault == Fault::WriteZero) return 0;
 if (fault == Fault::WriteInterrupted) { fault = Fault::WriteShort; errno = EINTR; return -1; }
 if (fault == Fault::WriteShort) bytes = std::min(bytes, size_t{3});
 return __real_pwrite(fd, p, bytes, offset);
}
extern "C" ssize_t __wrap_pread(int fd, void* p, size_t bytes, off_t offset) {
 if (fault == Fault::ReadError) { errno = EIO; return -1; }
 if (fault == Fault::ReadZero) return 0;
 if (offset >= 28 && fault == Fault::ReadBlobError) { errno = EIO; return -1; }
 if (offset >= 28 && fault == Fault::ReadBlobZero) return 0;
 if (fault == Fault::ReadInterrupted) { fault = Fault::ReadShort; errno = EINTR; return -1; }
 if (fault == Fault::ReadShort) bytes = std::min(bytes, size_t{3});
 return __real_pread(fd, p, bytes, offset);
}
extern "C" int __wrap_fsync(int fd) {
 struct stat st{}; require(fstat(fd, &st) == 0);
 if ((fault == Fault::FileSync && S_ISREG(st.st_mode)) ||
     (fault == Fault::DirectorySync && S_ISDIR(st.st_mode))) { errno = EIO; return -1; }
 return __real_fsync(fd);
}
extern "C" int __wrap_fstatvfs(int fd, struct statvfs* st) {
 int result = __real_fstatvfs(fd, st);
 if (!result && fault == Fault::NoSpace) st->f_bavail = 0;
 return result;
}
extern "C" long __wrap_syscall(long command, ...) {
 require(command == SYS_renameat2);
 va_list args; va_start(args, command);
 int olddir = va_arg(args, int); const char* oldname = va_arg(args, const char*);
 int newdir = va_arg(args, int); const char* newname = va_arg(args, const char*);
 unsigned flags = va_arg(args, unsigned); va_end(args);
 if (fault == Fault::Rename) { errno = EIO; return -1; }
 return __real_syscall(command, olddir, oldname, newdir, newname, flags);
}
extern "C" void* __wrap_mmap(void* at, size_t bytes, int prot, int flags, int fd, off_t offset) {
 auto p = __real_mmap(at, bytes, prot, flags, fd, offset);
 if (p != MAP_FAILED) {
  auto it = std::find_if(allocations.begin(), allocations.end(), [](auto a) { return !a.address; });
  require(it != allocations.end()); *it = {p, bytes}; ++live;
 }
 return p;
}
extern "C" int __wrap_munmap(void* p, size_t bytes) {
 auto it = std::find_if(allocations.begin(), allocations.end(), [p](auto a) { return a.address == p; });
 require(it != allocations.end() && it->bytes == bytes);
 const auto begin = static_cast<const unsigned char*>(p);
 require(std::all_of(begin, begin + bytes, [](auto b) { return b == 0; }));
 *it = {}; --live; ++zeroed_unmaps; return __real_munmap(p, bytes);
}
int main() {
 try {
  const auto initial = descriptors();
  std::array<unsigned char, wrapped_key_bytes> public_pattern{};
  for (size_t i = 0; i < public_pattern.size(); ++i) public_pattern[i] = static_cast<unsigned char>(i);
  {
   auto key = load_long_term_v2(public_pattern);
   Temp dir;
   {
    Record r(dir.fd); require(!r.exists() && !r.remove());
    rejects([&] { Record duplicate(dir.fd); });
    r.create(key); require(r.exists());
    struct stat st{}; require(fstatat(dir.fd, filename, &st, 0) == 0 && st.st_size == 128 &&
      (st.st_mode & 07777) == 0600 && st.st_nlink == 1);
    rejects([&] { r.create(key); });
    { auto read = r.read(); require(std::equal(read.bytes().begin(), read.bytes().end(), public_pattern.begin())); }
   }
   // A distinct process reopens the persisted bytes. This proves file
   // mechanics across processes, never a physical reboot or hardware unwrap.
   const auto child = fork(); require(child >= 0);
   if (!child) {
    try { bool match = false;
     { Record r(dir.fd); auto read = r.read();
      match = std::equal(read.bytes().begin(), read.bytes().end(), public_pattern.begin()); }
     _exit(match ? 0 : 1);
    } catch (...) { _exit(2); }
   }
   int status = 0; require(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
   Record r(dir.fd);
   for (auto f : {Fault::ReadError, Fault::ReadZero, Fault::ReadBlobError, Fault::ReadBlobZero}) {
    fault = f; rejects([&] { (void)r.read(); }); fault = Fault::None;
   }
   fault = Fault::ReadInterrupted;
   { auto read = r.read(); require(std::equal(read.bytes().begin(), read.bytes().end(), public_pattern.begin())); }
   fault = Fault::None;
   overwrite(dir.fd, 'X', 0); rejects([&] { (void)r.read(); }); rejects([&] { (void)r.remove(); });
   overwrite(dir.fd, 'U', 0);
   require(fchmodat(dir.fd, filename, 0644, 0) == 0);
   rejects([&] { (void)r.read(); }); require(fchmodat(dir.fd, filename, 0600, 0) == 0);
   require(linkat(dir.fd, filename, dir.fd, "extra-link", 0) == 0);
   rejects([&] { (void)r.read(); }); require(unlinkat(dir.fd, "extra-link", 0) == 0);
   require(r.remove() && !r.exists() && !r.remove());
   require(symlinkat("missing", dir.fd, filename) == 0);
   rejects([&] { r.create(key); }); rejects([&] { (void)r.read(); }); rejects([&] { (void)r.remove(); });
   require(unlinkat(dir.fd, filename, 0) == 0);
   for (auto f : {Fault::WriteError, Fault::WriteZero, Fault::FileSync, Fault::Rename, Fault::NoSpace}) {
    fault = f; rejects([&] { r.create(key); }); fault = Fault::None;
    require(!r.exists() && no_temporaries(dir));
   }
   fault = Fault::DirectorySync; rejects([&] { r.create(key); }); fault = Fault::None;
   require(r.exists() && no_temporaries(dir));
   rejects([&] { r.create(key); }); require(r.remove());
   fault = Fault::WriteInterrupted; r.create(key); fault = Fault::None;
   { auto read = r.read(); require(std::equal(read.bytes().begin(), read.bytes().end(), public_pattern.begin())); }
   // Truncation and trailing bytes cannot be treated as a valid record.
   int raw = openat(dir.fd, filename, O_RDWR | O_CLOEXEC); require(raw >= 0);
   require(ftruncate(raw, 127) == 0); rejects([&] { (void)r.read(); });
   require(ftruncate(raw, 129) == 0); rejects([&] { (void)r.read(); });
   require(ftruncate(raw, 128) == 0);
   rejects([&] { (void)read_long_term_v2(raw, 28); });
   close(raw);
   raw = openat(dir.fd, filename, O_RDONLY | O_CLOEXEC); require(raw >= 0);
   rejects([&] { (void)read_long_term_v2(raw, UINT64_MAX); });
   rejects([&] { (void)read_long_term_v2(raw, 29); }); close(raw);
   raw = openat(dir.fd, filename, O_PATH | O_CLOEXEC); require(raw >= 0);
   rejects([&] { (void)read_long_term_v2(raw, 28); }); close(raw);
   raw = openat(dir.fd, filename, O_WRONLY | O_CLOEXEC); require(raw >= 0);
   rejects([&] { (void)read_long_term_v2(raw, 28); }); close(raw);
   rejects([&] { (void)read_long_term_v2(dir.fd, 0); });
   require(r.remove());
  }
  {
   Temp dir; require(fchmod(dir.fd, 0755) == 0); rejects([&] { Record r(dir.fd); });
   require(fchmod(dir.fd, 0700) == 0);
   int lock = openat(dir.fd, ".lock", O_WRONLY | O_CREAT | O_CLOEXEC, 0600); require(lock >= 0);
   require(ftruncate(lock, 1) == 0); close(lock); rejects([&] { Record r(dir.fd); });
  }
  require(live == 0 && descriptors() == initial && zeroed_unmaps >= 5 && refused == 30);
  std::cout << "{\"real_private_file_transactions\":true,\"cross_process_readback\":true,"
    "\"atomic_no_replace\":true,\"partial_failure_cleanup\":true,\"uncertain_commit_preserved\":true,"
    "\"short_interrupted_io\":true,\"all_key_pages_zeroed_before_unmap\":true,"
    "\"no_descriptor_or_memory_leak\":true,\"refused_cases\":" << refused << ",\"zeroed_unmaps\":"
    << zeroed_unmaps << ",\"physical_key_generated\":false,\"cold_boot_reuse_proved\":false,"
    "\"boot_policy_admitted\":false}\n";
  return 0;
 } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}
