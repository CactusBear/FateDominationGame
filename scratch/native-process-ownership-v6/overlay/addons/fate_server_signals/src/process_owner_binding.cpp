#include "process_owner_core.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

using namespace godot;
class FateProcessOwner : public RefCounted {
    GDCLASS(FateProcessOwner, RefCounted);
    fate::ProcessOwner processes;
    static std::string text(const String &value) {
        CharString bytes = value.utf8();
        return std::string(bytes.get_data(), static_cast<size_t>(bytes.length()));
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("available"), &FateProcessOwner::available);
        ClassDB::bind_method(D_METHOD("spawn", "executable", "arguments"), &FateProcessOwner::spawn);
        ClassDB::bind_method(D_METHOD("state", "token", "pid"), &FateProcessOwner::state);
        ClassDB::bind_method(D_METHOD("verify", "token", "pid"), &FateProcessOwner::verify);
        ClassDB::bind_method(D_METHOD("terminate", "token", "pid"), &FateProcessOwner::terminate);
        ClassDB::bind_method(D_METHOD("release", "token", "pid"), &FateProcessOwner::release);
    }
public:
    bool available() const { return processes.available(); }
    Dictionary spawn(const String &executable, const PackedStringArray &arguments) {
        std::vector<std::string> args;
        for (int64_t i = 0; i < arguments.size(); ++i) args.push_back(text(arguments[i]));
        auto result = processes.spawn(text(executable), args);
        Dictionary response;
        response["pid"] = result.pid;
        response["token"] = String(result.token.c_str());
        return response;
    }
    int64_t state(const String &token, int64_t pid) { return processes.state(text(token), pid); }
    bool verify(const String &token, int64_t pid) { return state(token, pid) == fate::ProcessOwner::RUNNING; }
    bool terminate(const String &token, int64_t pid) { return processes.terminate(text(token), pid); }
    bool release(const String &token, int64_t pid) { return processes.release(text(token), pid); }
};
void register_fate_process_owner() { GDREGISTER_CLASS(FateProcessOwner); }
