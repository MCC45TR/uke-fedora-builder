// SPDX-License-Identifier: MIT
#include "hwkm-disposable-record.hpp"
#include <sys/file.h>
#include <sys/random.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/syscall.h>
#include <linux/fs.h>
#include <fcntl.h>
#include <unistd.h>
#include <array>
#include <cerrno>
#include <cstring>
#include <stdexcept>
#include <string>
#include <system_error>

namespace uke::protected_boot::hwkm::disposable {
namespace {
constexpr char name[] = "disposable-key-v1";
constexpr std::array<unsigned char, 28> header = {
 'U','K','E','-','H','W','K','M','-','D','I','S','P','O','S','A','B','L','E','-','V','1',0,0,1,0,0,0};
constexpr size_t record_bytes = header.size() + wrapped_key_bytes;
[[noreturn]] void failed(const char* action) { throw std::system_error(errno, std::generic_category(), action); }
void require(bool value) { if (!value) throw std::runtime_error("Disposable key record rejected"); }
struct Fd {
 int value;
 explicit Fd(int fd) : value(fd) { if (value < 0) failed("Open disposable key record"); }
 ~Fd() { close(value); }
 Fd(const Fd&) = delete;
 Fd& operator=(const Fd&) = delete;
};
void private_file(int fd, off_t length) {
 struct stat st{};
 if (fstat(fd, &st) < 0) failed("Inspect disposable record");
 require(S_ISREG(st.st_mode) && (st.st_mode & 07777) == 0600 && st.st_uid == geteuid() &&
         st.st_nlink == 1 && st.st_size == length);
}
void write_at(int fd, const unsigned char* data, size_t bytes, off_t offset) {
 size_t done = 0;
 while (done < bytes) {
  const auto count = pwrite(fd, data + done, bytes - done, offset + static_cast<off_t>(done));
  if (count < 0 && errno == EINTR) continue;
  if (count < 0) failed("Write disposable record");
  require(count > 0);
  done += static_cast<size_t>(count);
 }
}
void header_at(int fd) {
 std::array<unsigned char, header.size()> value{};
 size_t done = 0;
 while (done < value.size()) {
  const auto count = pread(fd, value.data() + done, value.size() - done, static_cast<off_t>(done));
  if (count < 0 && errno == EINTR) continue;
  if (count < 0) failed("Read disposable record header");
  require(count > 0); done += static_cast<size_t>(count);
 }
 require(value == header);
}
std::string temporary_name() {
 std::array<unsigned char, 16> nonce{};
 size_t done = 0;
 while (done < nonce.size()) {
  const auto count = getrandom(nonce.data() + done, nonce.size() - done, 0);
  if (count < 0 && errno == EINTR) continue;
  if (count < 0) failed("Create disposable record name");
  require(count > 0); done += static_cast<size_t>(count);
 }
 std::string out = ".new-key-";
 constexpr char hex[] = "0123456789abcdef";
 for (const auto byte : nonce) { out += hex[byte >> 4]; out += hex[byte & 15]; }
 return out;
}
}
Record::Record(int parent) {
 directory_ = fcntl(parent, F_DUPFD_CLOEXEC, 3);
 if (directory_ < 0) failed("Pin disposable record directory");
 try {
  struct stat st{};
  if (fstat(directory_, &st) < 0) failed("Inspect disposable record directory");
  require(S_ISDIR(st.st_mode) && (st.st_mode & 07777) == 0700 && st.st_uid == geteuid());
  lock_ = openat(directory_, ".lock", O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (lock_ < 0) failed("Open disposable record lock");
  private_file(lock_, 0);
  if (flock(lock_, LOCK_EX | LOCK_NB) < 0) failed("Lock disposable record");
 } catch (...) {
  if (lock_ >= 0) close(lock_);
  close(directory_); directory_ = lock_ = -1; throw;
 }
}
Record::~Record() { if (lock_ >= 0) close(lock_); if (directory_ >= 0) close(directory_); }
bool Record::exists() const {
 struct stat st{};
 if (fstatat(directory_, name, &st, AT_SYMLINK_NOFOLLOW) == 0) return true;
 if (errno != ENOENT) failed("Inspect disposable record presence");
 return false;
}
void Record::create(const WrappedKey& key) {
 require(key.lifetime() == Lifetime::LongTerm && !exists());
 struct statvfs space{};
 if (fstatvfs(directory_, &space) < 0) failed("Inspect disposable record reserve");
 require(space.f_frsize > 0 && space.f_bavail > 0 &&
         space.f_bavail > (1048576U - 1) / space.f_frsize);
 const auto temporary = temporary_name();
 Fd output(openat(directory_, temporary.c_str(), O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600));
 bool renamed = false;
 try {
  if (fchmod(output.value, 0600) < 0) failed("Protect disposable record");
  private_file(output.value, 0);
  write_at(output.value, header.data(), header.size(), 0);
  const auto bytes = key.bytes();
  write_at(output.value, bytes.data(), bytes.size(), static_cast<off_t>(header.size()));
  private_file(output.value, record_bytes);
  if (fsync(output.value) < 0) failed("Sync disposable record");
  if (syscall(SYS_renameat2, directory_, temporary.c_str(), directory_, name, RENAME_NOREPLACE) < 0)
   failed("Commit disposable record");
  renamed = true;
  if (fsync(directory_) < 0) failed("Sync disposable record directory");
 } catch (...) {
  if (!renamed) {
   struct stat opened{}, present{};
   if (fstat(output.value, &opened) == 0 && fstatat(directory_, temporary.c_str(), &present, AT_SYMLINK_NOFOLLOW) == 0 &&
       opened.st_dev == present.st_dev && opened.st_ino == present.st_ino)
    (void)unlinkat(directory_, temporary.c_str(), 0);
  }
  throw;
 }
}
WrappedKey Record::read() const {
 Fd input(openat(directory_, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW));
 private_file(input.value, record_bytes);
 header_at(input.value);
 auto key = read_long_term_v2(input.value, header.size());
 private_file(input.value, record_bytes);
 return key;
}
bool Record::remove() {
 if (!exists()) return false;
 Fd input(openat(directory_, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW));
 private_file(input.value, record_bytes);
 header_at(input.value);
 struct stat opened{}, present{};
 if (fstat(input.value, &opened) < 0 || fstatat(directory_, name, &present, AT_SYMLINK_NOFOLLOW) < 0)
  failed("Revalidate disposable record removal");
 require(opened.st_dev == present.st_dev && opened.st_ino == present.st_ino);
 if (unlinkat(directory_, name, 0) < 0) failed("Remove disposable record");
 if (fsync(directory_) < 0) failed("Sync disposable record removal");
 return true;
}
}
