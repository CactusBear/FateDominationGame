#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <atomic>
#ifdef _WIN32
#include <windows.h>
#else
#include <csignal>
#endif

using namespace godot;

// 信号处理器只操作无锁原子变量，不调用引擎、网络、日志或文件接口。
static std::atomic<int> pending_signal{0};
static std::atomic<bool> collect_requests{true};
static_assert(std::atomic<int>::is_always_lock_free, "signal marker must be lock-free");
static_assert(std::atomic<bool>::is_always_lock_free, "signal policy must be lock-free");
#ifdef _WIN32
static BOOL WINAPI handle_console_signal(DWORD signal) {
    if (signal != CTRL_C_EVENT && signal != CTRL_BREAK_EVENT) return FALSE;
    if (collect_requests.load(std::memory_order_relaxed)) pending_signal.store(static_cast<int>(signal) + 1, std::memory_order_relaxed);
    return TRUE;
}
#else
static void handle_posix_signal(int signal) {
    if (collect_requests.load(std::memory_order_relaxed)) pending_signal.store(signal, std::memory_order_relaxed);
}
#endif

class FateServerSignals : public RefCounted {
    GDCLASS(FateServerSignals, RefCounted);
    static FateServerSignals *owner;
    bool enabled = false;
#ifndef _WIN32
    struct sigaction previous_int{};
    struct sigaction previous_term{};
#endif
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("enable"), &FateServerSignals::enable);
        ClassDB::bind_method(D_METHOD("protect_worker"), &FateServerSignals::protect_worker);
        ClassDB::bind_method(D_METHOD("disable"), &FateServerSignals::disable);
        ClassDB::bind_method(D_METHOD("take_request"), &FateServerSignals::take_request);
    }
public:
    bool enable() { return activate(true); }
    bool protect_worker() { return activate(false); }
    bool activate(bool collect) {
        if (enabled) return collect_requests.load(std::memory_order_relaxed) == collect;
        if (owner != nullptr) return false;
        pending_signal.store(0, std::memory_order_relaxed);
        collect_requests.store(collect, std::memory_order_relaxed);
#ifdef _WIN32
        // Godot 控制台包装器可能继承忽略 Ctrl+C 的标记；注册 handler 本身不会清除该标记。
        if (!SetConsoleCtrlHandler(nullptr, FALSE)) return false;
        if (!SetConsoleCtrlHandler(handle_console_signal, TRUE)) return false;
#else
        struct sigaction action{};
        action.sa_handler = handle_posix_signal;
        sigemptyset(&action.sa_mask);
        action.sa_flags = SA_RESTART;
        if (sigaction(SIGINT, &action, &previous_int) != 0) return false;
        if (sigaction(SIGTERM, &action, &previous_term) != 0) {
            sigaction(SIGINT, &previous_int, nullptr);
            return false;
        }
#endif
        owner = this;
        enabled = true;
        return true;
    }
    void disable() {
        if (!enabled || owner != this) return;
#ifdef _WIN32
        SetConsoleCtrlHandler(handle_console_signal, FALSE);
#else
        sigaction(SIGINT, &previous_int, nullptr);
        sigaction(SIGTERM, &previous_term, nullptr);
#endif
        enabled = false;
        owner = nullptr;
        pending_signal.store(0, std::memory_order_relaxed);
    }
    int64_t take_request() {
        if (!enabled || owner != this) return 0;
        return pending_signal.exchange(0, std::memory_order_relaxed);
    }
    ~FateServerSignals() { disable(); }
};

FateServerSignals *FateServerSignals::owner = nullptr;

static void initialize_signals(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) GDREGISTER_CLASS(FateServerSignals);
}

extern "C" GDExtensionBool GDE_EXPORT fate_server_signals_init(
        GDExtensionInterfaceGetProcAddress get_proc_address,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize_signals);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
