#include "process_tree_owner_core.hpp"
#include <mutex>
#include <set>
#include <utility>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif
namespace fate {
#ifdef _WIN32
namespace {
using Identity = std::pair<uint32_t, uint64_t>;
std::mutex claim_mutex;
// Local anti-double-claim only, NOT a complete/current-instance registry.
// Abandoning a live/unknown lease leaves a tombstone until this module unloads.
std::set<Identity> claims;
uint64_t creation(HANDLE p, DWORD &error) {
    FILETIME c{}, e{}, k{}, u{};
    if (!GetProcessTimes(p, &c, &e, &k, &u)) { error = GetLastError(); return 0; }
    error = 0;
    return (static_cast<uint64_t>(c.dwHighDateTime) << 32) | c.dwLowDateTime;
}
bool same(const WindowsJobLease::Binding &a, const WindowsJobLease::Binding &b) {
    return a.token == b.token && a.root_pid == b.root_pid && a.creation_time == b.creation_time;
}
}
#endif
struct WindowsJobLease::Impl {
    mutable std::mutex mutex;
    Binding binding;
    bool attempted = false;
    bool assigned = false;
    bool closed = false;
    bool poisoned = false;
    uint32_t owner = 0;
#ifdef _WIN32
    HANDLE root = nullptr;
    HANDLE job = nullptr;
    bool claimed = false;
    ~Impl() {
        // No TerminateProcess/TerminateJobObject, no KILL_ON_JOB_CLOSE.
        // Live abandonment destroys proof, not the worker or its unsaved state.
        if (root) CloseHandle(root);
        if (job) CloseHandle(job);
    }
    Receipt receipt(const char *stage, DWORD error = 0) const {
        Receipt r; r.stage = stage; r.native_error = error;
        r.binding = binding; r.local_owner_pid = owner; return r;
    }
    Receipt read(const Binding &expected) const {
        if (owner && owner != GetCurrentProcessId()) return receipt("nonlocal_owner");
        if (!same(expected, binding)) return receipt("binding_mismatch");
        if (!assigned || closed || poisoned || !root || !job) return receipt("lease_unknown");
        if (GetProcessId(root) != binding.root_pid) return receipt("root_identity_unknown", GetLastError());
        DWORD error = 0;
        auto time = creation(root, error);
        if (error || time != binding.creation_time) return receipt("root_identity_unknown", error);
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
        if (!QueryInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits), nullptr))
            return receipt("job_limits_unknown", GetLastError());
        if (limits.BasicLimitInformation.LimitFlags != 0) return receipt("job_limits_changed");
        auto r = receipt("job_observed");
        DWORD state = WaitForSingleObject(root, 0);
        if (state == WAIT_OBJECT_0) {
            r.root_state = RootState::exited;
            DWORD code = 0;
            if (!GetExitCodeProcess(root, &code)) return receipt("root_exit_code_unknown", GetLastError());
            r.root_exit_code_known = true; r.root_exit_code = code;
        } else if (state == WAIT_TIMEOUT) {
            r.root_state = RootState::running;
            BOOL in_job = FALSE;
            if (!IsProcessInJob(root, job, &in_job)) return receipt("root_membership_unknown", GetLastError());
            if (!in_job) return receipt("root_membership_changed");
        } else return receipt("root_wait_unknown", GetLastError());
        JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting{};
        if (!QueryInformationJobObject(job, JobObjectBasicAccountingInformation, &accounting, sizeof(accounting), nullptr))
            return receipt("job_accounting_unknown", GetLastError());
        if (!accounting.TotalProcesses || accounting.ActiveProcesses > accounting.TotalProcesses ||
            (r.root_state == RootState::running && !accounting.ActiveProcesses)) return receipt("job_accounting_inconsistent");
        r.active_known = true; r.active_processes = accounting.ActiveProcesses;
        r.total_processes = accounting.TotalProcesses; r.ok = true;
        return r;
    }
