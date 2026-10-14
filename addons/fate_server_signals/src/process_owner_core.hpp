#pragma once
#include "process_tree_owner_core.hpp"
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace fate {
// Token is an in-memory capability, never an OS PID or a recoverable on-disk ID.
class ProcessOwner {
public:
    enum State { UNKNOWN = -1, EXITED = 0, RUNNING = 1 };
    struct Spawn { int64_t pid = -1; std::string token; };
    ProcessOwner() = default;
    ProcessOwner(const ProcessOwner &) = delete;
    ProcessOwner &operator=(const ProcessOwner &) = delete;
    ~ProcessOwner();
    bool available() const;
    Spawn spawn(const std::string &executable, const std::vector<std::string> &args);
    State state(const std::string &token, int64_t pid);
    bool terminate(const std::string &token, int64_t pid);
    bool release(const std::string &token, int64_t pid);
    WindowsJobLease::Receipt tree_observe(const std::string &token, int64_t pid) const;
private:
    struct Entry {
        int64_t pid = -1;
        intptr_t handle = 0;
        intptr_t thread = 0;
        std::unique_ptr<WindowsJobLease> lease;
        WindowsJobLease::Binding binding;
    };
    mutable std::mutex mutex;
    std::map<std::string, Entry> entries;
    static State inspect(const Entry &entry);
    static bool stop(const Entry &entry);
    static void dispose(const Entry &entry);
};
}
