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
#include <cstring>
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
 TypeStatus, TypeEcho, UnknownType, ReleaseRoot, ReleaseEnvironment, ReleaseService,
 ClientRefused, NameRefused, HalRefused, NameNull, ChangedName, KeymasterQueryRefused,
 KeymasterShort, KeymasterOversize, KeymasterEmpty, KeymasterPartial, KeymasterStatus,
 KeymasterPointer, KeymasterInput, KeymasterOldMajor, ReleaseOpener,
 StorageGenerateStatus, StorageOversizeResponse, StorageBadMap, StorageBadCertCount,
 StorageBadEphemeral, StorageTamperAccepted };
Fault fault = Fault::None;
bool keymaster = false;
bool storage = false;
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
int32_t invoke_keymaster_storage(ObjectArg* args) {
 constexpr unsigned char generate_request[]{
  0x08, 0x31, 0, 0, 0xa6, 22, 5,
  0x1a, 0x10, 0, 0, 2, 0x18, 32,
  0x1a, 0x30, 0, 0, 3, 0x19, 1, 0,
  0x1a, 0x20, 0, 0, 1, 0,
  0x1a, 0x20, 0, 0, 1, 1,
  0x1a, 0x70, 0, 2, 0xd2, 1,
 };
 constexpr unsigned char convert_request[]{0x1d,0x31,0,0,0xa1,23,0x44,0x11,0x22,0x33,0x44};
 auto* response = static_cast<unsigned char*>(args[1].b.ptr);
 need(args[1].b.size == 8192);
 if (queries == 2) {
  need(args[0].bi.size == sizeof(generate_request) &&
       !std::memcmp(args[0].bi.ptr, generate_request, sizeof(generate_request)));
  const unsigned char cbor[]{0xa2,23,0x44,0x11,0x22,0x33,0x44,0x18,32,0};
  put(response, 0, fault == Fault::StorageGenerateStatus ? static_cast<std::uint32_t>(-38) : 0);
  put(response, 4, fault == Fault::StorageOversizeResponse ? 8192 : sizeof(cbor));
  std::memcpy(response + 8, cbor, sizeof(cbor));
  if (fault == Fault::StorageBadMap) response[8] = 0x83;
  if (fault == Fault::StorageBadCertCount) response[17] = 1;
 } else if (queries == 3) {
  need(args[0].bi.size == sizeof(convert_request) &&
      !std::memcmp(args[0].bi.ptr, convert_request, sizeof(convert_request)));
  const unsigned char cbor[]{0xa1,0x18,36,0x44,0x66,0x77,0x88,0x99};
  put(response, 0, 0);
  put(response, 4, sizeof(cbor));
  std::memcpy(response + 8, cbor, sizeof(cbor));
  if (fault == Fault::StorageBadEphemeral) response[10] = 37;
 } else {
  need(queries == 4 && args[0].bi.size == sizeof(convert_request));
  const auto* bytes = static_cast<const unsigned char*>(args[0].bi.ptr);
  need(!std::memcmp(bytes, convert_request, 9) && bytes[9] == (convert_request[9] ^ 1) && bytes[10] == convert_request[10]);
  put(response, 0, fault == Fault::StorageTamperAccepted ? 0 : static_cast<std::uint32_t>(-33));
 }
 return 0;
}
int32_t invoke_keymaster(std::uintptr_t id, ObjectOp op, ObjectArg* args, ObjectCounts count) {
 need(op == 0);
 if (id < 5) {
  need(count == 0x1001 && Object_isNull(args[1].o));
  if (id == 3) {
   need(std::string_view(static_cast<const char*>(args[0].bi.ptr), args[0].bi.size) == "keymaster64");
   if (fault == Fault::NameNull) return 0;
   if (fault == Fault::ChangedName)
    *const_cast<char*>(static_cast<const char*>(args[0].bi.ptr)) = 'x';
  } else {
   need(args[0].bi.size == 4 && word(args[0].bi.ptr) == (id == 2 ? 0x97 : 150));
  }
  args[1].o = object(id + 1);
  // Even a refusal with a returned object must release that object.
  return (id == 2 && fault == Fault::ClientRefused) || (id == 3 && fault == Fault::NameRefused) ||
         (id == 4 && fault == Fault::HalRefused) ? 11 : 0;
 }
 need(id == 5 && count == 0x11);
 if (++queries > 1) {
  need(storage);
  return invoke_keymaster_storage(args);
 }
 need(
      args[0].bi.size == 4 && word(args[0].bi.ptr) == 0x200 && args[1].b.size == 20);
 if (fault == Fault::KeymasterQueryRefused) return -96;
 if (fault == Fault::KeymasterEmpty) return 0;
 void* response = args[1].b.ptr;
 put(response, 0, fault == Fault::KeymasterStatus ? 11 : 0);
 put(response, 4, storage ? 5 : fault == Fault::KeymasterOldMajor ? 1 : 4);
 put(response, 8, storage ? 3 : 1);
 put(response, 12, 5);
 if (fault != Fault::KeymasterPartial) put(response, 16, storage ? 3000 : 3);
 if (fault == Fault::KeymasterShort) args[1].b.size = 19;
 if (fault == Fault::KeymasterOversize) args[1].b.size = 21;
 if (fault == Fault::KeymasterPointer) args[1].b.ptr = nullptr;
 if (fault == Fault::KeymasterInput) args[0].bi.size = 3;
 return 0;
}
int32_t invoke(ObjectCxt context, ObjectOp op, ObjectArg* a, ObjectCounts count) {
 const auto id = reinterpret_cast<std::uintptr_t>(context);
 need(live.contains(id));
 if (op == 65535) {
  need(!a && !count && live.erase(id) == 1);
  return (id == 1 && fault == Fault::ReleaseRoot) || (id == 2 && fault == Fault::ReleaseEnvironment) ||
         (id == 3 && fault == Fault::ReleaseService) || (id == 4 && fault == Fault::ReleaseOpener) ? 9 : 0;
 }
 if (keymaster) return invoke_keymaster(id, op, a, count);
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
  keymaster = true;
  unsigned keymaster_refused = 0;
  auto run_keymaster = [&](Fault value) {
   need(live.empty() && owned == -1);
   fault = value;
   closes = queries = roots = credentials = 0;
   const auto before = fds();
   owned = open(path, O_RDWR | O_CLOEXEC);
   need(owned >= 3);
   const char* phase = "test";
   bool rejected = false;
   KeymasterVersion version{};
   try { version = inspect_keymaster_owned_provider(owned, phase); }
   catch (const std::exception&) { rejected = true; }
   need(owned == -1 && closes == 1 && live.empty() && fds() == before && roots == 1 && credentials == 1);
   if (value == Fault::None) {
    need(!rejected && queries == 1 && version.hal_major == 4 && version.hal_minor == 1 &&
         version.app_major == 5 && version.app_minor == 3);
   } else {
    need(rejected && queries == (value < Fault::KeymasterQueryRefused ? 0 : 1));
    ++keymaster_refused;
   }
  };
  run_keymaster(Fault::None);
  for (unsigned value = static_cast<unsigned>(Fault::ClientRefused);
       value <= static_cast<unsigned>(Fault::ReleaseOpener); ++value)
   run_keymaster(static_cast<Fault>(value));
  storage = true;
  unsigned storage_refused = 0;
  auto run_storage = [&](Fault value, unsigned expected_calls) {
   need(live.empty() && owned == -1);
   fault = value;
   closes = queries = roots = credentials = 0;
   const auto before = fds();
   owned = open(path, O_RDWR | O_CLOEXEC);
   need(owned >= 3);
   const char* phase = "test";
   bool rejected = false;
   KeymasterStorageResult info{};
   try { info = exercise_keymaster_storage(owned, phase); }
   catch (const std::exception&) { rejected = true; }
   need(owned == -1 && closes == 1 && live.empty() && fds() == before && queries == expected_calls);
   if (value == Fault::None) need(!rejected && info.long_term_bytes == 4 && info.ephemeral_bytes == 4);
   else { need(rejected); ++storage_refused; }
  };
  run_storage(Fault::None, 4);
  run_storage(Fault::StorageGenerateStatus, 2);
  run_storage(Fault::StorageOversizeResponse, 2);
  run_storage(Fault::StorageBadMap, 2);
  run_storage(Fault::StorageBadCertCount, 2);
  run_storage(Fault::StorageBadEphemeral, 3);
  run_storage(Fault::StorageTamperAccepted, 4);
  unlink(path);
  std::cout << "{\"production_parser_tested\":true,\"mink_api_and_provider_facts_doubled\":true,"
    "\"three_tpm_types_checked\":true,\"fixed_queries_only\":true,\"no_handle_leak\":true,\"refused_cases\":" << refused <<
    ",\"keymaster_fixed_version_checked\":true,\"keymaster_refused_cases\":" << keymaster_refused <<
    ",\"keymaster_storage_rpc_checked\":true,\"keymaster_storage_refused_cases\":" << storage_refused <<
    ",\"physical_tpm_found\":false,\"credential_firmware_acceptance_proved\":false,\"sealed_release_proved\":false}\n";
 } catch (...) { unlink(path); throw; }
}
