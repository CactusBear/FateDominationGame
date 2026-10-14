#pragma once
#include <cstdint>
#include <filesystem>
#include <memory>
#include <string>

namespace fate {
struct CleanupIdentity {
    uint32_t volume = 0;
    uint64_t file_index = 0;
    bool operator==(const CleanupIdentity &other) const {
        return volume == other.volume && file_index == other.file_index;
    }
};
enum class CleanupArtifactKind { unspecified, temporary_file, archive };
struct TemporaryCleanupRequest {
    std::filesystem::path approved_root;
    std::filesystem::path file;
    CleanupIdentity approved_root_identity;
    CleanupIdentity parent_identity;
    CleanupIdentity file_identity;
    uint64_t size = 0;
    std::string sha256; // exactly 64 lowercase hexadecimal characters
    CleanupArtifactKind kind = CleanupArtifactKind::unspecified;
};
struct TemporaryCleanupResult {
    bool ok = false;
    std::string stage;
    int64_t native_error = 0;
    uint64_t removed_bytes = 0;
    bool recovery_required = false; // disposition committed but completion unconfirmed
};

// Never derives authorization, lifecycle or complete-instance proof from paths.
// A lease owns ancestor pins and ONE exclusive file HANDLE. No delete on destruction.
// acquire only locks; verify_and_delete validates and deletes through that same HANDLE.
// Caller must serialize intent/result persistence and retain the lease throughout it.
class TemporaryCleanupLease {
public:
    TemporaryCleanupLease();
    ~TemporaryCleanupLease();
    TemporaryCleanupLease(TemporaryCleanupLease &&) noexcept;
    TemporaryCleanupLease &operator=(TemporaryCleanupLease &&) noexcept;
    TemporaryCleanupLease(const TemporaryCleanupLease &) = delete;
    TemporaryCleanupLease &operator=(const TemporaryCleanupLease &) = delete;
    static TemporaryCleanupResult acquire(const TemporaryCleanupRequest &request,
        TemporaryCleanupLease &out);
    TemporaryCleanupResult verify_and_delete();
private:
    struct State;
    std::unique_ptr<State> state_;
};
TemporaryCleanupResult delete_approved_temporary(const TemporaryCleanupRequest &request);
} // namespace fate