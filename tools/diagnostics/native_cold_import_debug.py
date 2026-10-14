"""Owned-process Windows debugger for fresh GDExtension cold imports.

Uses existing MSVC/SDK only; never attaches, changes system policies or edits a
production DLL. DbgHelp symbols are local-only (no symbol server).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

DEBUGGER_CPP = r'''
#define NOMINMAX
#include <windows.h>
#include <dbghelp.h>
#include <cstdio>
#include <cstdint>
#include <map>
#include <string>
#include <vector>

struct Module { DWORD64 base; DWORD size; std::wstring path; };
std::map<DWORD64,Module> modules;
DWORD64 image_base=0,watch_rva=0;
std::vector<DWORD64> trace_rvas;
std::map<DWORD64,unsigned char> breakpoints;
void module(HANDLE process, HANDLE file, DWORD64 base) {
    wchar_t path[32768]{};
    if(file && file!=INVALID_HANDLE_VALUE) GetFinalPathNameByHandleW(file,path,32768,0);
    IMAGE_DOS_HEADER dos{}; IMAGE_NT_HEADERS64 nt{}; SIZE_T got;
    DWORD size=0;
    if(ReadProcessMemory(process,(LPCVOID)base,&dos,sizeof(dos),&got) &&
       ReadProcessMemory(process,(LPCVOID)(base+dos.e_lfanew),&nt,sizeof(nt),&got)) size=nt.OptionalHeader.SizeOfImage;
    modules[base]={base,size,path};
    SymLoadModuleExW(process,file,path,nullptr,base,size,nullptr,0);
    std::printf("MODULE base=0x%llx size=0x%lx path=%ls\n",base,size,path);
}
void address(HANDLE process, DWORD64 pc) {
    auto it=modules.upper_bound(pc);
    if(it!=modules.begin()) { --it; auto &m=it->second;
        if(pc < m.base+m.size) std::printf(" module=%ls offset=0x%llx",m.path.c_str(),pc-m.base);
    }
    char buf[sizeof(SYMBOL_INFO)+2048]{};
    auto *sym=(SYMBOL_INFO*)buf; sym->SizeOfStruct=sizeof(SYMBOL_INFO); sym->MaxNameLen=2047; DWORD64 displacement=0;
    if(SymFromAddr(process,pc,&displacement,sym)) std::printf(" symbol=%s+0x%llx",sym->Name,displacement);
    else std::printf(" symbol_error=%lu",GetLastError());
    IMAGEHLP_LINE64 line{}; line.SizeOfStruct=sizeof(line); DWORD delta=0;
    if(SymGetLineFromAddr64(process,pc,&delta,&line)) std::printf(" source=%s:%lu",line.FileName,line.LineNumber);
    std::printf("\n");
}
void exception(HANDLE process,HANDLE thread,const DEBUG_EVENT &event) {
    const auto &e=event.u.Exception; const auto &r=e.ExceptionRecord;
    std::printf("%s pid=%lu tid=%lu first_chance=%lu code=0x%08lx flags=0x%lx address=0x%llx parameters=%lu\n",
        e.dwFirstChance==2?"TIMEOUT_SNAPSHOT":"EXCEPTION",event.dwProcessId,event.dwThreadId,e.dwFirstChance,r.ExceptionCode,r.ExceptionFlags,(DWORD64)r.ExceptionAddress,r.NumberParameters);
    if(watch_rva && image_base) {
        DWORD64 value=0;SIZE_T count=0;
        if(ReadProcessMemory(process,(LPCVOID)(image_base+watch_rva),&value,sizeof(value),&count))
            std::printf("WATCH rva=0x%llx address=0x%llx value=0x%llx\n",watch_rva,image_base+watch_rva,value);
        else std::printf("WATCH_ERROR %lu\n",GetLastError());
    }
    for(DWORD i=0;i<r.NumberParameters;i++) std::printf("PARAM %lu=0x%llx\n",i,(DWORD64)r.ExceptionInformation[i]);
    address(process,(DWORD64)r.ExceptionAddress);
    CONTEXT ctx{}; ctx.ContextFlags=CONTEXT_ALL;
    if(!GetThreadContext(thread,&ctx)) { std::printf("CONTEXT_ERROR %lu\n",GetLastError()); return; }
    std::printf("REG RIP=%llx RSP=%llx RBP=%llx RAX=%llx RBX=%llx RCX=%llx RDX=%llx RSI=%llx RDI=%llx\n",ctx.Rip,ctx.Rsp,ctx.Rbp,ctx.Rax,ctx.Rbx,ctx.Rcx,ctx.Rdx,ctx.Rsi,ctx.Rdi);
    std::printf("REG R8=%llx R9=%llx R10=%llx R11=%llx R12=%llx R13=%llx R14=%llx R15=%llx EFLAGS=%lx\n",ctx.R8,ctx.R9,ctx.R10,ctx.R11,ctx.R12,ctx.R13,ctx.R14,ctx.R15,ctx.EFlags);
    unsigned char bytes[48]{}; SIZE_T got=0;
    if(ReadProcessMemory(process,(LPCVOID)(ctx.Rip-16),bytes,sizeof(bytes),&got)) {
        std::printf("CODE address=0x%llx bytes=",ctx.Rip-16);
        for(SIZE_T i=0;i<got;i++)std::printf("%02x",bytes[i]); std::printf("\n");
    }
    STACKFRAME64 frame{};
    frame.AddrPC.Offset=ctx.Rip;frame.AddrPC.Mode=AddrModeFlat;
    frame.AddrStack.Offset=ctx.Rsp;frame.AddrStack.Mode=AddrModeFlat;
    frame.AddrFrame.Offset=ctx.Rbp;frame.AddrFrame.Mode=AddrModeFlat;
    std::printf("FRAME 0 pc=0x%llx",ctx.Rip);address(process,ctx.Rip);
    for(int i=1;i<96;i++) {
        if(!StackWalk64(IMAGE_FILE_MACHINE_AMD64,process,thread,&frame,&ctx,nullptr,SymFunctionTableAccess64,SymGetModuleBase64,nullptr)) {
            std::printf("STACK_END error=%lu\n",GetLastError()); break;
        }
        if(!frame.AddrPC.Offset)break;
        std::printf("FRAME %d pc=0x%llx sp=0x%llx",i,frame.AddrPC.Offset,frame.AddrStack.Offset);address(process,frame.AddrPC.Offset);
    }
}
int wmain(int argc,wchar_t **argv) {
    if(argc<4 || argc>6) { std::fprintf(stderr,"usage debugger godot.exe project timeout_ms [watch_rva [trace_rvas]]\n");return 2; }
    if(argc>=5)watch_rva=_wcstoui64(argv[4],nullptr,0);
    if(argc==6) {
        wchar_t *cursor=argv[5];
        while(*cursor){wchar_t *end=nullptr;DWORD64 rva=_wcstoui64(cursor,&end,0);if(end==cursor)return 2;trace_rvas.push_back(rva);cursor=*end==L','?end+1:end;}
    }
    std::wstring cmd=L"\""+std::wstring(argv[1])+L"\" --headless --editor --path \""+argv[2]+L"\" --import";
    std::vector<wchar_t> writable(cmd.begin(),cmd.end());writable.push_back(0);
    STARTUPINFOW start{};start.cb=sizeof(start); start.dwFlags=STARTF_USESTDHANDLES;
    start.hStdOutput=GetStdHandle(STD_OUTPUT_HANDLE);start.hStdError=GetStdHandle(STD_ERROR_HANDLE);start.hStdInput=GetStdHandle(STD_INPUT_HANDLE);
    PROCESS_INFORMATION pi{};
    if(!CreateProcessW(argv[1],writable.data(),nullptr,nullptr,TRUE,DEBUG_ONLY_THIS_PROCESS|CREATE_NO_WINDOW,nullptr,argv[2],&start,&pi)) {
        std::printf("CREATE_ERROR %lu\n",GetLastError());return 3;
    }
    FILETIME ct,et,kt,ut;GetProcessTimes(pi.hProcess,&ct,&et,&kt,&ut);
    std::printf("OWNED pid=%lu creation_filetime=%llu command=%ls\n",pi.dwProcessId,((uint64_t)ct.dwHighDateTime<<32)|ct.dwLowDateTime,cmd.c_str());
    SymSetOptions(SYMOPT_UNDNAME|SYMOPT_DEFERRED_LOADS|SYMOPT_LOAD_LINES|SYMOPT_FAIL_CRITICAL_ERRORS|SYMOPT_NO_PROMPTS);
    if(!SymInitializeW(pi.hProcess,L".",FALSE))std::printf("SYMINIT_ERROR %lu\n",GetLastError());
    std::map<DWORD,HANDLE> threads; ULONGLONG until=GetTickCount64()+_wcstoui64(argv[3],nullptr,10);bool exited=false;bool timedout=false;DWORD exit_code=0;
    while(!exited) {
        DEBUG_EVENT ev{};
        if(!WaitForDebugEvent(&ev,100)) {
            DWORD error=GetLastError();
            if(error!=ERROR_SEM_TIMEOUT){std::printf("WAIT_ERROR %lu\n",error);TerminateProcess(pi.hProcess,0xDEAD);timedout=true;}
            if(GetTickCount64()>until && !timedout){
                std::printf("TIMEOUT owned_pid=%lu\n",pi.dwProcessId);
                for(auto t:threads) {
                    DWORD previous=SuspendThread(t.second);
                    DEBUG_EVENT snapshot{};snapshot.dwProcessId=pi.dwProcessId;snapshot.dwThreadId=t.first;
                    snapshot.u.Exception.dwFirstChance=2;
                    exception(pi.hProcess,t.second,snapshot);
                    if(previous!=DWORD(-1))ResumeThread(t.second);
                }
                TerminateProcess(pi.hProcess,0xDEAD);timedout=true;
            }
            if(timedout && WaitForSingleObject(pi.hProcess,0)==WAIT_OBJECT_0)break;
            continue;
        }
        DWORD status=DBG_CONTINUE;
        switch(ev.dwDebugEventCode) {
        case CREATE_PROCESS_DEBUG_EVENT:
            threads[ev.dwThreadId]=ev.u.CreateProcessInfo.hThread;
            image_base=(DWORD64)ev.u.CreateProcessInfo.lpBaseOfImage;
            for(DWORD64 rva:trace_rvas) {
                unsigned char original=0,trap=0xcc;SIZE_T count=0;
                if(ReadProcessMemory(pi.hProcess,(LPCVOID)(image_base+rva),&original,1,&count) &&
                   WriteProcessMemory(pi.hProcess,(LPVOID)(image_base+rva),&trap,1,&count)) {
                    breakpoints[image_base+rva]=original;
                    FlushInstructionCache(pi.hProcess,(LPCVOID)(image_base+rva),1);
                } else std::printf("TRACE_SETUP_ERROR rva=%llx error=%lu\n",rva,GetLastError());
            }
            module(pi.hProcess,ev.u.CreateProcessInfo.hFile,(DWORD64)ev.u.CreateProcessInfo.lpBaseOfImage);
            if(ev.u.CreateProcessInfo.hFile)CloseHandle(ev.u.CreateProcessInfo.hFile);
            // Event handles are distinct references from PROCESS_INFORMATION.
            if(ev.u.CreateProcessInfo.hProcess!=pi.hProcess)CloseHandle(ev.u.CreateProcessInfo.hProcess);
            break;
        case CREATE_THREAD_DEBUG_EVENT: threads[ev.dwThreadId]=ev.u.CreateThread.hThread; break;
        case EXIT_THREAD_DEBUG_EVENT:
            if(threads.count(ev.dwThreadId)){
                if(threads[ev.dwThreadId]==pi.hThread)pi.hThread=nullptr;
                CloseHandle(threads[ev.dwThreadId]);threads.erase(ev.dwThreadId);
            }break;
        case LOAD_DLL_DEBUG_EVENT:
            module(pi.hProcess,ev.u.LoadDll.hFile,(DWORD64)ev.u.LoadDll.lpBaseOfDll);
            if(ev.u.LoadDll.hFile)CloseHandle(ev.u.LoadDll.hFile);break;
        case UNLOAD_DLL_DEBUG_EVENT:
            std::printf("UNLOAD base=0x%llx\n",(DWORD64)ev.u.UnloadDll.lpBaseOfDll);
            SymUnloadModule64(pi.hProcess,(DWORD64)ev.u.UnloadDll.lpBaseOfDll);modules.erase((DWORD64)ev.u.UnloadDll.lpBaseOfDll);break;
        case EXCEPTION_DEBUG_EVENT:
            std::printf("EVENT_EXCEPTION pid=%lu tid=%lu code=%08lx first=%lu\n",ev.dwProcessId,ev.dwThreadId,ev.u.Exception.ExceptionRecord.ExceptionCode,ev.u.Exception.dwFirstChance);
            if(ev.u.Exception.ExceptionRecord.ExceptionCode==EXCEPTION_BREAKPOINT &&
               breakpoints.count((DWORD64)ev.u.Exception.ExceptionRecord.ExceptionAddress)) {
                DWORD64 pc=(DWORD64)ev.u.Exception.ExceptionRecord.ExceptionAddress;
                CONTEXT context{};context.ContextFlags=CONTEXT_CONTROL;
                unsigned char original=breakpoints[pc];SIZE_T count=0;
                if(!WriteProcessMemory(pi.hProcess,(LPVOID)pc,&original,1,&count) ||
                   !GetThreadContext(threads[ev.dwThreadId],&context)) {std::printf("TRACE_ERROR %lu\n",GetLastError());TerminateProcess(pi.hProcess,0xDEAD);timedout=true;break;}
                context.Rip=pc;
                if(!SetThreadContext(threads[ev.dwThreadId],&context)){std::printf("TRACE_CONTEXT_ERROR %lu\n",GetLastError());TerminateProcess(pi.hProcess,0xDEAD);timedout=true;break;}
                FlushInstructionCache(pi.hProcess,(LPCVOID)pc,1);breakpoints.erase(pc);
                DWORD64 value=0;
                if(watch_rva && !ReadProcessMemory(pi.hProcess,(LPCVOID)(image_base+watch_rva),&value,sizeof(value),&count))
                    std::printf("TRACE_WATCH_ERROR %lu\n",GetLastError());
                std::printf("TRACE rva=0x%llx watch_rva=0x%llx value=0x%llx\n",pc-image_base,watch_rva,value);
                break;
            }
            if(ev.u.Exception.ExceptionRecord.ExceptionCode==EXCEPTION_BREAKPOINT && ev.u.Exception.dwFirstChance)status=DBG_CONTINUE;
            else {
                status=DBG_EXCEPTION_NOT_HANDLED;
                if(!ev.u.Exception.dwFirstChance || ev.u.Exception.ExceptionRecord.ExceptionCode==EXCEPTION_ACCESS_VIOLATION)
                    exception(pi.hProcess,threads[ev.dwThreadId],ev);
            }break;
        case EXIT_PROCESS_DEBUG_EVENT:
            exit_code=ev.u.ExitProcess.dwExitCode;exited=true;std::printf("EXIT pid=%lu code=0x%08lx timedout=%d\n",ev.dwProcessId,exit_code,timedout);break;
        }
        std::fflush(stdout);
        if(!ContinueDebugEvent(ev.dwProcessId,ev.dwThreadId,status)){std::printf("CONTINUE_ERROR %lu\n",GetLastError());TerminateProcess(pi.hProcess,0xDEAD);timedout=true;}
    }
    WaitForSingleObject(pi.hProcess,10000);SymCleanup(pi.hProcess);
    for(auto t:threads){if(t.second==pi.hThread)pi.hThread=nullptr;CloseHandle(t.second);}
    if(pi.hThread)CloseHandle(pi.hThread);CloseHandle(pi.hProcess);
    return timedout?4:exit_code?1:0;
}
'''


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def require_fresh_e(path: Path) -> Path:
    path = path.resolve()
    if path.drive.upper() != "E:" or path.exists():
        raise ValueError(f"must be a nonexisting E: owned root: {path}")
    return path


def parse_debug_log(text: str) -> dict:
    """Parse raw debugger events without treating snapshots as exceptions."""
    result = {"second_chance": [], "traces": [], "child_exit_hex": None}
    event = None
    for line in text.splitlines():
        match = re.match(r"EXCEPTION pid=(\d+) tid=(\d+) first_chance=(\d+) code=(0x[0-9a-f]+) flags=(0x[0-9a-f]+) address=(0x[0-9a-f]+)", line)
        if match:
            event = None
            if match[3] == "0":
                event = {"pid": int(match[1]), "tid": int(match[2]),
                         "code": match[4], "address": match[6],
                         "parameters": [], "registers": {}, "frames": [],
                         "watches": [], "module_line": ""}
                result["second_chance"].append(event)
        elif line.startswith("TIMEOUT_SNAPSHOT"):
            event = None
        elif line.startswith("TRACE "):
            result["traces"].append(line)
        elif line.startswith("EXIT "):
            exit_match = re.search(r"code=(0x[0-9a-f]+)", line)
            if exit_match:
                result["child_exit_hex"] = exit_match[1]
        elif event is not None:
            if line.startswith("PARAM "):
                event["parameters"].append(int(line.split("=", 1)[1], 16))
            elif line.startswith("REG "):
                event["registers"].update({key: int(value, 16) for key, value in re.findall(r"(\w+)=([0-9a-f]+)", line)})
            elif line.startswith("FRAME "):
                event["frames"].append(line)
            elif line.startswith("WATCH "):
                event["watches"].append(line)
            elif line.startswith(" module="):
                event["module_line"] = line.strip()
    return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--dll", type=Path)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--watch-rva", type=lambda value: int(value, 0))
    parser.add_argument("--trace-rva", action="append", type=lambda value: int(value, 0), default=[])
    parser.add_argument("--vs-dev", type=Path, default=Path("D:/VS2022/Common7/Tools/VsDevCmd.bat"))
    args = parser.parse_args(argv)
    if os.name != "nt":
        raise RuntimeError("Windows x64 only")
    root = require_fresh_e(args.root)
    root.mkdir(parents=True)
    cpp = root / "debugger.cpp"
    cpp.write_text(DEBUGGER_CPP, encoding="utf-8")
    build = root / "build.cmd"
    build.write_text(f'@call "{args.vs_dev}" -arch=x64 -host_arch=x64\n@cl /nologo /EHsc /std:c++17 /W4 "{cpp}" /Fe:"{root / "debugger.exe"}" /Fo:"{root / "debugger.obj"}" /link dbghelp.lib\n', encoding="utf-8")
    compiled = subprocess.run(["cmd.exe", "/d", "/c", str(build)], cwd=root, capture_output=True)
    (root / "build.log").write_bytes(compiled.stdout + compiled.stderr)
    if compiled.returncode:
        print(f"build blocked exit={compiled.returncode}: {root / 'build.log'}")
        return 2
    source = args.source.resolve()
    dll = (args.dll or source / "addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll").resolve()
    project = root / "project"
    project.mkdir()
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Round39 Native Cold Import"\nconfig/features=PackedStringArray("4.7")\n[rendering]\nrenderer/rendering_method="mobile"\n', encoding="utf-8")
    relative = Path("addons/fate_server_signals")
    (project / relative / "bin").mkdir(parents=True)
    descriptor = source / relative / "fate_server_signals.gdextension"
    shutil.copy2(descriptor, project / relative / descriptor.name)
    shutil.copy2(dll, project / relative / "bin/libfate_server_signals.windows.template_release.x86_64.dll")
    env = os.environ.copy()
    # Windows debugger otherwise adds expensive heap validation to this child.
    # This environment flag is child-local, not a registry/security-policy edit.
    env["_NO_DEBUG_HEAP"] = "1"
    for key in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "TMPDIR"):
        directory = root / "user" / key
        directory.mkdir(parents=True)
        env[key] = str(directory)
    command = [str(root / "debugger.exe"), str(args.godot.resolve()), str(project), str(args.timeout * 1000)]
    if args.watch_rva is not None or args.trace_rva:
        command.append(hex(args.watch_rva or 0))
    if args.trace_rva:
        command.append(",".join(hex(value) for value in args.trace_rva))
    with (root / "debug.log").open("wb") as log:
        result = subprocess.run(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout + 30)
    report = {"command": command, "debugger_exit": result.returncode,
              "dll": str(dll), "dll_sha256": digest(dll),
              "descriptor_sha256": digest(descriptor), "godot_sha256": digest(args.godot),
              "debug_log": str(root / "debug.log"), "cold_cache_existed_before": False}
    report["events"] = parse_debug_log((root / "debug.log").read_text(encoding="utf-8", errors="replace"))
    (root / "result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())