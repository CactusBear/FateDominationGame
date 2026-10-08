#include "process_owner_core.hpp"
#include <cassert>
#include <cerrno>
#include <chrono>
#include <iostream>
#include <string>
#include <thread>
#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#include <sys/wait.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <cstddef>
#endif
using fate::ProcessOwner;
static void wait_exit(ProcessOwner &owner, const ProcessOwner::Spawn &process) {
    for (int i = 0; i < 200 && owner.state(process.token, process.pid) == ProcessOwner::RUNNING; ++i)
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    assert(owner.state(process.token, process.pid) == ProcessOwner::EXITED);
}
int main(int argc, char **argv) {
    if (argc > 1 && std::string(argv[1]) == "--child") {
        if (argc > 2 && std::string(argv[2]) == "--args") {
            return argc == 7 && std::string(argv[3]).empty() && std::string(argv[4]) == "a b" && std::string(argv[5]) == "a\"b" && std::string(argv[6]) == "tail\\" ? 0 : 93;
        }
        std::this_thread::sleep_for(std::chrono::seconds(60)); return 0;
    }
    ProcessOwner owner;
#ifndef _WIN32
    if (argc > 1 && std::string(argv[1]) == "--blocked") {
        sock_filter filter[] = {
            BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(seccomp_data, nr)),
            BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_clone3, 0, 1),
            BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | ENOSYS),
            BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW)
        };
        sock_fprog program{static_cast<unsigned short>(sizeof(filter) / sizeof(filter[0])), filter};
        assert(prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) == 0);
        assert(prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program) == 0);
        assert(!owner.available());
        assert(owner.spawn("/bin/sleep", {"60"}).pid == -1);
        std::cout << "PASS fail-closed: real seccomp denies clone3; no PID fallback\n";
        return 0;
    }
#endif
    assert(owner.available());
#ifdef _WIN32
    char executable[32768]{};
    assert(GetModuleFileNameA(nullptr, executable, sizeof(executable)) > 0);
    std::string self = executable;
#else
    char executable[4096]{};
    auto n = readlink("/proc/self/exe", executable, sizeof(executable)-1);
    assert(n > 0);
    std::string self(executable, static_cast<size_t>(n));
#endif
    assert(owner.state("", 1) == ProcessOwner::UNKNOWN);
    assert(owner.spawn("/does/not/exist", {}).pid == -1);
    auto a = owner.spawn(self, {"--child"});
    auto b = owner.spawn(self, {"--child"});
    assert(a.pid > 0 && b.pid > 0 && a.token.size() == 32 && a.token != b.token);
    assert(owner.state(a.token, a.pid) == ProcessOwner::RUNNING);
    assert(owner.state(a.token, b.pid) == ProcessOwner::UNKNOWN);
    assert(!owner.terminate(a.token, b.pid));
    assert(!owner.terminate("forged", b.pid));
    assert(!owner.release(a.token, a.pid));
    assert(owner.state(b.token, b.pid) == ProcessOwner::RUNNING);
    assert(owner.terminate(a.token, a.pid));
    wait_exit(owner, a);
    assert(owner.state(b.token, b.pid) == ProcessOwner::RUNNING);
    assert(owner.terminate(a.token, a.pid)); // Exited retained identity is idempotent.
    assert(owner.release(a.token, a.pid));
    assert(owner.state(a.token, a.pid) == ProcessOwner::UNKNOWN);
    assert(!owner.terminate(a.token, b.pid));
    assert(owner.terminate(b.token, b.pid));
    assert(owner.release(b.token, b.pid));
#ifndef _WIN32
    assert(waitpid(static_cast<pid_t>(b.pid), nullptr, WNOHANG) == -1);
#endif
    auto quoted = owner.spawn(self, {"--child", "--args", "", "a b", "a\"b", "tail\\"});
    assert(quoted.pid > 0);
#ifndef _WIN32
    // Emulate Godot's global reaper: pidfd identity still reports exited after reap.
    int exit_status = -1;
    assert(waitpid(static_cast<pid_t>(quoted.pid), &exit_status, 0) == quoted.pid);
    assert(WIFEXITED(exit_status) && WEXITSTATUS(exit_status) == 0);
    assert(owner.state(quoted.token, quoted.pid) == ProcessOwner::EXITED);
    assert(owner.release(quoted.token, quoted.pid));
#else
    wait_exit(owner, quoted);
    HANDLE read_only = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, static_cast<DWORD>(quoted.pid));
    assert(read_only);
    DWORD code = 99;
    assert(GetExitCodeProcess(read_only, &code)); assert(code == 0); CloseHandle(read_only);
    assert(owner.release(quoted.token, quoted.pid));
#endif
    ProcessOwner::Spawn orphan;
#ifdef _WIN32
    HANDLE observer = nullptr;
#endif
    {
        ProcessOwner scoped;
        orphan = scoped.spawn(self, {"--child"});
        assert(orphan.pid > 0);
#ifdef _WIN32
        observer = OpenProcess(SYNCHRONIZE, FALSE, static_cast<DWORD>(orphan.pid));
        assert(observer);
#endif
    }
#ifndef _WIN32
    assert(waitpid(static_cast<pid_t>(orphan.pid), nullptr, WNOHANG) == -1);
#else
    assert(WaitForSingleObject(observer, 0) == WAIT_OBJECT_0);
    CloseHandle(observer);
#endif
    std::cout << "PASS native ownership: real spawn, token/PID mismatch, no live release, exit, terminate, release, argv, RAII\n";
}
