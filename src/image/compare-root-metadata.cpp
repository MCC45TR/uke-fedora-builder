// Compare real image readback metadata without following target symlinks.
#include <sys/stat.h>
#include <sys/xattr.h>
#include <array>
#include <cerrno>
#include <filesystem>
#include <iostream>
#include <optional>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;
using Attribute = std::optional<std::vector<unsigned char>>;

static struct stat metadata(const fs::path &path) {
    struct stat result {};
    if (lstat(path.c_str(), &result))
        throw std::runtime_error("Cannot stat: " + path.string());
    return result;
}

static Attribute attribute(const fs::path &path, const char *name) {
    const ssize_t size = lgetxattr(path.c_str(), name, nullptr, 0);
    if (size < 0) {
        if (errno == ENODATA) return std::nullopt;
        throw std::runtime_error("Cannot read attribute: " + path.string() + ": " + name);
    }
    std::vector<unsigned char> bytes(static_cast<size_t>(size));
    if (lgetxattr(path.c_str(), name, bytes.data(), bytes.size()) != size)
        throw std::runtime_error("Attribute changed during read: " + path.string());
    return bytes;
}

static std::set<std::string> paths(const fs::path &root) {
    std::set<std::string> result {"."};
    for (const auto &entry : fs::recursive_directory_iterator(root))
        result.insert(entry.path().lexically_relative(root).generic_string());
    return result;
}

int main(int argc, char **argv) {
    try {
        if (argc != 3)
            throw std::runtime_error("Usage: compare-root-metadata EXPECTED READBACK");
        auto root_path = [](const char *value) {
            auto result = fs::absolute(value);
            while (result != result.root_path() && result.filename().empty()) result = result.parent_path();
            return result;
        };
        const fs::path expected = root_path(argv[1]);
        const fs::path readback = root_path(argv[2]);
        if (!S_ISDIR(metadata(expected).st_mode) || !S_ISDIR(metadata(readback).st_mode))
            throw std::runtime_error("Both roots must be real directories");
        const auto expected_paths = paths(expected);
        if (expected_paths != paths(readback))
            throw std::runtime_error("Readback path inventory differs");
        constexpr std::array names {"security.capability", "system.posix_acl_access", "system.posix_acl_default"};
        size_t attributes = 0;
        for (const auto &relative : expected_paths) {
            const auto original = expected / relative;
            const auto actual = readback / relative;
            const auto left = metadata(original);
            const auto right = metadata(actual);
            if (left.st_mode != right.st_mode || left.st_uid != right.st_uid || left.st_gid != right.st_gid)
                throw std::runtime_error("Mode or owner differs: " + relative);
            if (left.st_mtim.tv_sec != right.st_mtim.tv_sec || left.st_mtim.tv_nsec != right.st_mtim.tv_nsec)
                throw std::runtime_error("Mtime differs: " + relative);
            if (S_ISLNK(left.st_mode)) {
                if (fs::read_symlink(original) != fs::read_symlink(actual))
                    throw std::runtime_error("Symlink differs: " + relative);
                continue; // Linux does not support POSIX ACLs or capabilities on symlinks.
            }
            for (const char *name : names) {
                const auto value = attribute(original, name);
                if (value != attribute(actual, name))
                    throw std::runtime_error("Attribute differs: " + relative + ": " + name);
                if (value) ++attributes;
            }
        }
        std::cout << "Compared " << expected_paths.size() << " paths and " << attributes
                  << " explicit ACL/capability attributes\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
