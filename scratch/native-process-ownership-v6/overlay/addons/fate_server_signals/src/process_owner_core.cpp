#include "process_owner_core.hpp"
#include <array>
#include <cerrno>
#include <chrono>
#include <cstring>
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <bcrypt.h>
#else
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <linux/sched.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>
extern char **environ;
#endif

namespace fate {
static std::string new_token() {
    std::array<unsigned char, 16> bytes{};
#ifdef _WIN32
    if (BCryptGenRandom(nullptr, bytes.data(), static_cast<ULONG>(bytes.size()), BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) return {};
#else
    size_t offset = 0;
    while (offset < bytes.size()) {
        ssize_t n = getrandom(bytes.data() + offset, bytes.size() - offset, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return {};
        offset += static_cast<size_t>(n);
    }
#endif
    const char *hex = "0123456789abcdef";
    std::string result;
    for (unsigned char byte : bytes) { result += hex[byte >> 4]; result += hex[byte & 15]; }
    return result;
}
#ifdef _WIN32
static std::wstring wide(const std::string &text) {
    if (text.empty()) return {};
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
    if (!count) return {};
    std::wstring result(static_cast<size_t>(count), L'\0');
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), &result[0], count)) return {};
    return result;
}
// CommandLineToArgvW / Microsoft CRT quoting: preserve empty args, quotes and trailing slashes.
static std::wstring quote(const std::wstring &text) {
    std::wstring result = L"\"";
    size_t slashes = 0;
    for (wchar_t c : text) {
        if (c == L'\\') { ++slashes; continue; }
        result.append(c == L'"' ? slashes * 2 + 1 : slashes, L'\\');
        slashes = 0;
        result += c;
    }
    result.append(slashes * 2, L'\\');
    return result + L"\"";
}
#else
static int wait_readable(int fd, int timeout_ms) {
    auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
    pollfd descriptor{fd, POLLIN, 0};
    for (;;) {
        auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now()).count();
        if (remaining <= 0) return 0;
        int result = poll(&descriptor, 1, static_cast<int>(remaining));
        if (result < 0 && errno == EINTR) continue;
        if (result > 0 && !(descriptor.revents & (POLLIN | POLLHUP))) return -1;
        return result;
    }
}
static int open_pidfd(pid_t pid) {
#if defined(SYS_pidfd_open) && defined(SYS_pidfd_send_signal)
    return static_cast<int>(syscall(SYS_pidfd_open, pid, 0));
#else
    (void)pid;
    errno = ENOSYS;
    return -1;
#endif
}
static bool send_pidfd(int fd, int signal) {
#ifdef SYS_pidfd_send_signal
    return syscall(SYS_pidfd_send_signal, fd, signal, nullptr, 0) == 0;
#else
    (void)fd; (void)signal;
    return false;
#endif
}
#endif

bool ProcessOwner::available() const {
#ifdef _WIN32
    return !new_token().empty();
#elif defined(__linux__)
#ifdef SYS_clone3
    // A zero-size clone3 probe creates no process. Seccomp/old kernels fail closed.
    errno = 0;
    syscall(SYS_clone3, nullptr, 0);
    if (errno != EINVAL && errno != EFAULT) return false;
#else
    return false;
#endif
    int fd = open_pidfd(getpid());
    if (fd < 0) return false;
    bool supported = send_pidfd(fd, 0); // Probe API/permissions, not ownership of a worker.
    siginfo_t info{};
    errno = 0;
    // Self is not a child: ECHILD proves P_PIDFD is implemented/allowed (Linux >= 5.4).
    int wait_result = waitid(static_cast<idtype_t>(3), static_cast<id_t>(fd), &info, WEXITED | WNOHANG);
    supported = supported && wait_result < 0 && errno == ECHILD;
    close(fd);
    return supported && !new_token().empty();
#else
    return false;
#endif
}

ProcessOwner::Spawn ProcessOwner::spawn(const std::string &executable, const std::vector<std::string> &args) {
    std::lock_guard<std::mutex> lock(mutex);
    Spawn result;
    if (executable.empty() || executable.find('\0') != std::string::npos || !available()) return result;
    for (const auto &arg : args) if (arg.find('\0') != std::string::npos) return result;
    std::string token = new_token();
    if (token.empty() || entries.count(token)) return result;
    // Allocate the registry slot before spawn so allocation failure cannot orphan a new child.
    auto slot = entries.emplace(token, Entry{-1, -1}).first;
#ifdef _WIN32
    std::wstring application = wide(executable);
    std::wstring command = quote(application);
    for (const auto &arg : args) {
        auto converted = wide(arg);
        if (!arg.empty() && converted.empty()) { entries.erase(slot); return result; }
        command += L" " + quote(converted);
    }
    if (application.empty() || command.size() >= 32767) { entries.erase(slot); return result; }
    STARTUPINFOW startup{}; startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    // No inherited handles, no shell, explicit executable. Handle pins the process object after PID reuse.
    if (!CreateProcessW(application.c_str(), &command[0], nullptr, nullptr, FALSE, 0, nullptr, nullptr, &startup, &process)) {
        entries.erase(slot); return result;
    }
    CloseHandle(process.hThread);
    slot->second = Entry{static_cast<int64_t>(process.dwProcessId), reinterpret_cast<intptr_t>(process.hProcess)};
#else
    // Parent prepares every allocation before clone; child uses only async-signal-safe operations.
    std::vector<char *> argv;
    argv.push_back(const_cast<char *>(executable.c_str()));
    for (const auto &arg : args) argv.push_back(const_cast<char *>(arg.c_str()));
    argv.push_back(nullptr);
    char **environment = environ;
    int gate[2], exec_error[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, gate) < 0) { entries.erase(slot); return result; }
    if (pipe2(exec_error, O_CLOEXEC) < 0) { close(gate[0]); close(gate[1]); entries.erase(slot); return result; }
    int fd = -1;
    pid_t child = -1;
