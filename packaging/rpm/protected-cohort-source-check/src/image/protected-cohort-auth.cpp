// SPDX-License-Identifier: MIT
// Read-only signature primitive for the future native protected-boot policy.
#include "protected-cohort-auth.hpp"
#include <openssl/bio.h>
#include <openssl/bn.h>
#include <openssl/core_names.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rsa.h>
#include <openssl/x509.h>
#include <linux/openat2.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <fcntl.h>
#include <algorithm>
#include <array>
#include <cerrno>
#include <cstring>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string_view>
#ifdef UKE_COHORT_AUTH_CLI
#include <iostream>
#endif

namespace uke::protected_boot {
namespace {
constexpr std::string_view domain = "UKE-PROTECTED-COHORT-v1\n";
constexpr size_t key_limit = 8192, payload_limit = 65536, signature_size = 512;
[[noreturn]] void refuse() { throw std::runtime_error("Cohort signature input rejected"); }
struct Fd {
    int value;
    explicit Fd(int descriptor) : value(descriptor) {}
    ~Fd() { if (value >= 0) close(value); }
    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;
};
bool unchanged(const struct stat& a, const struct stat& b) {
    return a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode &&
           a.st_size == b.st_size && a.st_mtim.tv_sec == b.st_mtim.tv_sec &&
           a.st_mtim.tv_nsec == b.st_mtim.tv_nsec && a.st_ctim.tv_sec == b.st_ctim.tv_sec &&
           a.st_ctim.tv_nsec == b.st_ctim.tv_nsec;
}
std::vector<unsigned char> read_regular(const std::string& path, size_t limit) {
    if (path.empty() || path.size() > 4096 || path.find('\0') != std::string::npos) refuse();
    const struct open_how how = {
        .flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
        .mode = 0,
        .resolve = RESOLVE_NO_SYMLINKS | RESOLVE_NO_MAGICLINKS,
    };
    // No fallback to a path-based open with weaker resolution guarantees.
    Fd fd{static_cast<int>(syscall(SYS_openat2, AT_FDCWD, path.c_str(), &how, sizeof(how)))};
    struct stat before{}, after{};
    if (fd.value < 0 || fstat(fd.value, &before) || !S_ISREG(before.st_mode) ||
        before.st_size <= 0 || static_cast<uint64_t>(before.st_size) > limit) refuse();
    std::vector<unsigned char> result(static_cast<size_t>(before.st_size));
    size_t offset = 0;
    while (offset < result.size()) {
        const auto count = pread(fd.value, result.data() + offset, result.size() - offset,
                                 static_cast<off_t>(offset));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) refuse();
        offset += static_cast<size_t>(count);
    }
    if (fstat(fd.value, &after) || !unchanged(before, after)) refuse();
    return result;
}
std::string sha256(const unsigned char* data, size_t size) {
    std::array<unsigned char, 32> digest{};
    size_t written = 0;
    if (EVP_Q_digest(nullptr, "SHA256", nullptr, data, size, digest.data(), &written) != 1 ||
        written != digest.size()) refuse();
    constexpr char hex[] = "0123456789abcdef";
    std::string result;
    result.reserve(64);
    for (const auto byte : digest) { result += hex[byte >> 4]; result += hex[byte & 15]; }
    return result;
}
bool whitespace(unsigned char value) {
    return value == ' ' || value == '\t' || value == '\r' || value == '\n';
}
int no_password(char*, int, int, void*) { return 0; }
}

std::vector<unsigned char> read_cohort_metadata_file(const std::string& path, size_t maximum_bytes) {
    if (!maximum_bytes || maximum_bytes > payload_limit) refuse();
    return read_regular(path, maximum_bytes);
}

