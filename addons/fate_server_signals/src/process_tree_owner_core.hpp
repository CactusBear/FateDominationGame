#pragma once
#include <cstdint>
#include <memory>
#include <string>

namespace fate {
// No spawning, stopping, saving, registry completeness or cleanup authorization.
class WindowsJobLease final {
public:
    enum class RootState { unknown, running, exited };
    struct Binding {
        std::string token;
        uint32_t root_pid = 0;
        uint64_t creation_time = 0; // exact GetProcessTimes FILETIME, not wall clock/PID alone
    };
    struct SuppliedProcess {
        intptr_t hprocess = 0; // borrowed real local HANDLE; never PID/OpenProcess
        Binding binding;
        // Trusted native caller assertion. hProcess alone cannot prove suspension.
        bool caller_owns_created_suspended = false;
    };
    struct Receipt {
        bool ok = false;
        std::string stage = "unknown";
        uint32_t native_error = 0;
        Binding binding;
        uint32_t local_owner_pid = 0;
        RootState root_state = RootState::unknown;
        bool active_known = false;
        uint32_t active_processes = 0;
        uint32_t total_processes = 0;
        bool root_exit_code_known = false;
        uint32_t root_exit_code = 0;
        bool release_complete = false;
        bool handles_released = false;
    };
    WindowsJobLease();
    ~WindowsJobLease(); // closes references only; NEVER kill-on-close, stop or saved receipt
    WindowsJobLease(const WindowsJobLease &) = delete;
    WindowsJobLease &operator=(const WindowsJobLease &) = delete;
    WindowsJobLease(WindowsJobLease &&) = delete;
    WindowsJobLease &operator=(WindowsJobLease &&) = delete;
    Receipt assign(const SuppliedProcess &process);
    Receipt observe(const Binding &binding) const;
    Receipt release(const Binding &binding); // fresh exact-Job active=0 AND root signaled
private:
    struct Impl;
    std::unique_ptr<Impl> impl;
};
}
