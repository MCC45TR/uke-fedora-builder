// Host-only offline SELinux labels. Preserve Fedora ownership, modes and xattrs.
#include <ext2fs/ext2fs.h>
#include <selinux/label.h>
#include <selinux/selinux.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <array>
#include <cerrno>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>

namespace fs = std::filesystem;
static void check(errcode_t code, const char *operation) {
    if (code) throw std::runtime_error(std::string(operation) + ": " + error_message(code));
}
int main(int argc, char **argv) {
    try {
        if (argc != 5 || (std::strcmp(argv[1], "apply") && std::strcmp(argv[1], "verify")))
            throw std::runtime_error("Usage: ext4-labels apply|verify IMAGE ROOT FILE_CONTEXTS");
        struct stat image_stat {};
        if (lstat(argv[2], &image_stat) || !S_ISREG(image_stat.st_mode))
            throw std::runtime_error("Image must be a regular file, never a symlink or block device");
        const bool write = !std::strcmp(argv[1], "apply");
        ext2_filsys image = nullptr;
        check(ext2fs_open(argv[2], (write ? EXT2_FLAG_RW : 0) | EXT2_FLAG_64BITS,
                          0, 0, unix_io_manager, &image), "open ext4");
        selinux_opt options[] = {{SELABEL_OPT_PATH, argv[4]}};
        selabel_handle *labels = selabel_open(SELABEL_CTX_FILE, options, 1);
        if (!labels) throw std::runtime_error("Cannot load the target file-context policy");
        const fs::path root = fs::canonical(argv[3]);
        unsigned long count = 0;
        auto visit = [&](const std::string &path, const fs::path &source, bool generated) {
            ext2_ino_t number;
            check(ext2fs_namei(image, EXT2_ROOT_INO, EXT2_ROOT_INO, path.c_str(), &number), "resolve inode");
            ext2_inode inode {};
            check(ext2fs_read_inode(image, number, &inode), "read inode");
            if (!generated) {
                struct stat original {};
                if (lstat(source.c_str(), &original)) throw std::runtime_error("Cannot stat source");
                if (inode.i_mode != original.st_mode || inode_uid(inode) != original.st_uid ||
                    inode_gid(inode) != original.st_gid)
                    throw std::runtime_error("Ownership or mode differs at " + path);
            }
            char *context = nullptr;
            if (selabel_lookup_raw(labels, &context, path.c_str(), inode.i_mode))
                throw std::runtime_error("Policy has no context for " + path);
            ext2_xattr_handle *attrs = nullptr;
            check(ext2fs_xattrs_open(image, number, &attrs), "open xattrs");
            check(ext2fs_xattrs_read(attrs), "read xattrs");
            if (!generated) {
                std::array<char, 128> original_cap {};
                ssize_t size = lgetxattr(source.c_str(), "security.capability", original_cap.data(), original_cap.size());
                if (size < 0 && errno != ENODATA && errno != ENOTSUP)
                    throw std::runtime_error("Cannot inspect source capability at " + path);
                void *actual_cap = nullptr;
                size_t cap_length = 0;
                errcode_t cap_error = ext2fs_xattr_get(attrs, "security.capability", &actual_cap, &cap_length);
                if (size > 0) {
                    check(cap_error, "get capability");
                    if (cap_length != static_cast<size_t>(size) ||
                        std::memcmp(actual_cap, original_cap.data(), cap_length))
                        throw std::runtime_error("Capability differs at " + path);
                } else if (!cap_error) {
                    throw std::runtime_error("Unexpected image capability at " + path);
                } else if (cap_error != EXT2_ET_EA_KEY_NOT_FOUND) check(cap_error, "get capability");
                if (actual_cap) ext2fs_free_mem(&actual_cap);
            }
            if (write) {
                check(ext2fs_xattr_set(attrs, "security.selinux", context, std::strlen(context) + 1), "set context");
                check(ext2fs_xattrs_write(attrs), "write xattrs");
            } else {
                void *actual = nullptr;
                size_t length = 0;
                check(ext2fs_xattr_get(attrs, "security.selinux", &actual, &length), "get context");
                if (length != std::strlen(context) + 1 || std::memcmp(actual, context, length))
                    throw std::runtime_error("Context differs at " + path);
                ext2fs_free_mem(&actual);
            }
            ext2fs_xattrs_close(&attrs);
            freecon(context);
            ++count;
        };
        visit("/", root, false);
        for (const auto &entry : fs::recursive_directory_iterator(root)) {
            // lexical_relative must not resolve absolute target symlinks on the host.
            visit("/" + entry.path().lexically_relative(root).generic_string(), entry.path(), false);
        }
        if (!fs::exists(root / "lost+found")) visit("/lost+found", {}, true);
        selabel_close(labels);
        check(ext2fs_close(image), "close ext4");
        std::cout << (write ? "Applied" : "Verified") << " " << count
                  << " SELinux inode contexts; source ownership and modes preserved\n";
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