VerifiedCohortBytes verify_cohort_signature_bytes(std::span<const unsigned char> pem,
                                                const std::string& trusted_spki_sha256,
                                                std::span<const unsigned char> payload,
                                                std::span<const unsigned char> signature) {
    if (trusted_spki_sha256.size() != 64 ||
        trusted_spki_sha256.find_first_not_of("0123456789abcdef") != std::string::npos) refuse();
    if (pem.empty() || pem.size() > key_limit || payload.size() <= domain.size() ||
        payload.size() > payload_limit || signature.size() != signature_size ||
        std::memcmp(payload.data(), domain.data(), domain.size())) refuse();
    constexpr std::string_view header = "-----BEGIN PUBLIC KEY-----\n";
    if (pem.size() < header.size() || std::memcmp(pem.data(), header.data(), header.size())) refuse();
    std::unique_ptr<BIO, decltype(&BIO_free)> input(
        BIO_new_mem_buf(pem.data(), static_cast<int>(pem.size())), BIO_free);
    if (!input) refuse();
    std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)> key(
        PEM_read_bio_PUBKEY(input.get(), nullptr, no_password, nullptr), EVP_PKEY_free);
    if (!key || EVP_PKEY_base_id(key.get()) != EVP_PKEY_RSA ||
        EVP_PKEY_get_bits(key.get()) != 4096 || EVP_PKEY_get_size(key.get()) != static_cast<int>(signature_size)) refuse();
    char tail;
    while (BIO_read(input.get(), &tail, 1) == 1)
        if (!whitespace(static_cast<unsigned char>(tail))) refuse();
    std::unique_ptr<EVP_PKEY_CTX, decltype(&EVP_PKEY_CTX_free)> public_check(
        EVP_PKEY_CTX_new_from_pkey(nullptr, key.get(), nullptr), EVP_PKEY_CTX_free);
    if (!public_check || EVP_PKEY_public_check(public_check.get()) != 1) refuse();
    BIGNUM* exponent_raw = nullptr;
    if (EVP_PKEY_get_bn_param(key.get(), OSSL_PKEY_PARAM_RSA_E, &exponent_raw) != 1) refuse();
    std::unique_ptr<BIGNUM, decltype(&BN_free)> exponent(exponent_raw, BN_free);
    if (!exponent || !BN_is_word(exponent.get(), 65537)) refuse();
    const int encoded_size = i2d_PUBKEY(key.get(), nullptr);
    if (encoded_size <= 0 || static_cast<size_t>(encoded_size) > key_limit) refuse();
    std::vector<unsigned char> spki(static_cast<size_t>(encoded_size));
    auto* cursor = spki.data();
    if (i2d_PUBKEY(key.get(), &cursor) != encoded_size || cursor != spki.data() + spki.size()) refuse();
    const auto key_digest = sha256(spki.data(), spki.size());
    if (key_digest != trusted_spki_sha256) refuse();
    std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> context(EVP_MD_CTX_new(), EVP_MD_CTX_free);
    EVP_PKEY_CTX* parameters = nullptr;
    if (!context || EVP_DigestVerifyInit(context.get(), &parameters, EVP_sha256(), nullptr, key.get()) != 1 ||
        !parameters || EVP_PKEY_CTX_set_rsa_padding(parameters, RSA_PKCS1_PSS_PADDING) <= 0 ||
        EVP_PKEY_CTX_set_rsa_mgf1_md(parameters, EVP_sha256()) <= 0 ||
        EVP_PKEY_CTX_set_rsa_pss_saltlen(parameters, 32) <= 0 ||
        EVP_DigestVerify(context.get(), signature.data(), signature.size(), payload.data(), payload.size()) != 1)
        refuse();
    const auto payload_digest = sha256(payload.data(), payload.size());
    return {std::vector<unsigned char>(payload.begin(), payload.end()), payload_digest, key_digest};
}

VerifiedCohortBytes verify_cohort_signature(const std::string& public_key_path,
                                          const std::string& trusted_spki_sha256,
                                          const std::string& payload_path,
                                          const std::string& signature_path) {
    const auto key = read_regular(public_key_path, key_limit);
    const auto payload = read_regular(payload_path, payload_limit);
    const auto signature = read_regular(signature_path, signature_size);
    return verify_cohort_signature_bytes(key, trusted_spki_sha256, payload, signature);
}
}

#ifdef UKE_COHORT_AUTH_CLI
// COPR fixture/inspection entry only; never installed as the admission policy.
int main(int argc, char** argv) {
    if (argc != 5) return 2;
    try {
        const auto result = uke::protected_boot::verify_cohort_signature(argv[1], argv[2], argv[3], argv[4]);
        std::cout << "{\"signature_verified\":true,\"payload_sha256\":\"" << result.payload_sha256()
                  << "\",\"signer_spki_sha256\":\"" << result.signer_spki_sha256()
                  << "\",\"manifest_semantics_admitted\":false,\"role_admitted\":false,"
                     "\"snapshot_authenticated\":false,\"hardware_trust_qualified\":false}\n";
        return 0;
    } catch (const std::exception&) {
        std::cerr << "UKE_COHORT_SIGNATURE_REJECTED\n";
        return 1;
    }
}
#endif