#endif
};
WindowsJobLease::WindowsJobLease() : impl(new Impl) {}
WindowsJobLease::~WindowsJobLease() = default;
WindowsJobLease::Receipt WindowsJobLease::assign(const SuppliedProcess &p) {
    std::lock_guard<std::mutex> lock(impl->mutex);
#ifdef _WIN32
    auto &i = *impl;
    if (i.attempted) return i.receipt("lease_already_attempted");
    i.attempted = true; i.owner = GetCurrentProcessId(); i.binding = p.binding;
    if (!p.caller_owns_created_suspended) return i.receipt("missing_suspended_ownership");
    if (!p.hprocess || p.hprocess == -1 || p.binding.token.empty() ||
        p.binding.token.find('\0') != std::string::npos || !p.binding.root_pid ||
        p.binding.root_pid == i.owner || !p.binding.creation_time) return i.receipt("invalid_supplied_process");
    HANDLE supplied = reinterpret_cast<HANDLE>(p.hprocess);
    // Restricted, non-inheritable duplicate: caller retains original HANDLE ownership.
    if (!DuplicateHandle(GetCurrentProcess(), supplied, GetCurrentProcess(), &i.root,
        PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE | PROCESS_SET_QUOTA | PROCESS_TERMINATE, FALSE, 0))
        return i.receipt("duplicate_process_handle_failed", GetLastError());
    DWORD error = 0;
    auto time = creation(i.root, error);
    if (error || GetProcessId(i.root) != p.binding.root_pid || time != p.binding.creation_time)
        return i.receipt("supplied_identity_mismatch", error);
    DWORD wait = WaitForSingleObject(i.root, 0);
    if (wait != WAIT_TIMEOUT) return i.receipt("supplied_root_not_running", wait == WAIT_FAILED ? GetLastError() : 0);
    {
        std::lock_guard<std::mutex> guard(claim_mutex);
        if (!claims.emplace(p.binding.root_pid, p.binding.creation_time).second) return i.receipt("duplicate_root_claim");
        i.claimed = true;
    }
    i.job = CreateJobObjectW(nullptr, nullptr); // unnamed, non-inheritable, private capability
    const char *failed = nullptr;
    if (!i.job) { failed = "create_job_failed"; error = GetLastError(); }
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{}; // no breakaway, no kill-on-close
    if (!failed && !SetInformationJobObject(i.job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) {
        failed = "set_job_limits_failed"; error = GetLastError();
    }
    if (!failed && !AssignProcessToJobObject(i.job, i.root)) {
        failed = "assign_job_failed"; error = GetLastError(); // incompatible enclosing Job fails closed
    }
    if (failed) {
        std::lock_guard<std::mutex> guard(claim_mutex);
        claims.erase({p.binding.root_pid, p.binding.creation_time}); i.claimed = false;
        return i.receipt(failed, error); // no resume, no root-only fallback
    }
    i.assigned = true;
    auto r = i.read(p.binding);
    if (!r.ok || !r.active_known || r.active_processes != 1 || r.total_processes != 1 || r.root_state != RootState::running) {
        i.poisoned = true;
        r.ok = false; r.stage = "assigned_state_unproven"; return r;
    }
    r.stage = "assigned_before_resume";
    return r;
#else
    (void)p;
    Receipt r; r.stage = "windows_unavailable"; return r;
#endif
}
WindowsJobLease::Receipt WindowsJobLease::observe(const Binding &binding) const {
    std::lock_guard<std::mutex> lock(impl->mutex);
#ifdef _WIN32
    return impl->read(binding);
#else
    (void)binding;
    Receipt r; r.stage = "windows_unavailable"; return r;
#endif
}
WindowsJobLease::Receipt WindowsJobLease::release(const Binding &binding) {
    std::lock_guard<std::mutex> lock(impl->mutex);
#ifdef _WIN32
    auto &i = *impl;
    auto r = i.read(binding);
    if (!r.ok) return r;
    if (r.root_state != RootState::exited || !r.active_known || r.active_processes != 0) {
        r.ok = false; r.stage = "tree_still_active"; return r;
    }
    // Fresh zero is stable for this private non-breakaway Job: no living member can spawn.
    // No external assign API/HANDLE is published by the lease.
    if (!CloseHandle(i.root)) {
        r.ok = false; r.stage = "root_close_unknown"; r.native_error = GetLastError(); i.poisoned = true; return r;
    }
    i.root = nullptr;
    if (!CloseHandle(i.job)) {
        r.ok = false; r.stage = "job_close_unknown"; r.native_error = GetLastError(); i.poisoned = true; return r;
    }
    i.job = nullptr; i.closed = true;
    {
        std::lock_guard<std::mutex> guard(claim_mutex);
        claims.erase({i.binding.root_pid, i.binding.creation_time}); i.claimed = false;
    }
    r.stage = "tree_zero_handles_released"; r.release_complete = true; r.handles_released = true;
    return r;
#else
    (void)binding;
    Receipt r; r.stage = "windows_unavailable"; return r;
#endif
}
}
