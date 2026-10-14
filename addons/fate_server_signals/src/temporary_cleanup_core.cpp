#include "temporary_cleanup_core.hpp"
#include <algorithm>
#include <array>
#include <vector>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#include <bcrypt.h>
#endif

namespace fate {
namespace fs = std::filesystem;
static TemporaryCleanupResult fail(const char *stage, int64_t error=0) {
    return {false,stage,error,0};
}
#ifdef _WIN32
namespace {
struct Handle {
    HANDLE value=INVALID_HANDLE_VALUE;
    Handle() = default;
    explicit Handle(HANDLE h):value(h) {}
    ~Handle() { if(value!=INVALID_HANDLE_VALUE) CloseHandle(value); }
    Handle(Handle &&other) noexcept:value(other.value) {other.value=INVALID_HANDLE_VALUE;}
    Handle(const Handle &) = delete;
    Handle &operator=(const Handle &) = delete;
};
CleanupIdentity identity(const BY_HANDLE_FILE_INFORMATION &i) {
    return {i.dwVolumeSerialNumber,(uint64_t(i.nFileIndexHigh)<<32)|i.nFileIndexLow};
}
uint64_t length(const BY_HANDLE_FILE_INFORMATION &i) {
    return (uint64_t(i.nFileSizeHigh)<<32)|i.nFileSizeLow;
}
bool same(const fs::path &a,const fs::path &b) {
    auto x=a.native(),y=b.native();
    return CompareStringOrdinal(x.c_str(),static_cast<int>(x.size()),y.c_str(),
        static_cast<int>(y.size()),TRUE)==CSTR_EQUAL;
}
bool strict_path(const fs::path &p) {
    const auto name=p.native();
    if(name.empty() || name.size()>32760 || name.find(L'\0')!=std::wstring::npos ||
        !p.is_absolute() || p.root_name().native().size()!=2 || p.root_name().native()[1]!=L':' ||
        !((name[0]>=L'A' && name[0]<=L'Z') || (name[0]>=L'a' && name[0]<=L'z')) ||
        p.lexically_normal()!=p) return false;
    for(const auto &part:p.relative_path()) {
        auto s=part.native();
        if(s.empty() || s==L"." || s==L".." || s.back()==L'.' || s.back()==L' ' ||
            s.find_first_of(L":*?\"<>|")!=std::wstring::npos ||
            std::any_of(s.begin(),s.end(),[](wchar_t c){return c<32;})) return false;
        auto base=s.substr(0,s.find(L'.'));
        for(auto &c:base) if(c>=L'a' && c<=L'z') c-=L'a'-L'A';
        if(base==L"CON" || base==L"PRN" || base==L"AUX" || base==L"NUL" ||
            base==L"CONIN$" || base==L"CONOUT$" ||
            ((base.size()==4 && (base.substr(0,3)==L"COM" || base.substr(0,3)==L"LPT")) &&
             ((base[3]>=L'1' && base[3]<=L'9') || base[3]==L'\u00b9' || base[3]==L'\u00b2' || base[3]==L'\u00b3')))
            return false;
    }
    return true;
}
bool contained(const fs::path &root,const fs::path &path) {
    auto r=root.begin(),p=path.begin();
    for(;r!=root.end();++r,++p) if(p==path.end() || !same(*r,*p)) return false;
    return p!=path.end(); // root itself is not an artifact
}
bool exact_handle_path(HANDLE h,fs::path expected) {
    expected.make_preferred();
    DWORD size=GetFinalPathNameByHandleW(h,nullptr,0,FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
    if(!size) return false;
    std::vector<wchar_t> buf(size+1);
    DWORD used=GetFinalPathNameByHandleW(h,buf.data(),static_cast<DWORD>(buf.size()),FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
    if(!used || used>=buf.size()) return false;
    return same(fs::path(std::wstring(buf.data(),used)),fs::path(L"\\\\?\\"+expected.native()));
}
bool regular(const BY_HANDLE_FILE_INFORMATION &i) {
    return !(i.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT)) && i.nNumberOfLinks==1;
}
// One hash implementation, Windows' provider, bytes read from the exclusive handle.
TemporaryCleanupResult sha256(HANDLE file,uint64_t expected,std::string &out) {
    struct Algorithm {
        BCRYPT_ALG_HANDLE value=nullptr;
        ~Algorithm(){if(value) BCryptCloseAlgorithmProvider(value,0);}
    } algorithm;
    struct Hash {
        BCRYPT_HASH_HANDLE value=nullptr;
        ~Hash(){if(value) BCryptDestroyHash(value);}
    };
    auto status=BCryptOpenAlgorithmProvider(&algorithm.value,BCRYPT_SHA256_ALGORITHM,nullptr,0);
    if(status<0) return fail("sha256_provider",status);
    DWORD object_size=0,used=0;
    status=BCryptGetProperty(algorithm.value,BCRYPT_OBJECT_LENGTH,reinterpret_cast<PUCHAR>(&object_size),sizeof(object_size),&used,0);
    if(status<0) return fail("sha256_properties",status);
    std::vector<unsigned char> object(object_size);
    Hash hash; // destroyed before the backing object and algorithm on every return
    status=BCryptCreateHash(algorithm.value,&hash.value,object.data(),object_size,nullptr,0,0);
    if(status<0) return fail("sha256_create",status);

    LARGE_INTEGER zero{};
    if(!SetFilePointerEx(file,zero,nullptr,FILE_BEGIN)) return fail("hash_seek",GetLastError());
    std::array<unsigned char,65536> buffer{};
    uint64_t total=0;
    for(;;) {
        DWORD count=0;
        if(!ReadFile(file,buffer.data(),static_cast<DWORD>(buffer.size()),&count,nullptr)) return fail("hash_read",GetLastError());
        if(!count) break;
        if(total>expected || count>expected-total) return fail("size_changed");
        total+=count;
        status=BCryptHashData(hash.value,buffer.data(),count,0);
        if(status<0) return fail("sha256_update",status);
    }
    if(total!=expected) return fail("size_changed");
    std::array<unsigned char,32> digest{};
    status=BCryptFinishHash(hash.value,digest.data(),static_cast<ULONG>(digest.size()),0);
    if(status<0) return fail("sha256_finish",status);
    constexpr char hex[]="0123456789abcdef";
    out.clear();out.reserve(64);
    for(auto byte:digest){out.push_back(hex[byte>>4]);out.push_back(hex[byte&15]);}
    return {true,"hashed",0,0};
}
} // anonymous namespace
struct TemporaryCleanupLease::State {
    TemporaryCleanupRequest request;
    std::vector<Handle> ancestors;
    Handle file;
    bool attempted=false;
    bool disposition_committed=false;
    bool absence_confirmed=false;
};
#else
struct TemporaryCleanupLease::State {};
#endif

TemporaryCleanupLease::TemporaryCleanupLease() = default;
TemporaryCleanupLease::~TemporaryCleanupLease() = default;
TemporaryCleanupLease::TemporaryCleanupLease(TemporaryCleanupLease &&) noexcept = default;
TemporaryCleanupLease &TemporaryCleanupLease::operator=(TemporaryCleanupLease &&) noexcept = default;

TemporaryCleanupResult TemporaryCleanupLease::acquire(const TemporaryCleanupRequest &request,TemporaryCleanupLease &out) {
#ifdef _WIN32
    try {
        if(out.state_) return fail("lease_already_held");
        if(request.kind!=CleanupArtifactKind::temporary_file) return fail("not_explicit_temporary_file");
        if(!strict_path(request.approved_root) || !strict_path(request.file)) return fail("unsafe_path");
        if(!contained(request.approved_root,request.file)) return fail("outside_approved_root");
        if(request.sha256.size()!=64 || !std::all_of(request.sha256.begin(),request.sha256.end(),
            [](char c){return (c>='0' && c<='9') || (c>='a' && c<='f');})) return fail("invalid_sha256");
        if(!request.approved_root_identity.file_index || !request.parent_identity.file_index ||
            !request.file_identity.file_index) return fail("missing_identity");
        wchar_t volume[MAX_PATH]{};
        if(!GetVolumePathNameW(request.file.c_str(),volume,MAX_PATH)) return fail("volume",GetLastError());
        if(GetDriveTypeW(volume)!=DRIVE_FIXED) return fail("local_fixed_volume_required");
        wchar_t filesystem[MAX_PATH]{};
        if(!GetVolumeInformationW(volume,nullptr,0,nullptr,nullptr,nullptr,filesystem,MAX_PATH))
            return fail("filesystem",GetLastError());
        // This API's persisted identity is NTFS's 64-bit file index. ReFS needs a
        // distinct 128-bit identity contract; never silently truncate that identity.
        if(std::wstring(filesystem)!=L"NTFS") return fail("ntfs_identity_required");
        auto state=std::make_unique<State>();
        state->request=request;
        fs::path current=request.file.root_path();
        std::vector<fs::path> dirs{current};
        for(const auto &part:request.file.parent_path().relative_path()) {current/=part;dirs.push_back(current);}
        // Pin root first, then one child at a time. Deny directory writers AND rename/delete;
        // OPEN_REPARSE_POINT tests the object itself, never traverses the final component.
        bool root_seen=false;
        for(const auto &directory:dirs) {
            state->ancestors.emplace_back(CreateFileW(directory.c_str(),FILE_READ_ATTRIBUTES,
                FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,nullptr));
            auto h=state->ancestors.back().value;
            if(h==INVALID_HANDLE_VALUE) return fail("pin_ancestor",GetLastError());
            BY_HANDLE_FILE_INFORMATION info{};
            if(GetFileType(h)!=FILE_TYPE_DISK || !GetFileInformationByHandle(h,&info)) return fail("ancestor_stat",GetLastError());
            if(!(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY) || (info.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT))
                return fail("ancestor_not_plain_directory");
            if(!exact_handle_path(h,directory)) return fail("ancestor_path_changed");
            if(same(directory,request.approved_root)) {
                root_seen=true;
                if(!(identity(info)==request.approved_root_identity)) return fail("approved_root_identity_changed");
            }
            if(same(directory,request.file.parent_path()) && !(identity(info)==request.parent_identity))
                return fail("parent_identity_changed");
        }
        if(!root_seen) return fail("approved_root_not_pinned");
        state->file.value=CreateFileW(request.file.c_str(),GENERIC_READ|DELETE,0,nullptr,OPEN_EXISTING,
            FILE_FLAG_OPEN_REPARSE_POINT|FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_SEQUENTIAL_SCAN,nullptr);
        if(state->file.value==INVALID_HANDLE_VALUE) return fail("exclusive_open",GetLastError());
        BY_HANDLE_FILE_INFORMATION info{};
        if(GetFileType(state->file.value)!=FILE_TYPE_DISK || !GetFileInformationByHandle(state->file.value,&info))
            return fail("file_stat",GetLastError());
        if(!regular(info)) return fail("regular_single_link_required");
        if(!(identity(info)==request.file_identity)) return fail("file_identity_changed");
        if(!exact_handle_path(state->file.value,request.file)) return fail("file_path_changed");
        out.state_=std::move(state);
        return {true,"exclusive_handle_acquired",0,0};
    } catch(const fs::filesystem_error &e) {return fail("filesystem_exception",e.code().value());}
      catch(const std::exception &) {return fail("exception");}
#else
    (void)request;(void)out;
    return fail("unsupported_platform");
#endif
}

TemporaryCleanupResult TemporaryCleanupLease::verify_and_delete() {
#ifdef _WIN32
    if(!state_) return fail("inactive_lease");
    if(state_->attempted || state_->file.value==INVALID_HANDLE_VALUE) {
        auto result=fail("inactive_lease");
        result.recovery_required=state_->disposition_committed && !state_->absence_confirmed;
        return result;
    }
    state_->attempted=true; // one attempt; a refusal never silently retries under changed evidence
    auto uncertain=[this](const char *stage,int64_t error=0) {
        auto result=fail(stage,error);
        result.recovery_required=state_->disposition_committed;
        return result;
    };
    try {
        auto &r=state_->request;
        auto h=state_->file.value;
        BY_HANDLE_FILE_INFORMATION before{};
        if(!GetFileInformationByHandle(h,&before)) return fail("file_stat",GetLastError());
        if(!regular(before)) return fail("regular_single_link_required");
        if(!(identity(before)==r.file_identity)) return fail("file_identity_changed");
        if(length(before)!=r.size) return fail("size_changed");
        std::string digest;
        auto hashed=sha256(h,r.size,digest);
        if(!hashed.ok) return hashed;
        if(digest!=r.sha256) return fail("sha256_changed");
        BY_HANDLE_FILE_INFORMATION after{};
        if(!GetFileInformationByHandle(h,&after)) return fail("file_restat",GetLastError());
        if(!regular(after) || !(identity(after)==r.file_identity) || length(after)!=r.size ||
            CompareFileTime(&before.ftLastWriteTime,&after.ftLastWriteTime)!=0) return fail("file_changed_during_hash");
        if(!exact_handle_path(h,r.file)) return fail("file_path_changed");
        // Ordinary disposition, not POSIX unlink: existing mappings/unsupported FS fail closed.
        FILE_DISPOSITION_INFO disposition{};disposition.DeleteFile=TRUE;
        if(!SetFileInformationByHandle(h,FileDispositionInfo,&disposition,sizeof(disposition)))
            return fail("handle_delete",GetLastError());
        state_->disposition_committed=true;
        if(!CloseHandle(h)) return uncertain("delete_close_unconfirmed",GetLastError());
        state_->file.value=INVALID_HANDLE_VALUE;
        // Ancestor pins remain alive for this exact-target readback and audit receipt.
        Handle readback(CreateFileW(r.file.c_str(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
            nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT|FILE_FLAG_BACKUP_SEMANTICS,nullptr));
        if(readback.value!=INVALID_HANDLE_VALUE) return uncertain("delete_readback_exists");
        DWORD error=GetLastError();
        if(error!=ERROR_FILE_NOT_FOUND) return uncertain("delete_readback_unconfirmed",error);
        state_->absence_confirmed=true;
        return {true,"deleted_absence_confirmed",0,r.size};
    } catch(const fs::filesystem_error &e) {return uncertain("filesystem_exception",e.code().value());}
      catch(const std::exception &) {return uncertain("exception");}
#else
    return fail("unsupported_platform");
#endif
}

TemporaryCleanupResult delete_approved_temporary(const TemporaryCleanupRequest &request) {
    TemporaryCleanupLease lease;
    auto result=TemporaryCleanupLease::acquire(request,lease);
    return result.ok ? lease.verify_and_delete() : result;
}
} // namespace fate