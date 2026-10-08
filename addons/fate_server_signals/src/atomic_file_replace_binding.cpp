#include "atomic_file_replace_core.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
using namespace godot;
class FateAtomicFileReplace : public RefCounted {
    GDCLASS(FateAtomicFileReplace, RefCounted);
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("replace_validated_file", "temporary_absolute_path", "target_absolute_path", "validated_size"),
            &FateAtomicFileReplace::replace_validated_file);
    }
public:
    Dictionary replace_validated_file(const String &temporary,const String &target,int64_t size) {
        fate::ReplaceResult result{false,"invalid_argument",0};
        // Reject embedded NUL before constructing native C paths; never silently truncate.
        bool has_nul=false;
        for(int64_t i=0;i<temporary.length();++i) if(temporary[i]==0) has_nul=true;
        for(int64_t i=0;i<target.length();++i) if(target[i]==0) has_nul=true;
        if(size>=0 && !has_nul) {
#ifdef _WIN32
            auto t=temporary.utf16(), d=target.utf16();
            result=fate::replace_validated_file(std::filesystem::path(reinterpret_cast<const wchar_t *>(t.get_data())),
                std::filesystem::path(reinterpret_cast<const wchar_t *>(d.get_data())),uint64_t(size));
#else
            auto t=temporary.utf8(), d=target.utf8();
            result=fate::replace_validated_file(std::filesystem::path(t.get_data()),std::filesystem::path(d.get_data()),uint64_t(size));
#endif
        }
        Dictionary out;
        out["ok"]=result.ok;
        out["stage"]=String(result.stage.c_str());
        out["native_error"]=result.native_error;
        out["durability_guaranteed"]=false;
        return out;
    }
};
void register_fate_atomic_file_replace() { GDREGISTER_CLASS(FateAtomicFileReplace); }
