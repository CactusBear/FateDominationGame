#include "process_tree_owner_core.hpp"
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#ifdef FATE_LEASE_CORE_HOOK
// Forced include for the standalone test object only; production source has no test switches.
BOOL WINAPI fate_probe_assign(HANDLE job, HANDLE process);
BOOL WINAPI fate_probe_query(HANDLE job, JOBOBJECTINFOCLASS kind, LPVOID info, DWORD size, LPDWORD written);
#define AssignProcessToJobObject fate_probe_assign
#define QueryInformationJobObject fate_probe_query
#else
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#include <memory>
using Lease = fate::WindowsJobLease;
static bool deny_assign = false, deny_query = false;
BOOL WINAPI fate_probe_assign(HANDLE job, HANDLE process) {
    if (!deny_assign) return AssignProcessToJobObject(job, process);
    HANDLE restricted = nullptr;
    if (!DuplicateHandle(GetCurrentProcess(), job, GetCurrentProcess(), &restricted, JOB_OBJECT_QUERY, FALSE, 0)) return FALSE;
    BOOL result = AssignProcessToJobObject(restricted, process); // genuine Win32 ERROR_ACCESS_DENIED
    DWORD error = GetLastError(); CloseHandle(restricted); SetLastError(error); return result;
}
BOOL WINAPI fate_probe_query(HANDLE job, JOBOBJECTINFOCLASS kind, LPVOID info, DWORD size, LPDWORD written) {
    if (!deny_query) return QueryInformationJobObject(job, kind, info, size, written);
    HANDLE restricted = nullptr;
    if (!DuplicateHandle(GetCurrentProcess(), job, GetCurrentProcess(), &restricted, JOB_OBJECT_ASSIGN_PROCESS, FALSE, 0)) return FALSE;
    BOOL result = QueryInformationJobObject(restricted, kind, info, size, written);
    DWORD error = GetLastError(); CloseHandle(restricted); SetLastError(error); return result;
}
static void need(bool ok, const char *why) { if (!ok) throw std::runtime_error(why); }
struct Handle {
    HANDLE h = nullptr;
    Handle() = default;
    explicit Handle(HANDLE v) : h(v) {}
    ~Handle() { if (h) CloseHandle(h); }
    Handle(const Handle &) = delete;
    Handle &operator=(const Handle &) = delete;
};
static uint64_t born(HANDLE p) {
    FILETIME c{}, e{}, k{}, u{};
    need(GetProcessTimes(p, &c, &e, &k, &u) != FALSE, "creation time");
    return (static_cast<uint64_t>(c.dwHighDateTime) << 32) | c.dwLowDateTime;
}
static std::wstring exe() {
    std::vector<wchar_t> name(32768);
    DWORD n = GetModuleFileNameW(nullptr, name.data(), static_cast<DWORD>(name.size()));
    need(n && n < name.size(), "exe path");
    return std::wstring(name.data(), n);
}
static PROCESS_INFORMATION spawn(const std::wstring &args, bool suspended) {
    auto path = exe();
    auto cmd = L"\"" + path + L"\" " + args;
    STARTUPINFOW si{}; si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    need(CreateProcessW(path.c_str(), &cmd[0], nullptr, nullptr, TRUE,
                        suspended ? CREATE_SUSPENDED : 0, nullptr, nullptr, &si, &pi) != FALSE, "spawn own probe");
    return pi;
}
static std::wstring num(HANDLE h) { return std::to_wstring(reinterpret_cast<uintptr_t>(h)); }
static HANDLE arg(char *s) { return reinterpret_cast<HANDLE>(static_cast<uintptr_t>(std::stoull(s))); }
static void wait(HANDLE h) { need(WaitForSingleObject(h, 12000) == WAIT_OBJECT_0, "fixture wait timeout"); }
static void emit(const char *name, const Lease::Receipt &r) {
    std::cout << "{\"case\":\"" << name << "\",\"ok\":" << (r.ok ? "true" : "false")
              << ",\"stage\":\"" << r.stage << "\",\"error\":" << r.native_error
              << ",\"active_known\":" << (r.active_known ? "true" : "false")
              << ",\"active\":" << r.active_processes << ",\"total\":" << r.total_processes
              << ",\"root_pid\":" << r.binding.root_pid << ",\"creation_time\":" << r.binding.creation_time
              << ",\"local_owner_pid\":" << r.local_owner_pid
              << ",\"root_exited\":" << (r.root_state == Lease::RootState::exited ? "true" : "false")
              << ",\"root_exit_code\":" << r.root_exit_code
              << ",\"release_complete\":" << (r.release_complete ? "true" : "false")
              << ",\"handles_released\":" << (r.handles_released ? "true" : "false") << "}" << std::endl;
}
struct Tree {
    struct Shared { PVOID volatile child; PVOID volatile grand; };
    // Inherited exact event HANDLEs, not named objects or system PID discovery.
    Handle ready, child_go, grand_go, child_done, grand_done;
    Handle process, thread;
    Handle controller, mapping, child_process, grand_process;
    Shared *shared = nullptr;
    Lease::Binding binding;
    Tree(bool crash = false) {
        SECURITY_ATTRIBUTES sa{sizeof(sa), nullptr, TRUE};
        for (HANDLE *p : {&ready.h, &child_go.h, &grand_go.h, &child_done.h, &grand_done.h}) {
            *p = CreateEventW(&sa, TRUE, FALSE, nullptr); need(*p != nullptr, "event");
        }
        need(DuplicateHandle(GetCurrentProcess(), GetCurrentProcess(), GetCurrentProcess(), &controller.h,
                             PROCESS_DUP_HANDLE | PROCESS_QUERY_LIMITED_INFORMATION, TRUE, 0) != FALSE, "controller handle");
        mapping.h = CreateFileMappingW(INVALID_HANDLE_VALUE, &sa, PAGE_READWRITE, 0, sizeof(Shared), nullptr);
        need(mapping.h != nullptr, "shared fixture mapping");
        shared = static_cast<Shared *>(MapViewOfFile(mapping.h, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(Shared)));
        need(shared != nullptr, "map fixture");
        shared->child = nullptr; shared->grand = nullptr;
        auto args = L"root " + num(ready.h) + L" " + num(child_go.h) + L" " + num(grand_go.h)
                  + L" " + num(child_done.h) + L" " + num(grand_done.h)
                  + L" " + num(controller.h) + L" " + num(mapping.h) + (crash ? L" 1" : L" 0");
        auto pi = spawn(args, true);
        process.h = pi.hProcess; thread.h = pi.hThread;
        binding = {"local-owner-token", pi.dwProcessId, born(process.h)};
    }
    Lease::SuppliedProcess supplied() { return {reinterpret_cast<intptr_t>(process.h), binding, true}; }
    void resume() { need(ResumeThread(thread.h) == 1, "only resume assigned suspended root"); }
    void root_exit() {
        wait(ready.h); wait(process.h);
        child_process.h = shared->child; grand_process.h = shared->grand;
        need(child_process.h && grand_process.h, "exact duplicated descendant handles");
    }
    void drain() {
        SetEvent(child_go.h); SetEvent(grand_go.h);
        wait(child_done.h); wait(grand_done.h);
        wait(child_process.h); wait(grand_process.h);
    }
    ~Tree() {
        // Fixture-specific explicit local caller recovery, never production lease policy.
        SetEvent(child_go.h); SetEvent(grand_go.h);
        if (WaitForSingleObject(process.h, 0) == WAIT_TIMEOUT) {
            // Exact root handle owned by this constructor, including never-resumed RED case.
            TerminateProcess(process.h, 91);
            WaitForSingleObject(process.h, 5000);
        }
        if (child_process.h) WaitForSingleObject(child_process.h, 15000);
        if (grand_process.h) WaitForSingleObject(grand_process.h, 15000);
        if (shared) UnmapViewOfFile(shared);
    }
};
static Lease::Receipt drained(Lease &lease, const Lease::Binding &b) {
    for (int i = 0; i < 600; ++i) {
        auto r = lease.observe(b);
        if (!r.ok || (r.active_known && r.active_processes == 0)) return r;
        Sleep(10);
    }
    throw std::runtime_error("own Job did not drain");
}
static int child_mode(int argc, char **argv) {
    need(argc >= 9, "child args");
    HANDLE ready = arg(argv[2]), child_go = arg(argv[3]), grand_go = arg(argv[4]);
    HANDLE child_done = arg(argv[5]), grand_done = arg(argv[6]);
    HANDLE controller = arg(argv[7]), mapping = arg(argv[8]);
    std::string mode = argv[1];
    if (mode == "grand") {
        wait(grand_go); SetEvent(grand_done); return 0;
    }
    auto args = L"grand " + num(ready) + L" " + num(child_go) + L" " + num(grand_go)
              + L" " + num(child_done) + L" " + num(grand_done)
              + L" " + num(controller) + L" " + num(mapping);
    if (mode == "root") args.replace(0, 5, L"child");
    auto pi = spawn(args, false);
    Handle p(pi.hProcess), t(pi.hThread);
    auto shared = static_cast<Tree::Shared *>(MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(Tree::Shared)));
    need(shared != nullptr, "map child");
    HANDLE remote = nullptr;
    need(DuplicateHandle(GetCurrentProcess(), p.h, controller, &remote,
                         PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, 0) != FALSE, "exact child handle handoff");
    InterlockedExchangePointer(mode == "root" ? &shared->child : &shared->grand, remote);
    UnmapViewOfFile(shared);
    if (mode == "child") SetEvent(ready);
    else wait(ready);
    if (mode == "root") {
        if (argc > 9 && std::string(argv[9]) == "1") TerminateProcess(GetCurrentProcess(), 73);
        return 0;
    }
    wait(child_go); SetEvent(child_done); return 0;
}
static int run_tree() {
    Tree tree;
    Lease lease;
    auto assigned = lease.assign(tree.supplied()); emit("assigned_before_resume", assigned);
    if (!assigned.ok) return 1;
    need(WaitForSingleObject(tree.ready.h, 0) == WAIT_TIMEOUT, "root must not execute before assign");
    need(assigned.active_known && assigned.active_processes == 1, "suspended root in exact job");
    tree.resume(); tree.root_exit();
    Lease::Receipt refused;
    for (int i = 0; i < 600; ++i) {
        refused = lease.release(tree.binding);
        if (refused.active_known && refused.active_processes == 2) break;
        Sleep(10);
    }
    emit("root_exit_child_running", refused);
    need(!refused.release_complete && refused.active_known && refused.active_processes == 2, "descendants block release");
    tree.drain();
    auto zero = drained(lease, tree.binding); emit("final_active_zero_readback", zero);
    DWORD before = 0, after_count = 0;
    need(GetProcessHandleCount(GetCurrentProcess(), &before) != FALSE, "handle count before");
    auto released = lease.release(tree.binding); emit("final_release", released);
    need(GetProcessHandleCount(GetCurrentProcess(), &after_count) != FALSE && before == after_count + 2, "actual two lease handles closed");
    need(released.release_complete && released.handles_released && released.active_processes == 0, "final proof and close");
    auto after = lease.observe(tree.binding); emit("after_release_unknown", after);
    need(!after.ok && !after.release_complete, "released lease cannot reissue proof");
    std::cout << "{\"case\":\"handles_closed\",\"ok\":true,\"handle_count_before\":" << before
              << ",\"handle_count_after\":" << after_count << "}" << std::endl;
    return 0;
}
static int run_bindings() {
    Tree tree; Lease lease, duplicate, unknown;
    auto assigned = lease.assign(tree.supplied()); need(assigned.ok, "assign binding fixture");
    auto stale = tree.binding; stale.token += "-old"; emit("stale_token", lease.release(stale));
    stale = tree.binding; ++stale.root_pid; emit("stale_pid", lease.observe(stale));
    stale = tree.binding; ++stale.creation_time; emit("stale_creation", lease.release(stale));
    auto p = tree.supplied(); p.binding.token = "distinct-token-same-root";
    emit("duplicate_claim", duplicate.assign(p));
    emit("reassign", lease.assign(tree.supplied()));
    emit("unknown", unknown.release(tree.binding));
    emit("valid_after_stale", lease.observe(tree.binding));
    tree.resume(); tree.root_exit(); tree.drain();
    auto zero = drained(lease, tree.binding); emit("bindings_zero_before_query_denial", zero);
    need(zero.ok && zero.active_processes == 0, "bindings drain");
    deny_query = true; auto unavailable = lease.release(tree.binding); deny_query = false;
    emit("query_unknown", unavailable); need(!unavailable.ok && !unavailable.release_complete && unavailable.native_error == ERROR_ACCESS_DENIED, "native query failure closed even after prior zero");
    emit("still_owned_after_unknown", lease.observe(tree.binding));
    emit("bindings_final_release", lease.release(tree.binding)); return 0;
}
static int run_crash() {
    Tree tree(true); Lease lease;
    need(lease.assign(tree.supplied()).ok, "assign crash fixture");
    tree.resume(); tree.root_exit();
    Lease::Receipt r;
    for (int i = 0; i < 600; ++i) {
        r = lease.release(tree.binding);
        if (r.active_known && r.active_processes == 2) break;
        Sleep(10);
    }
    emit("crashed_root_live_tree", r);
    need(!r.release_complete && r.root_exit_code_known && r.root_exit_code == 73 && r.active_processes == 2, "crash descendants retained");
    tree.drain(); emit("crash_final_active_zero", drained(lease, tree.binding));
    emit("crash_final_release", lease.release(tree.binding)); return 0;
}
static int run_abandon() {
    Tree tree;
    auto lease = std::make_unique<Lease>();
    need(lease->assign(tree.supplied()).ok, "assign abandon fixture");
    tree.resume(); tree.root_exit();
    emit("before_destructor_live_tree", lease->observe(tree.binding));
    lease.reset(); // production destructor under test, not a test kill substitute
    Lease::Receipt alive;
    alive.ok = WaitForSingleObject(tree.child_process.h, 0) == WAIT_TIMEOUT &&
               WaitForSingleObject(tree.grand_process.h, 0) == WAIT_TIMEOUT;
    emit("descendants_alive_after_destructor", alive); need(alive.ok, "destructor killed worker");
    Lease duplicate; emit("duplicate_after_abandon", duplicate.assign(tree.supplied()));
    tree.drain(); Lease::Receipt exited; exited.ok = true; emit("owned_descendants_naturally_exited", exited);
    Tree suspended; auto second = std::make_unique<Lease>();
    need(second->assign(suspended.supplied()).ok, "second assign"); second.reset();
    Lease retry; auto rejected = retry.assign(suspended.supplied()); emit("abandoned_root_tombstone", rejected);
    need(!rejected.ok && rejected.stage == "duplicate_root_claim", "no live abandoned reclaim");
    suspended.resume(); suspended.root_exit(); suspended.drain();
    return 0;
}
static int run_invalid() {
    Tree tree; Lease missing, wrong, invalid, nested, denied;
    auto p = tree.supplied(); p.caller_owns_created_suspended = false;
    emit("missing_ownership", missing.assign(p));
    p = tree.supplied(); ++p.binding.creation_time; emit("wrong_identity", wrong.assign(p));
    p = tree.supplied(); p.hprocess = 0x1234; emit("invalid_handle", invalid.assign(p));
    Handle outer(CreateJobObjectW(nullptr, nullptr)); need(outer.h != nullptr, "outer job");
    JOBOBJECT_BASIC_UI_RESTRICTIONS ui{}; ui.UIRestrictionsClass = JOB_OBJECT_UILIMIT_HANDLES;
    need(SetInformationJobObject(outer.h, JobObjectBasicUIRestrictions, &ui, sizeof(ui)) != FALSE, "outer UI restriction");
    need(AssignProcessToJobObject(outer.h, tree.process.h) != FALSE, "assign own outer job");
    deny_assign = true; auto refused = denied.assign(tree.supplied()); deny_assign = false;
    emit("native_assign_denied", refused);
    need(!refused.ok && refused.stage == "assign_job_failed" && refused.native_error == ERROR_ACCESS_DENIED, "native assign failure must fail closed");
    emit("failed_assign_unknown", denied.release(tree.binding));
    Lease::Receipt no_resume; no_resume.ok = WaitForSingleObject(tree.ready.h, 0) == WAIT_TIMEOUT &&
        WaitForSingleObject(tree.process.h, 0) == WAIT_TIMEOUT;
    emit("no_resume_on_failure", no_resume); need(no_resume.ok, "failure resumed owned root");
    // This Windows host allows this real UI-restricted outer Job nesting. Do not fake failure.
    auto compatible = nested.assign(tree.supplied()); emit("compatible_nested_job", compatible);
    need(compatible.ok, "real compatible nesting");
    tree.resume(); tree.root_exit(); tree.drain();
    emit("nested_final_zero", drained(nested, tree.binding));
    emit("nested_final_release", nested.release(tree.binding)); return 0;
}
int main(int argc, char **argv) {
    try {
        need(argc > 1, "mode");
        std::string mode = argv[1];
        if (mode == "root" || mode == "child" || mode == "grand") return child_mode(argc, argv);
        if (mode == "tree") return run_tree();
        if (mode == "bindings") return run_bindings();
        if (mode == "crash") return run_crash();
        if (mode == "abandon") return run_abandon();
        if (mode == "invalid") return run_invalid();
        throw std::runtime_error("unknown mode");
    } catch (const std::exception &e) { std::cerr << e.what() << std::endl; return 2; }
}
#endif
