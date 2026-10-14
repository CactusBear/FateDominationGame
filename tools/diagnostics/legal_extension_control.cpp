// 独立诊断控制；只依赖精确宿主 C 接口，不链接 godot-cpp。
#define NOMINMAX
#include <windows.h>
#include "gdextension_interface.h"
#include <cstdio>
#include <cstdlib>
#include <new>

// 所有静态存储均是普通字节/指针；Godot StringName 只在 SCENE 构造和销毁。
struct alignas(8) Name { unsigned char bytes[8]; };
static_assert(sizeof(void *) == 8 && sizeof(Name) == 8, "pinned x64 StringName storage");
static Name class_name, parent_name, object_name, notification_name, refcount_name, initref_name, unref_name;
static GDExtensionClassLibraryPtr library;
static GDExtensionInterfaceStringNameNewWithUtf8Chars name_new;
static GDExtensionInterfaceVariantGetPtrDestructor get_destructor;
static GDExtensionInterfaceClassdbRegisterExtensionClass4 register_class;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionInterfaceClassdbConstructObject2 construct;
static GDExtensionInterfaceObjectSetInstance set_instance;
static GDExtensionInterfaceObjectDestroy destroy_object;
static GDExtensionInterfaceClassdbGetMethodBind method_bind;
static GDExtensionInterfaceObjectMethodBindPtrcall ptrcall;
static GDExtensionPtrDestructor name_destroy;
static GDExtensionMethodBindPtr notification_bind, refcount_bind, initref_bind, unref_bind;
static bool enabled, initialized, registered;
static unsigned creates, frees;
struct Instance { GDExtensionObjectPtr owner; };
static void trace(const char *event, int level = -1) {
    std::printf("R49_CONTROL tick=%llu pid=%lu tid=%lu event=%s level=%d registered=%d creates=%u frees=%u\n",
        GetTickCount64(), GetCurrentProcessId(), GetCurrentThreadId(), event, level, registered, creates, frees);
    std::fflush(stdout);
}
[[noreturn]] static void fail(const char *reason) {
    std::fprintf(stderr, "R49_INITFAIL reason=%s\n", reason); std::fflush(stderr);
    // initialization callback 返回 void；不可假装成功后继续，明确以非 AV 状态终止自有测试。
    ExitProcess(0xE0490001);
}
static void notify_postinitialize(GDExtensionObjectPtr object) {
    int64_t what = 0; GDExtensionBool reversed = 0;
    const GDExtensionConstTypePtr args[] = { &what, &reversed };
    ptrcall(notification_bind, object, args, nullptr);
}
static GDExtensionObjectPtr create_instance(void *, GDExtensionBool notify) {
    trace("CREATE_ENTER");
    auto *instance = new (std::nothrow) Instance{};
    if (!instance) fail("instance allocation");
    // v4 create_instance2 合约要求 RefCounted 返回引用计数零；不调用 init_ref。
    instance->owner = construct(&parent_name);
    if (!instance->owner) { delete instance; fail("RefCounted constructor"); }
    set_instance(instance->owner, &class_name, instance);
    ++creates;
    if (notify) notify_postinitialize(instance->owner);
    trace("CREATE_RETURN");
    return instance->owner;
}
static void free_instance(void *, GDExtensionClassInstancePtr value) {
    trace("FREE_ENTER");
    // 引擎拥有并销毁 owner；这里只释放绑定的自有实例，禁止递归 object_destroy。
    delete static_cast<Instance *>(value); ++frees; trace("FREE_RETURN");
}
static GDExtensionClassCallVirtual get_virtual(void *, GDExtensionConstStringNamePtr, uint32_t) {
    return nullptr; // 明确声明不覆盖任何 virtual。
}
static void initialize(void *, GDExtensionInitializationLevel level) {
    trace("INITIALIZE", level);
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    if (initialized) fail("duplicate scene initialization");
    name_destroy = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
    if (!name_destroy) fail("StringName destructor");
    name_new(&class_name, "R49LegalRefCounted"); name_new(&parent_name, "RefCounted");
    name_new(&object_name, "Object"); name_new(&notification_name, "notification");
    name_new(&refcount_name, "get_reference_count");
    name_new(&initref_name, "init_ref"); name_new(&unref_name, "unreference"); initialized = true;
    notification_bind = method_bind(&object_name, &notification_name, 4023243586LL);
    refcount_bind = method_bind(&parent_name, &refcount_name, 3905245786LL);
    initref_bind = method_bind(&parent_name, &initref_name, 2240911060LL);
    unref_bind = method_bind(&parent_name, &unref_name, 2240911060LL);
    if (!notification_bind || !refcount_bind || !initref_bind || !unref_bind) fail("required MethodBind");
    trace("SCENE_FRAMEWORK_READY", level);
    if (!enabled) { trace("UNREGISTERED_CONTROL", level); return; }
    GDExtensionClassCreationInfo4 info{};
    info.is_virtual = false; info.is_abstract = false; info.is_exposed = true; info.is_runtime = false;
    info.create_instance_func = create_instance; info.free_instance_func = free_instance;
    info.get_virtual_func = get_virtual; info.class_userdata = nullptr;
    register_class(library, &class_name, &parent_name, &info); registered = true;
    trace("REGISTER_RETURN", level);
    // 真实 ClassDB 路径实例化，验证 mandatory callbacks 实际可调用，而非仅看类名。
    GDExtensionObjectPtr object = construct(&class_name);
    if (!object || creates != 1) fail("registered ClassDB instantiate");
    int64_t count = -1; ptrcall(refcount_bind, object, nullptr, &count);
    // 精确宿主 raw refcount 初值为1，refcount_init=1 表示尚无有效引用。
    // 首次 init_ref 必须补偿回1；若构造器已建立有效引用，此处会变2。
    if (count != 1) fail("unexpected raw RefCounted count");
    GDExtensionBool acquired = false; ptrcall(initref_bind, object, nullptr, &acquired);
    ptrcall(refcount_bind, object, nullptr, &count);
    if (!acquired || count != 1) fail("v4 effective zero reference contract");
    notify_postinitialize(object);
    GDExtensionBool last = false; ptrcall(unref_bind, object, nullptr, &last);
    if (!last) fail("selftest final reference not released");
    destroy_object(object);
    if (frees != 1) fail("free callback not called");
    trace("INSTANTIATE_FREE_PASS", level);
}
static void deinitialize(void *, GDExtensionInitializationLevel level) {
    trace("DEINITIALIZE", level);
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    if (!initialized) fail("scene teardown without initialization");
    if (registered) {
        if (creates != frees) fail("live extension instance at unregister");
        trace("UNREGISTER_ENTER", level); unregister_class(library, &class_name);
        registered = false; trace("UNREGISTER_RETURN", level);
    }
    // 必须先同等级注销类，再依逆构造顺序析构所有 Name；不会留到 DLL CRT 退场。
    name_destroy(&unref_name); name_destroy(&initref_name); name_destroy(&refcount_name);
    name_destroy(&notification_name); name_destroy(&object_name);
    name_destroy(&parent_name); name_destroy(&class_name); initialized = false;
    trace("STRINGNAMES_DESTROYED", level);
}
extern "C" __declspec(dllexport) GDExtensionBool legal_extension_control_init(
        GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr lib,
        GDExtensionInitialization *init) {
    if (!get_proc || !lib || !init) { std::fprintf(stderr, "R49_INITFAIL entry arguments\n"); return false; }
    // 两组使用完全相同 DLL，只由显式子进程环境选择是否注册。
    char selection[2]{};
    if (GetEnvironmentVariableA("R49_REGISTER_CLASS", selection, 2) != 1 ||
        (selection[0] != '0' && selection[0] != '1')) {
        std::fprintf(stderr, "R49_INITFAIL explicit R49_REGISTER_CLASS required\n"); return false;
    }
    enabled = selection[0] == '1'; library = lib;
#define API(target, type, symbol) target = reinterpret_cast<type>(get_proc(symbol)); if (!target) { std::fprintf(stderr, "R49_INITFAIL missing API %s\n", symbol); return false; }
    API(name_new, GDExtensionInterfaceStringNameNewWithUtf8Chars, "string_name_new_with_utf8_chars")
    API(get_destructor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor")
    API(register_class, GDExtensionInterfaceClassdbRegisterExtensionClass4, "classdb_register_extension_class4")
    API(unregister_class, GDExtensionInterfaceClassdbUnregisterExtensionClass, "classdb_unregister_extension_class")
    API(construct, GDExtensionInterfaceClassdbConstructObject2, "classdb_construct_object2")
    API(set_instance, GDExtensionInterfaceObjectSetInstance, "object_set_instance")
    API(destroy_object, GDExtensionInterfaceObjectDestroy, "object_destroy")
    API(method_bind, GDExtensionInterfaceClassdbGetMethodBind, "classdb_get_method_bind")
    API(ptrcall, GDExtensionInterfaceObjectMethodBindPtrcall, "object_method_bind_ptrcall")
#undef API
    init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    init->userdata = nullptr; init->initialize = initialize; init->deinitialize = deinitialize;
    trace(enabled ? "ENTRY_REGISTERED_MODE" : "ENTRY_UNREGISTERED_MODE");
    return true;
}
