#define NOMINMAX
#include <windows.h>
#include <cstdio>
#include <string>
#include <vector>

static BOOL WINAPI keep(DWORD code) { return code==CTRL_C_EVENT || code==CTRL_BREAK_EVENT; }
static unsigned long long born(HANDLE h) {
    FILETIME c{},e{},k{},u{};
    if(!GetProcessTimes(h,&c,&e,&k,&u))return 0;
    return (static_cast<unsigned long long>(c.dwHighDateTime)<<32)|c.dwLowDateTime;
}
static std::wstring quote(const std::wstring &s) { return L"\""+s+L"\""; }
static bool ready(const std::wstring &dir,const std::wstring &role) {
    FILE *f=nullptr;
    if(_wfopen_s(&f,(dir+L"/"+role+L".ready").c_str(),L"wb") || !f)return false;
    std::fprintf(f,"{\"pid\":%lu,\"creation_time\":%llu}",GetCurrentProcessId(),born(GetCurrentProcess()));
    std::fclose(f);return true;
}
static bool members(DWORD engine,DWORD keeper) {
    DWORD ids[32]{};DWORD n=GetConsoleProcessList(ids,32);
    bool e=false,k=false,s=false;
    std::printf("R57_CONSOLE count=%lu members=",n);
    for(DWORD i=0;i<n && i<32;i++)std::printf("%lu,",ids[i]);
    std::printf(" engine=%lu keeper=%lu sender=%lu\n",engine,keeper,GetCurrentProcessId());std::fflush(stdout);
    if(n!=3)return false;
    for(DWORD i=0;i<n;i++) {
        if(ids[i]==engine)e=true;else if(ids[i]==keeper)k=true;
        else if(ids[i]==GetCurrentProcessId())s=true;else return false;
    }
    return e&&k&&s;
}
int wmain(int argc,wchar_t **argv) {
    SetErrorMode(SEM_FAILCRITICALERRORS|SEM_NOGPFAULTERRORBOX|SEM_NOOPENFILEERRORBOX);
    if(argc==7 && std::wstring(argv[1])==L"--send") {
        DWORD keeper=wcstoul(argv[2],nullptr,10),engine=wcstoul(argv[3],nullptr,10);
        HANDLE kh=OpenProcess(SYNCHRONIZE|PROCESS_QUERY_LIMITED_INFORMATION,FALSE,keeper);
        HANDLE eh=OpenProcess(SYNCHRONIZE|PROCESS_QUERY_LIMITED_INFORMATION,FALSE,engine);
        HANDLE ack=OpenEventW(SYNCHRONIZE|EVENT_MODIFY_STATE,FALSE,argv[6]);
        bool valid=kh&&eh&&ack&&born(kh)==_wcstoui64(argv[4],nullptr,10)&&born(eh)==_wcstoui64(argv[5],nullptr,10)&&
            WaitForSingleObject(kh,0)==WAIT_TIMEOUT&&WaitForSingleObject(eh,0)==WAIT_TIMEOUT;
        bool sent=false;
        std::printf("R57_SENDER_IDENTITY valid=%d keeper=%lu keeper_creation=%llu engine=%lu engine_creation=%llu sender=%lu sender_creation=%llu\n",valid,keeper,kh?born(kh):0,engine,eh?born(eh):0,GetCurrentProcessId(),born(GetCurrentProcess()));std::fflush(stdout);
        // This sender is a CREATE_NO_WINDOW owned child, never a user console.
        FreeConsole();
        BOOL attached=valid?AttachConsole(keeper):FALSE;
        DWORD attach_error=attached?0:GetLastError();
        BOOL protected_sender=attached?SetConsoleCtrlHandler(keep,TRUE):FALSE;
        std::printf("R57_ATTACH ok=%d error=%lu handler=%d\n",attached,attach_error,protected_sender);std::fflush(stdout);
        if(valid && attached && protected_sender && members(engine,keeper) && members(engine,keeper))
            sent=GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT,0)!=0;
        std::printf("R57_SEND sent=%d error=%lu\n",sent,GetLastError());std::fflush(stdout);
        DWORD ack_wait=sent?WaitForSingleObject(ack,15000):WAIT_FAILED;
        std::printf("R57_EVENT_ACK wait=%lu\n",ack_wait);std::fflush(stdout);
        if(ack_wait!=WAIT_OBJECT_0) { if(kh)CloseHandle(kh); if(eh)CloseHandle(eh); if(ack)CloseHandle(ack); return 5; }
        // Detach is permitted only after the engine-side expected handler result.
        FreeConsole();
        if(kh)CloseHandle(kh);if(eh)CloseHandle(eh);if(ack)CloseHandle(ack);return 0;
    }
    if(argc==5 && std::wstring(argv[1])==L"--lock") {
        HANDLE h=CreateFileW(argv[2],GENERIC_READ,0,nullptr,OPEN_EXISTING,0,nullptr);
        if(h==INVALID_HANDLE_VALUE)return 6;
        HANDLE event=OpenEventW(SYNCHRONIZE,FALSE,argv[4]);
        if(!event || !ready(argv[3],L"lock"))return 7;
        DWORD w=WaitForSingleObject(event,150000);CloseHandle(event);CloseHandle(h);return w==WAIT_OBJECT_0?0:8;
    }
    if(argc!=8 || std::wstring(argv[1])!=L"--tree")return 2;
    const std::wstring dir=argv[2],role=argv[3],mode=argv[4];
    HANDLE gate=OpenEventW(SYNCHRONIZE,FALSE,argv[5]);
    HANDLE end=OpenEventW(SYNCHRONIZE,FALSE,argv[6]);
    if(!gate || !end)return 3;
    PROCESS_INFORMATION child{};
    if(role!=L"grandchild" && mode!=L"solo") {
        std::wstring next=role==L"root"?L"child":L"grandchild";
        std::wstring command=quote(argv[7])+L" --tree "+quote(dir)+L" "+next+L" "+mode+L" "+quote(argv[5])+L" "+quote(argv[6])+L" "+quote(argv[7]);
        STARTUPINFOW si{};si.cb=sizeof(si);
        if(!CreateProcessW(argv[7],command.data(),nullptr,nullptr,FALSE,0,nullptr,nullptr,&si,&child))return 4;
        auto until=GetTickCount64()+10000;
        while(GetFileAttributesW((dir+L"/"+next+L".ready").c_str())==INVALID_FILE_ATTRIBUTES && GetTickCount64()<until)SwitchToThread();
        CloseHandle(child.hThread);CloseHandle(child.hProcess);
    }
    if(!ready(dir,role))return 9;
    DWORD waited=WaitForSingleObject(role==L"root"?gate:end,150000);
    CloseHandle(gate);CloseHandle(end);
    if(role==L"root" && mode==L"crash")RaiseException(0xE0570001,EXCEPTION_NONCONTINUABLE,0,nullptr);
    return waited==WAIT_OBJECT_0?0:10;
}