#ifdef SYS_clone3
    clone_args options{};
    options.flags = CLONE_PIDFD;
    options.pidfd = reinterpret_cast<uintptr_t>(&fd);
    options.exit_signal = SIGCHLD;
    // PID and pidfd are created atomically. No PID-acquisition / reaper race.
    child = static_cast<pid_t>(syscall(SYS_clone3, &options, sizeof(options)));
#endif
    if (child == 0) {
        close(gate[1]); close(exec_error[0]);
        char permission = 0;
        ssize_t n;
        do { n = read(gate[0], &permission, 1); } while (n < 0 && errno == EINTR);
        close(gate[0]);
        if (n != 1 || permission != 1) _exit(126);
        execve(executable.c_str(), argv.data(), environment);
        int failure = errno;
        // A short/error write also fails closed in the parent.
        ssize_t ignored = write(exec_error[1], &failure, sizeof(failure));
        (void)ignored;
        _exit(127);
    }
    close(gate[0]); close(exec_error[1]);
    if (child < 0) { close(gate[1]); close(exec_error[0]); entries.erase(slot); return result; }
    slot->second = Entry{child, fd};
    char permission = 1;
    // MSG_NOSIGNAL also handles an external kill before gate release without killing the supervisor.
    ssize_t sent;
    do { sent = send(gate[1], &permission, 1, MSG_NOSIGNAL); } while (sent < 0 && errno == EINTR);
    close(gate[1]);
    int failure = 0;
    ssize_t n = -1;
    if (sent == 1 && wait_readable(exec_error[0], 5000) > 0) {
        do { n = read(exec_error[0], &failure, sizeof(failure)); } while (n < 0 && errno == EINTR);
    }
    close(exec_error[0]);
    if (sent != 1 || n != 0) {
        if (stop(slot->second)) { dispose(slot->second); entries.erase(slot); }
        // If the OS cannot confirm exit, keep the identity privately for destructor cleanup.
        return result;
    }
#endif
    result.pid = slot->second.pid;
    result.token = token;
    return result;
}

ProcessOwner::State ProcessOwner::inspect(const Entry &entry) {
#ifdef _WIN32
    DWORD status = WaitForSingleObject(reinterpret_cast<HANDLE>(entry.handle), 0);
    return status == WAIT_OBJECT_0 ? EXITED : status == WAIT_TIMEOUT ? RUNNING : UNKNOWN;
#else
    pollfd descriptor{static_cast<int>(entry.handle), POLLIN, 0};
    int status;
    do { status = poll(&descriptor, 1, 0); } while (status < 0 && errno == EINTR);
    if (status < 0 || (descriptor.revents & POLLNVAL)) return UNKNOWN;
    if (descriptor.revents & (POLLIN | POLLHUP)) {
        // Reap immediately on detection, while retaining pidfd for the durable exited identity.
        siginfo_t info{};
        while (waitid(static_cast<idtype_t>(3), static_cast<id_t>(entry.handle), &info, WEXITED | WNOHANG) < 0 && errno == EINTR) {}
        return EXITED;
    }
    return status == 0 ? RUNNING : UNKNOWN;
#endif
}
ProcessOwner::State ProcessOwner::state(const std::string &token, int64_t pid) {
    std::lock_guard<std::mutex> lock(mutex);
    auto entry = entries.find(token);
    return entry == entries.end() || entry->second.pid != pid ? UNKNOWN : inspect(entry->second);
}
bool ProcessOwner::stop(const Entry &entry) {
    State observed = inspect(entry);
    if (observed == EXITED) return true;
    if (observed != RUNNING) return false;
#ifdef _WIN32
    HANDLE handle = reinterpret_cast<HANDLE>(entry.handle);
    if (!TerminateProcess(handle, 1) && inspect(entry) != EXITED) return false;
    return WaitForSingleObject(handle, 5000) == WAIT_OBJECT_0;
#else
    int fd = static_cast<int>(entry.handle);
    if (!send_pidfd(fd, SIGKILL) && inspect(entry) != EXITED) return false;
    return wait_readable(fd, 5000) > 0 && inspect(entry) == EXITED;
#endif
}
bool ProcessOwner::terminate(const std::string &token, int64_t pid) {
    std::lock_guard<std::mutex> lock(mutex);
    auto entry = entries.find(token);
    return entry != entries.end() && entry->second.pid == pid && stop(entry->second);
}
void ProcessOwner::dispose(const Entry &entry) {
#ifdef _WIN32
    CloseHandle(reinterpret_cast<HANDLE>(entry.handle));
#else
    // P_PIDFD = 3 since Linux 5.4. ECHILD is valid if Godot's global reaper already reaped it.
    // Never waitpid here: a recycled PID could identify another child.
    siginfo_t info{};
    while (waitid(static_cast<idtype_t>(3), static_cast<id_t>(entry.handle), &info, WEXITED | WNOHANG) < 0 && errno == EINTR) {}
    close(static_cast<int>(entry.handle));
#endif
}
bool ProcessOwner::release(const std::string &token, int64_t pid) {
    std::lock_guard<std::mutex> lock(mutex);
    auto entry = entries.find(token);
    if (entry == entries.end() || entry->second.pid != pid || inspect(entry->second) != EXITED) return false;
    dispose(entry->second); entries.erase(entry); return true;
}
ProcessOwner::~ProcessOwner() {
    for (const auto &entry : entries) {
        // Destruction targets only retained OS identities, never an OS PID lookup.
        stop(entry.second); dispose(entry.second);
    }
}
}
