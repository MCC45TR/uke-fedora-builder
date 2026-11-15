// SPDX-License-Identifier: MIT
// Production parser with MINK API/provider-fact doubles. No secure-world call.
#include "qtee-tpm-discovery.hpp"
#include <MinkCom.h>
#include <linux/tee.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <array>
#include <cerrno>
#include <cstdarg>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <set>
#include <stdexcept>
#include <string_view>

#ifndef __aarch64__
#error Native AArch64 qualification required
#endif
using namespace uke::protected_boot::qtee_tpm;
extern "C" int __real_fstat(int, struct stat*);
extern "C" int __real_close(int);
namespace {
void need(bool value) { if (!value) throw std::runtime_error("QTEE fixture assertion"); }
enum class Fault { None, NotCharacter, BadOwner, Writable, WrongAdapter, AdapterSymlink,
 WrongProvider, MissingObjects, VersionIoctl, RootRefused, RootNull, CredentialsRefused,
 CredentialsNull, ServiceRefused, ServiceNull, ServiceInput, QueryRefused, VersionStatus,
 VersionEcho, ShortOutput, OversizeOutput, ChangedPointer, ChangedInput, ChangedLocality,
 TypeStatus, TypeEcho, UnknownType, ReleaseRoot, ReleaseEnvironment, ReleaseService };
Fault fault = Fault::None;
int owned = -1;
std::set<std::uintptr_t> live;
size_t closes = 0, queries = 0, roots = 0, credentials = 0, refused = 0;
std::uint32_t type = 0x6654504d;
std::uint32_t word(const void* p) {
 const auto* b = static_cast<const unsigned char*>(p);
 return std::uint32_t(b[0]) | std::uint32_t(b[1]) << 8 | std::uint32_t(b[2]) << 16 | std::uint32_t(b[3]) << 24;
}
void put(void* p, size_t at, std::uint32_t value) {
 auto* b = static_cast<unsigned char*>(p);
 for (unsigned i = 0; i < 4; ++i) b[at+i] = value >> (i*8);
}
size_t fds() { DIR* d = opendir("/proc/self/fd"); need(d); size_t n = 0; while (readdir(d)) ++n; closedir(d); return n; }
int32_t invoke(ObjectCxt context, ObjectOp op, ObjectArg* a, ObjectCounts count);
Object object(std::uintptr_t value) { need(live.insert(value).second); return {invoke, reinterpret_cast<void*>(value)}; }
int32_t invoke(ObjectCxt context, ObjectOp op, ObjectArg* a, ObjectCounts count) {
 const auto id = reinterpret_cast<std::uintptr_t>(context);
 need(live.contains(id));
 if (op == 65535) {
  need(!a && !count && live.erase(id) == 1);
  return (id == 1 && fault == Fault::ReleaseRoot) || (id == 2 && fault == Fault::ReleaseEnvironment) ||
         (id == 3 && fault == Fault::ReleaseService) ? 9 : 0;
 }
 if (id == 2) {
  need(op == 0 && count == 0x1001 && word(a[0].bi.ptr) == 81 && a[0].bi.size == 4 && Object_isNull(a[1].o));
  if (fault == Fault::ServiceRefused) return 10;
  if (fault != Fault::ServiceNull) a[1].o = object(3);
  if (fault == Fault::ServiceInput) a[0].bi.size = 3;
  return 0;
 }
 need(id == 3 && op == 0 && count == 0x12 && a[0].bi.size == 1 &&
      !*static_cast<const unsigned char*>(a[0].bi.ptr) && a[1].bi.size == 4 && a[2].b.size == 12);
 const auto command = word(a[1].bi.ptr);
 need(command == (++queries == 1 ? 0x1000u : 0x80000u) && queries <= 2);
 if (fault == Fault::QueryRefused) return -96;
 void* response = a[2].b.ptr;
 if (queries == 1) { put(response, 0, fault == Fault::VersionStatus ? 1 : 0); put(response, 4, fault == Fault::VersionEcho ? 3 : 0x1000); put(response, 8, 0x00050002); }
 else { put(response, 0, fault == Fault::TypeEcho ? 3 : 0x80000); put(response, 4, fault == Fault::TypeStatus ? 1 : 0); put(response, 8, fault == Fault::UnknownType ? 0 : type); }
 if (fault == Fault::ShortOutput) a[2].b.size = 11;
 if (fault == Fault::OversizeOutput) a[2].b.size = 13;
 if (fault == Fault::ChangedPointer) a[2].b.ptr = nullptr;
 if (fault == Fault::ChangedInput) a[1].bi.size = 3;
 if (fault == Fault::ChangedLocality) *const_cast<unsigned char*>(static_cast<const unsigned char*>(a[0].bi.ptr)) = 1;
 return 0;
}
void facts(struct stat* st) {
 st->st_mode = S_IFCHR | 0600; st->st_uid = 0;
 if (fault == Fault::NotCharacter) st->st_mode = S_IFREG | 0600;
 if (fault == Fault::BadOwner) st->st_uid = 1000;
 if (fault == Fault::Writable) st->st_mode |= 0020;
}
}
extern "C" int MinkCom_getRootEnvObject(Object* out) {
 need(++roots == 1 && live.empty() && Object_isNull(*out));
 if (fault == Fault::RootRefused) return -96;
 if (fault != Fault::RootNull) *out = object(1);
 return 0;
}
extern "C" int MinkCom_getClientEnvObject(Object root, Object* out) {
 need(++credentials == 1 && live.contains(1) && root.context == reinterpret_cast<void*>(1) && Object_isNull(*out));
 if (fault == Fault::CredentialsRefused) return 10;
 if (fault != Fault::CredentialsNull) *out = object(2);
 return 0;
}
extern "C" int __wrap_fstat(int fd, struct stat* st) {
 const int status = __real_fstat(fd, st); if (!status && fd == owned) facts(st); return status;
}
extern "C" int __wrap_lstat(const char* path, struct stat* st) {
 need(std::string_view(path) == "/dev/tee0");
 const int status = __real_fstat(owned, st); facts(st);
 if (fault == Fault::WrongAdapter) ++st->st_ino;
 if (fault == Fault::AdapterSymlink) st->st_mode = S_IFLNK | 0777;
 return status;
}
extern "C" int __wrap_close(int fd) {
 if (fd == owned) { owned = -1; ++closes; }
 return __real_close(fd);
}
extern "C" int __wrap_ioctl(int fd, unsigned long op, ...) {
 need(fd == owned && op == TEE_IOC_VERSION);
 va_list args; va_start(args, op); auto* v = va_arg(args, tee_ioctl_version_data*); va_end(args);
 if (fault == Fault::VersionIoctl) { errno = EINTR; return -1; }
 v->impl_id = fault == Fault::WrongProvider ? 1 : 4;
 v->gen_caps = fault == Fault::MissingObjects ? 0 : 16;
 return 0;
}
int main() {
 char path[] = "/tmp/uke-qtee-fixture.XXXXXX";
 const int seed = mkstemp(path); need(seed >= 0); close(seed);
 try {
  auto run = [&](Fault value, int flags = O_RDWR | O_CLOEXEC) {
   need(live.empty() && owned == -1); fault = value;
   closes = queries = roots = credentials = 0;
   const auto before = fds(); owned = open(path, flags); need(owned >= 3);
   const char* phase = "test"; bool rejected = false;
   Information info;
   try { info = inspect_owned_provider(owned, phase); } catch (const std::exception&) { rejected = true; }
   need(owned == -1 && closes == 1 && live.empty() && fds() == before);
   if (value == Fault::None && flags == (O_RDWR | O_CLOEXEC)) {
    need(!rejected && queries == 2 && roots == 1 && credentials == 1 && info.major == 5 && info.minor == 2 && info.information_queries == 2);
    need(info.kind == (type == 0x6654504d ? Kind::Firmware : type == 0x6454504d ? Kind::Discrete : Kind::None));
   } else { need(rejected); ++refused; }
  };
  for (const auto value : {0x6654504du, 0x6454504du, 0x4e6f6e65u}) { type = value; run(Fault::None); }
  for (unsigned value = 1; value <= static_cast<unsigned>(Fault::ReleaseService); ++value) run(static_cast<Fault>(value));
  run(Fault::None, O_RDONLY | O_CLOEXEC); run(Fault::None, O_RDWR);
  unlink(path);
  std::cout << "{\"production_parser_tested\":true,\"mink_api_and_provider_facts_doubled\":true,"
    "\"three_tpm_types_checked\":true,\"fixed_queries_only\":true,\"no_handle_leak\":true,\"refused_cases\":" << refused <<
    ",\"physical_tpm_found\":false,\"credential_firmware_acceptance_proved\":false,\"sealed_release_proved\":false}\n";
 } catch (...) { unlink(path); throw; }
}
