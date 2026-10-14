#include "atomic_file_replace_core.hpp"
#include "temporary_cleanup_core.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
using namespace godot;
class FateAtomicFileReplace : public RefCounted {
    GDCLASS(FateAtomicFileReplace, RefCounted);
    static bool identity(const Dictionary &value, fate::CleanupIdentity &out) {
        Variant volume = value.get("volume", Variant());
        Variant file_index = value.get("file_index", Variant());
        if (volume.get_type() != Variant::INT || file_index.get_type() != Variant::INT) return false;
        int64_t volume_value = volume;
        int64_t index_value = file_index;
        if (volume_value < 0 || volume_value > UINT32_MAX || index_value <= 0) return false;
        out.volume = static_cast<uint32_t>(volume_value);
        out.file_index = static_cast<uint64_t>(index_value);
        return true;
    }
    static bool has_nul(const String &value) {
        for (int64_t i = 0; i < value.length(); ++i) if (value[i] == 0) return true;
        return false;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("replace_validated_file", "temporary_absolute_path", "target_absolute_path", "validated_size"),
            &FateAtomicFileReplace::replace_validated_file);
        ClassDB::bind_method(D_METHOD("remove_verified", "approved_root_absolute_path", "file_absolute_path",
            "approved_root_identity", "parent_identity", "file_identity", "validated_size", "sha256"),
            &FateAtomicFileReplace::remove_verified);
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
    Dictionary remove_verified(const String &approved_root, const String &file,
        const Dictionary &approved_root_identity, const Dictionary &parent_identity,
        const Dictionary &file_identity, int64_t size, const String &sha256) {
        fate::TemporaryCleanupResult result{false, "invalid_argument", 0, 0};
        fate::TemporaryCleanupRequest request;
        request.kind = fate::CleanupArtifactKind::temporary_file;
        request.size = size >= 0 ? static_cast<uint64_t>(size) : 0;
        auto hash = sha256.utf8();
        request.sha256 = std::string(hash.get_data(), static_cast<size_t>(hash.length()));
        fate::CleanupIdentity root_id, parent_id, file_id;
        if (size >= 0 && !has_nul(approved_root) && !has_nul(file) &&
            identity(approved_root_identity, root_id) && identity(parent_identity, parent_id) &&
            identity(file_identity, file_id)) {
#ifdef _WIN32
            auto root = approved_root.utf16();
            auto path = file.utf16();
            request.approved_root = std::filesystem::path(reinterpret_cast<const wchar_t *>(root.get_data()));
            request.file = std::filesystem::path(reinterpret_cast<const wchar_t *>(path.get_data()));
#else
            auto root = approved_root.utf8();
            auto path = file.utf8();
            request.approved_root = std::filesystem::path(root.get_data());
            request.file = std::filesystem::path(path.get_data());
#endif
            request.approved_root_identity = root_id;
            request.parent_identity = parent_id;
            request.file_identity = file_id;
            result = fate::delete_approved_temporary(request);
        }
        Dictionary out;
        out["ok"] = result.ok;
        out["stage"] = String(result.stage.c_str());
        out["native_error"] = result.native_error;
        out["removed_bytes"] = static_cast<int64_t>(result.removed_bytes);
        out["recovery_required"] = result.recovery_required;
        return out;
    }
};
void register_fate_atomic_file_replace() { GDREGISTER_CLASS(FateAtomicFileReplace); }
