// SPDX-License-Identifier: MIT
// One-shot fixed TPM-TA information queries; no TPM registration or startup.
#include "qtee-tpm-discovery.hpp"
#include "protected-physical-cohort.hpp"
#include <systemd/sd-device.h>
#include <nlohmann/json.hpp>
#include <linux/openat2.h>
#include <linux/tee.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <signal.h>
#include <cerrno>
#include <memory>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>

namespace {
using namespace uke::protected_boot;
[[noreturn]] void reject() { throw std::runtime_error("QTEE TPM probe rejected"); }
struct Fd {
    int value = -1;
    explicit Fd(int fd) : value(fd) { if (fd < 0) reject(); }
    ~Fd() { if (value >= 0) close(value); }
    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;
    int transfer() { const int result = value; value = -1; return result; }
};
size_t descriptors() {
    DIR* directory = opendir("/proc/self/fd");
    if (!directory) reject();
    size_t count = 0; while (readdir(directory)) ++count;
    closedir(directory); return count;
}
void deadline(int) {
    constexpr char message[] = "UKE_QTEE_TPM_PROBE_TIMEOUT\n";
    (void)!write(STDERR_FILENO, message, sizeof(message) - 1);
    // Process exit closes the exclusive TEE context even when an interrupted
    // request leaves its object ownership uncertain. No retries are made.
    _exit(124);
}
int select_provider() {
    sd_device_enumerator* raw = nullptr;
    if (sd_device_enumerator_new(&raw) < 0) reject();
    std::unique_ptr<sd_device_enumerator, decltype(&sd_device_enumerator_unref)> enumerate(raw, sd_device_enumerator_unref);
    if (sd_device_enumerator_add_match_subsystem(raw, "tee", 1) < 0) reject();
    Fd dev(open("/dev", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    int selected = -1;
    size_t count = 0;
    try {
        for (auto* item = sd_device_enumerator_get_device_first(raw); item;
             item = sd_device_enumerator_get_device_next(raw)) {
            if (++count > 32) reject();
            const char* name = nullptr;
            if (sd_device_get_sysname(item, &name) < 0 || !name) reject();
            const std::string_view simple(name);
            // Never open the privileged supplicant or arbitrary service nodes.
            if (!simple.starts_with("tee") || simple.size() < 4 || simple.size() > 7 ||
                simple.substr(3).find_first_not_of("0123456789") != simple.npos) continue;
            const char* path = nullptr; const char* syspath = nullptr; dev_t number{};
            if (sd_device_get_devname(item, &path) < 0 || sd_device_get_syspath(item, &syspath) < 0 ||
                sd_device_get_devnum(item, &number) < 0 || !path || !syspath ||
                std::string(path) != "/dev/" + std::string(simple) ||
                !std::string_view(syspath).starts_with("/sys/devices/")) reject();
            struct open_how how{};
            how.flags = O_RDWR | O_CLOEXEC;
            how.resolve = RESOLVE_BENEATH | RESOLVE_NO_SYMLINKS | RESOLVE_NO_MAGICLINKS;
            Fd candidate(static_cast<int>(syscall(SYS_openat2, dev.value, name, &how, sizeof(how))));
            struct stat st{};
            if (fstat(candidate.value, &st) || !S_ISCHR(st.st_mode) || st.st_rdev != number) reject();
            tee_ioctl_version_data version{};
            if (ioctl(candidate.value, TEE_IOC_VERSION, &version)) reject();
            if (version.impl_id != TEE_IMPL_ID_QTEE) continue;
            if (!(version.gen_caps & TEE_GEN_CAP_OBJREF) || selected >= 0) reject();
            selected = candidate.transfer();
        }
        if (selected < 0) reject();
        return selected;
    } catch (...) { if (selected >= 0) close(selected); throw; }
}
nlohmann::json inspect(const char*& phase, std::string_view mode) {
    phase = "physical-owner";
    auto physical = open_physical_boot_devices();
    phase = "qtee-provider-selection";
    Fd provider(select_provider());
    if (mode == "--keymaster-storage") {
        const auto storage = qtee_tpm::exercise_keymaster_storage(provider.transfer(), phase);
        phase = "physical-owner-after";
        physical.revalidate();
        return {{"schema_version", 1}, {"physical_ufs_topology_verified", true},
            {"qtee_provider_verified", true}, {"application", "keymaster64"},
            {"disposable_storage_key_generation", true}, {"record_flushed_and_read", true},
            {"long_term_bytes", storage.long_term_bytes}, {"ephemeral_bytes", storage.ephemeral_bytes},
            {"altered_blob_refused", true}, {"objects_released", true}};
    }
    if (mode == "--keymaster-version") {
        const auto version = qtee_tpm::inspect_keymaster_owned_provider(provider.transfer(), phase);
        phase = "physical-owner-after";
        physical.revalidate();
        return {{"schema_version", 1}, {"physical_ufs_topology_verified", true},
            {"qtee_provider_verified", true}, {"application", "keymaster64"},
            {"hal_major", version.hal_major}, {"hal_minor", version.hal_minor},
            {"app_major", version.app_major}, {"app_minor", version.app_minor},
            {"fixed_version_queries", 1}, {"objects_released", true}};
    }
    const auto information = qtee_tpm::inspect_owned_provider(provider.transfer(), phase);
    phase = "physical-owner-after";
    physical.revalidate();
    const char* type = information.kind == qtee_tpm::Kind::Firmware ? "ftpm" :
        information.kind == qtee_tpm::Kind::Discrete ? "dtpm" : "none";
    return {{"schema_version", 1}, {"physical_ufs_topology_verified", true},
        {"qtee_provider_verified", true}, {"tpm_service_responded", true},
        {"reported_tpm_type", type}, {"ta_version_major", information.major},
        {"ta_version_minor", information.minor},
        {"userspace_credential_callback", true}, {"privileged_null_credential", false},
        {"fixed_vendor_information_queries", 2}, {"tpm2_commands_sent", 0},
        {"startup_clear_or_nv_write_requested", false}, {"driver_or_module_loaded", false},
        {"objects_released", true}, {"measured_boot_proved", false},
        {"sealed_release_proved", false}, {"automatic_unlock_proved", false}};
}
}
int main(int argc, char** argv) {
    if (argc != 2) return 2;
    const std::string_view mode(argv[1]);
    const bool keymaster = mode == "--keymaster-version" || mode == "--keymaster-storage";
    if (!keymaster && mode != "--inspect") return 2;
    const char* rejection = keymaster ? "UKE_QTEE_KEYMASTER_PROBE_REJECTED" : "UKE_QTEE_TPM_PROBE_REJECTED";
    const char* phase = "root-required";
    try {
        if (geteuid() != 0) reject();
        phase = "deadline-setup";
        struct sigaction action{};
        action.sa_handler = deadline;
        sigemptyset(&action.sa_mask);
        if (sigaction(SIGALRM, &action, nullptr)) reject();
        alarm(5);
        const auto initial = descriptors();
        auto report = inspect(phase, mode);
        phase = "owned-handle-release";
        if (descriptors() != initial) reject();
        struct rusage usage{};
        if (getrusage(RUSAGE_SELF, &usage)) reject();
        alarm(0);
        report["owned_handles_released"] = true;
        report["peak_rss_kib"] = usage.ru_maxrss;
        std::cout << report.dump() << '\n';
        return !keymaster && report.at("reported_tpm_type") == "none" ? 77 : 0;
    } catch (const qtee_tpm::RemoteRefusal& error) {
        alarm(0);
        std::cerr << rejection << " stage=" << phase << " remote=" << error.result << '\n';
        // This says only that service lookup was refused, not that firmware
        // lacks a TPM. Credentials and service admission may differ by model.
        return std::string_view(phase) == "qtee-tpm-service-open" ? 77 : 1;
    } catch (const std::system_error& error) {
        alarm(0);
        std::cerr << rejection << " stage=" << phase << " errno=" << error.code().value() << '\n';
        return 1;
    } catch (const std::exception&) {
        alarm(0);
        std::cerr << rejection << " stage=" << phase << '\n'; return 1;
    }
}
