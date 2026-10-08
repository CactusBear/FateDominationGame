#pragma once
#include <cstdint>
#include <filesystem>
#include <string>
namespace fate {
struct ReplaceResult { bool ok; std::string stage; int64_t native_error; };
// The caller owns validation, exclusive writer coordination and a trusted local directory.
// Both files must already exist, be closed for writing, and have one hard link.
ReplaceResult replace_validated_file(const std::filesystem::path &temporary,
    const std::filesystem::path &target, uint64_t validated_size);
}
