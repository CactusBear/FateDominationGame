#include "atomic_file_replace_core.hpp"
#include <system_error>
#include <vector>
#include <cstring>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#else
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif
namespace fate {
namespace fs = std::filesystem;
static ReplaceResult fail(const char *stage, int64_t code=0) { return {false,stage,code}; }
// Reject links in every existing path component. This is a preflight, NOT a hostile-race defense.
static bool no_links(const fs::path &path) {
    fs::path current;
    for (const auto &component:path) {
        current /= component;
#ifdef _WIN32
        DWORD a=GetFileAttributesW(current.c_str());
        if (a==INVALID_FILE_ATTRIBUTES || (a&FILE_ATTRIBUTE_REPARSE_POINT)) return false;
#else
        struct stat s{};
        if (lstat(current.c_str(),&s)!=0 || S_ISLNK(s.st_mode)) return false;
#endif
    }
    return true;
}
ReplaceResult replace_validated_file(const fs::path &temporary,const fs::path &target,uint64_t size) {
    try {
        if (temporary.native().find(fs::path::value_type(0))!=fs::path::string_type::npos ||
            target.native().find(fs::path::value_type(0))!=fs::path::string_type::npos) return fail("embedded_nul");
#ifdef _WIN32
        // Reject alternate data streams and device namespace spellings, not just link attributes.
        if (temporary.root_name().native().size()!=2 || target.root_name().native().size()!=2)
            return fail("drive_path_required");
        for(const auto &c:temporary.relative_path()) if(c.native().find(L':')!=std::wstring::npos) return fail("alternate_stream_rejected");
        for(const auto &c:target.relative_path()) if(c.native().find(L':')!=std::wstring::npos) return fail("alternate_stream_rejected");
#endif
        if (!temporary.is_absolute() || !target.is_absolute()) return fail("absolute_path_required");
        if (temporary.lexically_normal()!=temporary || target.lexically_normal()!=target)
            return fail("normalized_path_required");
        if (temporary==target) return fail("same_path");
        if (!no_links(temporary) || !no_links(target)) return fail("missing_or_link_path");
        std::error_code error;
        bool same_parent=fs::equivalent(temporary.parent_path(),target.parent_path(),error);
        if(error || !same_parent) return fail("same_directory_required",error.value());
#ifdef _WIN32
        // Local fixed volume only: network/removable filesystem atomicity is outside this contract.
        wchar_t volume[MAX_PATH]{};
        if (!GetVolumePathNameW(target.c_str(),volume,MAX_PATH)) return fail("volume",GetLastError());
        if (GetDriveTypeW(volume)!=DRIVE_FIXED) return fail("local_fixed_volume_required");
        struct Handle { HANDLE value=INVALID_HANDLE_VALUE; ~Handle(){if(value!=INVALID_HANDLE_VALUE) CloseHandle(value);} };
        Handle src, dst;
        src.value=CreateFileW(temporary.c_str(),FILE_READ_ATTRIBUTES|DELETE,
            FILE_SHARE_READ|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
        if(src.value==INVALID_HANDLE_VALUE) return fail("open_temporary",GetLastError());
        dst.value=CreateFileW(target.c_str(),FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
        if(dst.value==INVALID_HANDLE_VALUE) return fail("open_target",GetLastError());
        if(GetFileType(src.value)!=FILE_TYPE_DISK || GetFileType(dst.value)!=FILE_TYPE_DISK)
            return fail("disk_file_required");
        BY_HANDLE_FILE_INFORMATION s{},d{};
        if(!GetFileInformationByHandle(src.value,&s) || !GetFileInformationByHandle(dst.value,&d))
            return fail("stat",GetLastError());
        const DWORD bad=FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT;
        if((s.dwFileAttributes&bad)||(d.dwFileAttributes&bad)||s.nNumberOfLinks!=1||d.nNumberOfLinks!=1)
            return fail("regular_single_link_required");
        if(s.dwVolumeSerialNumber==d.dwVolumeSerialNumber && s.nFileIndexHigh==d.nFileIndexHigh && s.nFileIndexLow==d.nFileIndexLow)
            return fail("same_file");
        uint64_t actual=(uint64_t(s.nFileSizeHigh)<<32)|s.nFileSizeLow;
        if(actual!=size) return fail("validated_size_changed");
        // Native handle rename: never delete the destination or copy across volumes.
        // Win10+ FileRenameInfoEx POSIX semantics lets existing shared-delete readers
        // retain the old object while new opens see the new object. Unsupported API fails closed.
        CloseHandle(dst.value);dst.value=INVALID_HANDLE_VALUE;
        const std::wstring name=target.native();
        const size_t bytes=name.size()*sizeof(wchar_t);
        if(bytes>32760*sizeof(wchar_t)) return fail("path_too_long");
        std::vector<unsigned char> storage(sizeof(FILE_RENAME_INFO)+bytes,0);
        auto *info=reinterpret_cast<FILE_RENAME_INFO *>(storage.data());
        info->Flags=FILE_RENAME_FLAG_REPLACE_IF_EXISTS|FILE_RENAME_FLAG_POSIX_SEMANTICS;
        info->RootDirectory=nullptr;
        info->FileNameLength=static_cast<DWORD>(bytes);
        std::memcpy(info->FileName,name.data(),bytes);
        if(!SetFileInformationByHandle(src.value,FileRenameInfoEx,info,static_cast<DWORD>(storage.size())))
            return fail("native_replace",GetLastError());
#else
        struct Fd { int value=-1; ~Fd(){if(value>=0) close(value);} } src,dst;
        src.value=open(temporary.c_str(),O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
        if(src.value<0) return fail("open_temporary",errno);
        dst.value=open(target.c_str(),O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
        if(dst.value<0) return fail("open_target",errno);
        struct stat s{},d{};
        if(fstat(src.value,&s)!=0||fstat(dst.value,&d)!=0) return fail("stat",errno);
        if(!S_ISREG(s.st_mode)||!S_ISREG(d.st_mode)||s.st_nlink!=1||d.st_nlink!=1)
            return fail("regular_single_link_required");
        if(s.st_dev==d.st_dev && s.st_ino==d.st_ino) return fail("same_file");
        if(uint64_t(s.st_size)!=size) return fail("validated_size_changed");
        // POSIX rename within one directory is an atomic namespace operation.
        // Caller serializes writers: open/fstat cannot prevent pathname races on their own.
        if(::rename(temporary.c_str(),target.c_str())!=0) return fail("native_replace",errno);
#endif
        return {true,"published",0};
    } catch(const fs::filesystem_error &e) { return fail("filesystem_exception",e.code().value()); }
      catch(const std::exception &) { return fail("exception"); }
}
}
