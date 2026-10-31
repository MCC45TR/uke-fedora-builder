// COPR-only SDK bootstrap conversion: retain CPIO data-last hard links in TAR.
#include <archive.h>
#include <archive_entry.h>
#include <sys/types.h>
#include <array>
#include <filesystem>
#include <iostream>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using Entry = std::unique_ptr<archive_entry, decltype(&archive_entry_free)>;
struct Links {
    std::vector<Entry> entries;
    std::vector<char> data;
    bool has_data = false;
};
static std::string message(archive *value) {
    const char *text = archive_error_string(value);
    return text ? text : "Archive operation failed";
}
static void write_bytes(archive *output, const char *data, size_t size) {
    while (size) {
        const auto count = archive_write_data(output, data, size);
        if (count <= 0) throw std::runtime_error(message(output));
        data += count;
        size -= static_cast<size_t>(count);
    }
}
static void header(archive *output, archive_entry *entry) {
    if (archive_write_header(output, entry) != ARCHIVE_OK)
        throw std::runtime_error(message(output));
}
int main(int argc, char **argv) {
    try {
        if (argc != 3) throw std::runtime_error("Usage: cpio-sdk-tar INPUT.cpio OUTPUT.tar");
        const std::filesystem::path output_path(argv[2]);
        if (std::filesystem::exists(output_path) || std::filesystem::is_symlink(output_path))
            throw std::runtime_error("Output already exists");
        auto input = std::unique_ptr<archive, decltype(&archive_read_free)>(archive_read_new(), archive_read_free);
        auto output = std::unique_ptr<archive, decltype(&archive_write_free)>(archive_write_new(), archive_write_free);
        if (!input || !output) throw std::runtime_error("Cannot allocate archive state");
        archive_read_support_format_cpio(input.get());
        archive_read_support_filter_none(input.get());
        if (archive_read_open_filename(input.get(), argv[1], 65536) != ARCHIVE_OK)
            throw std::runtime_error(message(input.get()));
        if (archive_write_set_format_pax_restricted(output.get()) != ARCHIVE_OK ||
            archive_write_open_filename(output.get(), argv[2]) != ARCHIVE_OK)
            throw std::runtime_error(message(output.get()));
        std::map<std::pair<dev_t, la_int64_t>, Links> groups;
        constexpr size_t limit = 512U * 1024U * 1024U;
        size_t buffered = 0, entries = 0;
        std::array<char, 65536> block {};
        archive_entry *value = nullptr;
        int result;
        while ((result = archive_read_next_header(input.get(), &value)) == ARCHIVE_OK) {
            const char *name = archive_entry_pathname(value);
            if (!name || !*name) throw std::runtime_error("Missing archive pathname");
            const std::filesystem::path path(name);
            if (path.is_absolute()) throw std::runtime_error("Absolute archive pathname");
            for (const auto &part : path)
                if (part == "..") throw std::runtime_error("Parent archive pathname");
            const auto type = archive_entry_filetype(value);
            if (type != AE_IFREG && type != AE_IFDIR && type != AE_IFLNK)
                throw std::runtime_error("Special SDK payload is not allowed");
            ++entries;
            if (type == AE_IFREG && archive_entry_nlink(value) > 1) {
                auto &links = groups[{archive_entry_dev(value), archive_entry_ino64(value)}];
                auto copy = Entry(archive_entry_clone(value), archive_entry_free);
                if (!copy) throw std::runtime_error("Cannot retain hard-link metadata");
                links.entries.push_back(std::move(copy));
                std::vector<char> data;
                la_ssize_t count;
                while ((count = archive_read_data(input.get(), block.data(), block.size())) > 0) {
                    if (buffered + data.size() + static_cast<size_t>(count) > limit)
                        throw std::runtime_error("SDK hard-link buffer limit exceeded");
                    data.insert(data.end(), block.data(), block.data() + count);
                }
                if (count < 0) throw std::runtime_error(message(input.get()));
                if (archive_entry_size(value) < 0 ||
                    static_cast<la_int64_t>(data.size()) != archive_entry_size(value))
                    throw std::runtime_error("Incomplete hard-link payload");
                if (!data.empty()) {
                    if (links.has_data && links.data != data)
                        throw std::runtime_error("Conflicting hard-link payloads");
                    if (!links.has_data) {
                        buffered += data.size();
                        links.data = std::move(data);
                        links.has_data = true;
                    }
                }
            } else {
                header(output.get(), value);
                la_ssize_t count;
                while ((count = archive_read_data(input.get(), block.data(), block.size())) > 0)
                    write_bytes(output.get(), block.data(), static_cast<size_t>(count));
                if (count < 0) throw std::runtime_error(message(input.get()));
            }
        }
        if (result != ARCHIVE_EOF) throw std::runtime_error(message(input.get()));
        for (auto &[identity, links] : groups) {
            (void)identity;
            auto *first = links.entries.front().get();
            const std::string target(archive_entry_pathname(first));
            archive_entry_set_hardlink(first, nullptr);
            archive_entry_set_size(first, static_cast<la_int64_t>(links.data.size()));
            header(output.get(), first);
            write_bytes(output.get(), links.data.data(), links.data.size());
            for (size_t index = 1; index < links.entries.size(); ++index) {
                auto *alias = links.entries[index].get();
                archive_entry_set_hardlink(alias, target.c_str());
                archive_entry_set_size(alias, 0);
                header(output.get(), alias);
            }
        }
        if (archive_write_close(output.get()) != ARCHIVE_OK)
            throw std::runtime_error(message(output.get()));
        std::cout << "SDK CPIO conversion retained " << entries << " entries and "
                  << groups.size() << " hard-link groups\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
