#include "temporary_cleanup_core.hpp"
#define NOMINMAX
#include <windows.h>
#include <iostream>
#include <string>

static void result(const fate::TemporaryCleanupResult &r) {
    std::cout << "{\"ok\":" << (r.ok ? "true" : "false")
              << ",\"stage\":\"" << r.stage << "\",\"native_error\":" << r.native_error
              << ",\"removed_bytes\":" << r.removed_bytes
              << ",\"recovery_required\":" << (r.recovery_required ? "true" : "false") << "}" << std::endl;
}
static fate::CleanupIdentity identity(const wchar_t *path) {
    HANDLE h=CreateFileW(path,FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
        nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
    BY_HANDLE_FILE_INFORMATION i{};
    if(h==INVALID_HANDLE_VALUE || !GetFileInformationByHandle(h,&i)) ExitProcess(10);
    CloseHandle(h);
    return {i.dwVolumeSerialNumber,(uint64_t(i.nFileIndexHigh)<<32)|i.nFileIndexLow};
}
int wmain(int argc,wchar_t **argv) {
    // Parent assigns this exact child to its own Job before authorizing work.
    std::string command;
    if(!std::getline(std::cin,command) || command!="GO") return 11;
    if(argc<3) return 12;
    std::wstring mode=argv[1];
    if(mode==L"inspect") {
        auto i=identity(argv[2]);
        std::cout << "{\"volume\":" << i.volume << ",\"file_index\":" << i.file_index << "}" << std::endl;
        return 0;
    }
    if(mode==L"map") {
        HANDLE h=CreateFileW(argv[2],GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
            nullptr,OPEN_EXISTING,0,nullptr);
        if(h==INVALID_HANDLE_VALUE) return 14;
        HANDLE mapping=CreateFileMappingW(h,nullptr,PAGE_READWRITE,0,0,nullptr);
        if(!mapping) return 15;
        void *view=MapViewOfFile(mapping,FILE_MAP_WRITE,0,0,0);
        if(!view) return 16;
        CloseHandle(h); // mapping survives after the ordinary I/O HANDLE closes
        result({true,"mapped",0,0});
        std::getline(std::cin,command);
        UnmapViewOfFile(view);CloseHandle(mapping);
        return 0;
    }
    if(mode==L"occupy" || mode==L"tryread" || mode==L"trywrite" || mode==L"trydelete") {
        DWORD access=mode==L"trywrite" ? GENERIC_WRITE : mode==L"trydelete" ? DELETE : GENERIC_READ;
        HANDLE h=CreateFileW(argv[2],access,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
            nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
        if(h==INVALID_HANDLE_VALUE) {result({false,"open",GetLastError(),0});return 0;}
        result({true,"opened",0,0});
        if(mode==L"occupy") std::getline(std::cin,command);
        CloseHandle(h);
        return 0;
    }
    if(argc!=14) return 13;
    fate::TemporaryCleanupRequest r;
    r.approved_root=argv[2];r.file=argv[3];
    r.approved_root_identity={uint32_t(std::stoul(argv[4])),std::stoull(argv[5])};
    r.parent_identity={uint32_t(std::stoul(argv[6])),std::stoull(argv[7])};
    r.file_identity={uint32_t(std::stoul(argv[8])),std::stoull(argv[9])};
    r.size=std::stoull(argv[10]);
    std::wstring hash=argv[11];for(wchar_t c:hash) r.sha256.push_back(static_cast<char>(c));
    r.kind=std::wstring(argv[12])==L"temporary" ? fate::CleanupArtifactKind::temporary_file :
        std::wstring(argv[12])==L"archive" ? fate::CleanupArtifactKind::archive : fate::CleanupArtifactKind::unspecified;
    if(mode==L"delete") { result(fate::delete_approved_temporary(r));return 0; }
    fate::TemporaryCleanupLease lease;
    auto acquired=fate::TemporaryCleanupLease::acquire(r,lease);
    result(acquired);
    if(!acquired.ok) return 0;
    if(mode==L"lease_contract") {
        result(fate::TemporaryCleanupLease::acquire(r,lease));
        fate::TemporaryCleanupLease moved(std::move(lease));
        result(lease.verify_and_delete());
        fate::TemporaryCleanupLease assigned;
        assigned=std::move(moved);
        result(moved.verify_and_delete());
        result(assigned.verify_and_delete());
        result(assigned.verify_and_delete());
        return 0;
    }
    if(!std::getline(std::cin,command)) return 0;
    if(command=="CRASH") TerminateProcess(GetCurrentProcess(),73);
    if(command=="DELETE") result(lease.verify_and_delete());
    // CLOSE/EOF destroy lease without deletion.
    return 0;
}