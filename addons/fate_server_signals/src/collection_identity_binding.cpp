#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <cstdint>
#include <cstring>

using namespace godot;

// Godot 4.x 当前目标ABI的Array/Dictionary opaque builtin存储均为8字节
// 引用句柄。只复制候选键，不解引用、不读私有对象、不访问内容。
// 这不是未来ABI的承诺：尺寸编译门及is_supported运行门必须同时通过。
// 最终身份相等由GDScript is_same判定；本键不能序列化或跨进程使用。
static_assert(sizeof(Array) == sizeof(int64_t), "Unsupported Array opaque handle ABI");
static_assert(sizeof(Dictionary) == sizeof(int64_t), "Unsupported Dictionary opaque handle ABI");

static int64_t candidate_key(const Variant &value) {
    int64_t key = 0;
    if (value.get_type() == Variant::ARRAY) {
        const Array reference = value;
        std::memcpy(&key, reference._native_ptr(), sizeof(key));
    } else if (value.get_type() == Variant::DICTIONARY) {
        const Dictionary reference = value;
        std::memcpy(&key, reference._native_ptr(), sizeof(key));
    }
    return key;
}

static bool valid_pair(const Variant &a, const Variant &alias, const Variant &distinct) {
    return candidate_key(a) != 0 &&
        UtilityFunctions::is_same(a, alias) && candidate_key(a) == candidate_key(alias) &&
        !UtilityFunctions::is_same(a, distinct) && candidate_key(a) != candidate_key(distinct);
}

class FateCollectionIdentity : public RefCounted {
    GDCLASS(FateCollectionIdentity, RefCounted);
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("is_supported", "engine_hash"), &FateCollectionIdentity::is_supported);
        ClassDB::bind_method(D_METHOD("candidate_key", "value"), &FateCollectionIdentity::key_for);
    }
public:
    int64_t key_for(const Variant &value) const { return candidate_key(value); }
    bool is_supported(const String &engine_hash) const {
        // opaque内容不是跨版本公共承诺，只接受已核对id/is_same_instance源码的引擎。
        if (!engine_hash.begins_with("ed1daf0bf")) return false;
        Array a;
        Array aa = a;
        Array b;
        Dictionary d;
        Dictionary dd = d;
        Dictionary e;
        if (!valid_pair(a, aa, b) || !valid_pair(d, dd, e)) return false;
        // 内容/大小改变不改变引用句柄；空集合也必须有独立身份。
        const int64_t ak = candidate_key(a);
        const int64_t dk = candidate_key(d);
        a.append(1);
        d[String("value")] = 1;
        if (candidate_key(a) != ak || candidate_key(aa) != ak ||
                candidate_key(d) != dk || candidate_key(dd) != dk) return false;
        return valid_pair(a, aa, a.duplicate()) && valid_pair(d, dd, d.duplicate());
    }
};

void register_fate_collection_identity() {
    GDREGISTER_CLASS(FateCollectionIdentity);
}