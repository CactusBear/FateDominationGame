#pragma once
#include <cstdint>
#include <map>
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
private:
    struct Entry { int64_t pid; intptr_t handle; };
    std::mutex mutex;
    std::map<std::string, Entry> entries;
    static State inspect(const Entry &entry);
    static bool stop(const Entry &entry);
    static void dispose(const Entry &entry);
};
}
