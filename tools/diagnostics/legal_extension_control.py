"""R49: exactly four fresh cold imports; separate post-import capability check.

Production source/native files and host are read-only. Hardware data-write
watchpoints alter owned thread debug registers only, never host code bytes.
"""
from __future__ import annotations
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import time
import zipfile

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.diagnostics.native_cold_import_debug import DEBUGGER_CPP, digest, parse_debug_log
from tools.diagnostics.project_extension_lifecycle_probe import (
    physical_e, child_env, bounded, prepare_project, save, validate_flags, EXT, DLL, MINIMAL,
)
ENGINE_SHA = "ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424"
REVISION = "ed1daf0bf001b61586d9930840f2f1394092c079"
DOC_RVA = 0x66DCC10
HOST_POINTS = (0x17ABC86, 0x1792840)

HARDWARE_CPP = r'''
DWORD64 fate_base=0;
DWORD64 hw_points[4]{};
unsigned long long hw_sequence=0;
bool install_hw(HANDLE thread) {
    CONTEXT ctx{};ctx.ContextFlags=CONTEXT_DEBUG_REGISTERS;
    if(!GetThreadContext(thread,&ctx)){std::printf("HW_CONTEXT_ERROR %lu\n",GetLastError());return false;}
    ctx.Dr0=hw_points[0];ctx.Dr1=hw_points[1];ctx.Dr2=0;ctx.Dr3=0;ctx.Dr6=0;
    // 数据写断点在 store 完成后 trap，无执行断点的 RF/TF 恢复和重入问题。
    // DR0: write / 8 bytes；DR1: write / 4 bytes，仅正式 DLL 加载后启用。
    ctx.Dr7=(hw_points[0]?0x90001:0)|(hw_points[1]?0xd00004:0);
    if(!SetThreadContext(thread,&ctx)){std::printf("HW_INSTALL_ERROR %lu\n",GetLastError());return false;}
    return true;
}
bool hardware_event(HANDLE process,HANDLE thread,DWORD pid,DWORD tid) {
    CONTEXT ctx{};ctx.ContextFlags=CONTEXT_ALL;
    if(!GetThreadContext(thread,&ctx))return false;
    DWORD64 hits=ctx.Dr6&3;
    if(!hits)return false;
    DWORD64 doc=0;DWORD level=0xffffffff;SIZE_T got=0;
    if(!ReadProcessMemory(process,(LPCVOID)(image_base+watch_rva),&doc,sizeof(doc),&got))std::printf("HW_READ_ERROR %lu\n",GetLastError());
    if(fate_base)ReadProcessMemory(process,(LPCVOID)(fate_base+0x17a5e0),&level,sizeof(level),&got);
    for(int i=0;i<2;i++)if(hits&(DWORD64(1)<<i)) {
        std::printf("HWTRACE seq=%llu tick=%llu pid=%lu tid=%lu event=%s pc=0x%llx host_rva=0x%llx fate_rva=0x%llx doc=0x%llx level=%lu\n",
            ++hw_sequence,GetTickCount64(),pid,tid,i?"FATE_LEVEL_WRITE":"DOC_POINTER_WRITE",ctx.Rip,ctx.Rip-image_base,fate_base?ctx.Rip-fate_base:0,doc,level);
    }
    if(hw_sequence>128){std::printf("HW_RESUME_ERROR runaway trace limit\n");TerminateProcess(process,0xDEAD);}
    // 不改 EFlags/RIP/任何代码字节，直接继续已经完成写入的下一条指令。
    return true;
}
'''


def debugger_source():
    source = DEBUGGER_CPP
    begin = source.index("    if(argc<4 || argc>6)")
    end = source.index("    std::vector<wchar_t> writable", begin)
    source = source[:begin] + '    if(argc!=5)return 2;\n    watch_rva=0x66dcc10;\n    std::wstring cmd=L"\\\""+std::wstring(argv[1])+L"\\\" "+argv[4];\n' + source[end:]
    source = source.replace("int wmain(int argc,wchar_t **argv) {", HARDWARE_CPP + "\nint wmain(int argc,wchar_t **argv) {")
    start = source.index("            for(DWORD64 rva:trace_rvas)")
    end = source.index("            module(pi.hProcess", start)
    source = source[:start] + '            hw_points[0]=image_base+0x66dcc10;hw_points[1]=0;\n            if(!install_hw(threads[ev.dwThreadId]))TerminateProcess(pi.hProcess,0xDEAD);\n' + source[end:]
    start = source.index("            if(ev.u.Exception.ExceptionRecord.ExceptionCode==EXCEPTION_BREAKPOINT &&\n               breakpoints.count")
    end = source.index("            if(ev.u.Exception.ExceptionRecord.ExceptionCode==EXCEPTION_BREAKPOINT && ev.u.Exception.dwFirstChance)", start)
    source = source[:start] + '            if(ev.u.Exception.ExceptionRecord.ExceptionCode==EXCEPTION_SINGLE_STEP && ev.u.Exception.dwFirstChance && hardware_event(pi.hProcess,threads[ev.dwThreadId],ev.dwProcessId,ev.dwThreadId))break;\n' + source[end:]
    old = "case CREATE_THREAD_DEBUG_EVENT: threads[ev.dwThreadId]=ev.u.CreateThread.hThread; break;"
    assert source.count(old) == 1
    source = source.replace(old, "case CREATE_THREAD_DEBUG_EVENT: threads[ev.dwThreadId]=ev.u.CreateThread.hThread; if(!install_hw(threads[ev.dwThreadId]))TerminateProcess(pi.hProcess,0xDEAD); break;")
    old = "            if(ev.u.LoadDll.hFile)CloseHandle(ev.u.LoadDll.hFile);break;"
    new = r'''            if(modules[(DWORD64)ev.u.LoadDll.lpBaseOfDll].path.find(L"libfate_server_signals.windows.template_release.x86_64.dll")!=std::wstring::npos) {
                fate_base=(DWORD64)ev.u.LoadDll.lpBaseOfDll;
                hw_points[1]=fate_base+0x17a5e0;
                for(auto t:threads)if(!install_hw(t.second))TerminateProcess(pi.hProcess,0xDEAD);
                std::printf("HW_FATE_MODULE base=0x%llx level_storage_rva=0x17a5e0\n",fate_base);
            }
            if(ev.u.LoadDll.hFile)CloseHandle(ev.u.LoadDll.hFile);break;'''
    assert source.count(old) == 1
    source = source.replace(old, new)
    source = source.replace("    PROCESS_INFORMATION pi{};", '    PROCESS_INFORMATION pi{};\n    bool own_console=GetEnvironmentVariableW(L"R49_OWN_CONSOLE",nullptr,0)>0;\n    if(own_console){start.dwFlags|=STARTF_USESHOWWINDOW;start.wShowWindow=SW_HIDE;}')
    source = source.replace("    PROCESS_INFORMATION pi{};", '    wchar_t self_pid[32]{};swprintf_s(self_pid,L"%lu",GetCurrentProcessId());SetEnvironmentVariableW(L"R49_OWN_DEBUGGER_PID",self_pid);\n    SetConsoleCtrlHandler([](DWORD code)->BOOL{return code==CTRL_BREAK_EVENT || code==CTRL_C_EVENT;},TRUE);\n    PROCESS_INFORMATION pi{};')
    source = source.replace("DEBUG_ONLY_THIS_PROCESS|CREATE_NO_WINDOW", "DEBUG_ONLY_THIS_PROCESS|(own_console?CREATE_NEW_CONSOLE:CREATE_NO_WINDOW)")
    source = source.replace("        std::fflush(stdout);", "        if(GetTickCount64()>until && !exited && !timedout){std::printf(\"TIMEOUT owned_pid=%lu\\n\",pi.dwProcessId);TerminateProcess(pi.hProcess,0xDEAD);timedout=true;}\n        std::fflush(stdout);")
    assert "WriteProcessMemory(" not in source
    return source


HELPER_CPP = r'''
#include <windows.h>
#include <cwchar>
#include <cstdio>
static BOOL WINAPI ignore(DWORD){return TRUE;}
static bool members(DWORD engine,DWORD debugger){
    DWORD pids[16]{};DWORD n=GetConsoleProcessList(pids,16);
    bool have_engine=false,have_debugger=false,have_self=false;
    if(n<3 || n>16)return false;
    for(DWORD i=0;i<n;i++){
        if(pids[i]==engine)have_engine=true;
        else if(pids[i]==debugger)have_debugger=true;
        else if(pids[i]==GetCurrentProcessId())have_self=true;
        else return false;
    }
    std::printf("R49_CONSOLE_MEMBERS engine=%lu debugger=%lu sender=%lu count=%lu\n",engine,debugger,GetCurrentProcessId(),n);std::fflush(stdout);
    return have_engine && have_debugger && have_self;
}
int wmain(int argc,wchar_t **argv){
    if(argc==4 && !std::wcscmp(argv[1],L"--send-break")){
        DWORD engine=wcstoul(argv[2],nullptr,10),debugger=wcstoul(argv[3],nullptr,10);
        if(!engine || !debugger || !members(engine,debugger))return 5;
        if(!SetConsoleCtrlHandler(ignore,TRUE))return 2;
        if(!members(engine,debugger))return 6;
        return GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT,0)?0:3;
    }
    if(argc!=1)return 7;
    HANDLE event=CreateEventW(nullptr,TRUE,FALSE,nullptr);
    if(!event)return 4;
    WaitForSingleObject(event,INFINITE);CloseHandle(event);return 0;
}
'''

CAPABILITY_GD = '''extends SceneTree
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
    print("R49_CAP ", label, "=", ok)
    if not ok: failures.append(label)
func _initialize() -> void:
    _run.call_deferred()
func inject_break(helper: String) -> bool:
    # OS.execute 的 Windows 启动策略可另建控制台；用已读的正式 owner CREATE flags=0 继承本进程独占控制台。
    var sender = ClassDB.instantiate("FateProcessOwner")
    var sent: Dictionary = sender.spawn(helper, PackedStringArray(["--send-break", str(OS.get_process_id()), OS.get_environment("R49_OWN_DEBUGGER_PID")]))
    var pid: int = int(sent.get("pid", -1))
    var token: String = str(sent.get("token", ""))
    if pid <= 0: return false
    var until := Time.get_ticks_msec() + 5000
    while sender.state(token, pid) == 1 and Time.get_ticks_msec() < until:
        await process_frame
    var exited: bool = sender.state(token, pid) == 0
    if not exited: sender.terminate(token, pid)
    return sender.release(token, pid) and exited
func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var output := args[0]
    var helper := args[1]
    for name in ["FateServerSignals", "FateProcessOwner", "FateAtomicFileReplace", "FateCollectionIdentity"]:
        check(ClassDB.class_exists(name) and ClassDB.can_instantiate(name), "registered_" + name)
    var signals = ClassDB.instantiate("FateServerSignals")
    check(signals.enable(), "signals_enable")
    var competing = ClassDB.instantiate("FateServerSignals")
    check(not competing.enable(), "signals_single_owner")
    check(await inject_break(helper), "signal_inject_owned_console")
    var request: int = 0
    var until := Time.get_ticks_msec() + 5000
    while request == 0 and Time.get_ticks_msec() < until:
        request = signals.take_request()
        if request == 0: await process_frame
    check(request == 2 and signals.take_request() == 0, "signals_break_delivery_once")
    signals.disable()
    check(signals.protect_worker(), "signals_protect_worker")
    check(await inject_break(helper), "worker_signal_inject")
    for _frame in range(10): await process_frame
    check(signals.take_request() == 0, "worker_does_not_collect")
    signals.disable()
    var owner = ClassDB.instantiate("FateProcessOwner")
    check(owner.available(), "owner_available")
    var child: Dictionary = owner.spawn(helper, PackedStringArray())
    var pid: int = int(child.get("pid", -1))
    var token: String = str(child.get("token", ""))
    check(pid > 0 and not token.is_empty(), "owner_spawn")
    if pid > 0:
        check(owner.verify(token, pid) and owner.state(token, pid) == 1, "owner_verify_running")
        check(not owner.verify("wrong-token", pid) and not owner.release(token, pid), "owner_reject_wrong_or_live_release")
        check(owner.terminate(token, pid), "owner_terminate")
        check(owner.state(token, pid) == 0, "owner_exit_observed")
        check(owner.release(token, pid) and owner.state(token, pid) == -1, "owner_release")
    var atomic = ClassDB.instantiate("FateAtomicFileReplace")
    var folder := output.get_base_dir()
    var temporary := folder.path_join("atomic-source.tmp")
    var target := folder.path_join("atomic-target.txt")
    var file := FileAccess.open(temporary, FileAccess.WRITE)
    file.store_string("r49-new"); file.close()
    file = FileAccess.open(target, FileAccess.WRITE)
    file.store_string("r49-old"); file.close()
    var result: Dictionary = atomic.replace_validated_file(temporary, target, 7)
    check(result.get("ok", false) and FileAccess.get_file_as_string(target) == "r49-new" and not FileAccess.file_exists(temporary), "atomic_replace_and_readback")
    var identity = ClassDB.instantiate("FateCollectionIdentity")
    check(identity.is_supported(str(Engine.get_version_info().get("hash", ""))), "identity_runtime_abi_gate")
    var array: Array = []; var alias: Array = array; var distinct: Array = []
    var dict: Dictionary = {}; var dalias: Dictionary = dict; var ddistinct: Dictionary = {}
    var ak: int = identity.candidate_key(array); var dk: int = identity.candidate_key(dict)
    check(ak != 0 and ak == identity.candidate_key(alias) and ak != identity.candidate_key(distinct), "identity_array_alias_distinct")
    check(dk != 0 and dk == identity.candidate_key(dalias) and dk != identity.candidate_key(ddistinct), "identity_dictionary_alias_distinct")
    array.append(1); dict["a"] = 1
    check(ak == identity.candidate_key(array) and dk == identity.candidate_key(dict), "identity_stable_after_mutation")
    signals = null; competing = null; owner = null; atomic = null; identity = null
    var report := {"failures": failures, "ok": failures.is_empty(), "owned_helper_pid": pid, "engine": Engine.get_version_info()}
    file = FileAccess.open(output, FileAccess.WRITE); file.store_string(JSON.stringify(report, "  ")); file.close()
    print("R49_CAP_RESULT ", JSON.stringify(report))
    quit(0 if failures.is_empty() else 1)
'''


def verify_pinned_engine(godot):
    if digest(godot) != ENGINE_SHA:
        raise ValueError("hardware RVAs require exact pinned actual engine")
    data = godot.read_bytes()
    assert REVISION.encode() in data
    pe = struct.unpack_from("<I", data, 60)[0]
    optional = pe + 24
    section_start = optional + struct.unpack_from("<H", data, pe + 20)[0]
    count = struct.unpack_from("<H", data, pe + 6)[0]
    def at(rva, size):
        for i in range(count):
            row = section_start + i * 40
            vs, va, rawsize, off = struct.unpack_from("<IIII", data, row + 8)
            if va <= rva < va + max(vs, rawsize):
                return data[off + rva - va:off + rva - va + size]
        raise ValueError("RVA not mapped")
    # 精确字节检查后才安装硬件断点；不是从旧 RVA 直接推断本轮调用顺序。
    expected = {0x17ABC7B: "48c7058a0ff30400000000", 0x17ABC86: "4883c420", 0x1792840: "4883ec28"}
    actual = {hex(rva): at(rva, len(bytes.fromhex(value))).hex() for rva, value in expected.items()}
    if any(actual[hex(rva)] != value for rva, value in expected.items()):
        raise ValueError(f"pinned trace bytes mismatch: {actual}")
    return actual


def archive_generated(directory):
    paths = [directory / "project/.godot", directory / "user"]
    paths += [p for p in (directory / "project").rglob("~*.dll")]
    files = [f for p in paths if p.exists() for f in (p.rglob("*") if p.is_dir() else [p]) if f.is_file()]
    # 保留完整原件为无损 ZIP，校验逐个内容 SHA 后才回收自有生成缓存。
    archive = directory / "generated-originals.zip"
    manifest = {p.relative_to(directory).as_posix(): digest(p) for p in files}
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED) as z:
        for p in files: z.write(p, p.relative_to(directory).as_posix())
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        assert set(z.namelist()) == set(manifest)
        for name, sha in manifest.items():
            assert hashlib.sha256(z.read(name)).hexdigest() == sha
    for p in paths:
        if p.exists():
            physical_e(p)
            if p.is_dir(): shutil.rmtree(p)
            else: p.unlink()
    save(directory / "archive-manifest.json", {"archive": str(archive), "archive_sha256": digest(archive), "files": manifest, "verified_then_reclaimed": True})


def run_debugger(root, directory, godot, env, tail, timeout):
    command = [str(root / "debugger.exe"), str(godot), str(directory / "project"), str(timeout * 1000), subprocess.list2cmdline(tail)]
    if env.get("R49_OWN_CONSOLE") == "1":
        # GUI 引擎会 AttachConsole(parent)；真正的独占控制台必须属于 console-subsystem debugger。
        startup = subprocess.STARTUPINFO();startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow = 0
        started = time.monotonic()
        with (directory / "debug.log").open("xb") as stream:
            proc = subprocess.Popen(command, cwd=directory, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                    creationflags=subprocess.CREATE_NEW_CONSOLE, startupinfo=startup)
            timedout = False
            try: code = proc.wait(timeout=timeout + 20)
            except subprocess.TimeoutExpired:
                timedout = True;proc.kill();code = proc.wait(timeout=10)
        run = {"pid":proc.pid,"exit":code,"timeout":timedout,"elapsed_s":time.monotonic()-started,"argv":command,"log":str(directory/"debug.log"),"isolated_debugger_console":True}
    else:
        run = bounded(command, directory, env, directory / "debug.log", timeout + 20)
    text = (directory / "debug.log").read_text(encoding="utf-8", errors="replace")
    events = parse_debug_log(text)
    owned = re.search(r"OWNED pid=(\d+) creation_filetime=(\d+) command=(.*)", text)
    native_errors = [line for line in text.splitlines() if any(s in line for s in ("HW_CONTEXT_ERROR", "HW_INSTALL_ERROR", "HW_READ_ERROR", "HW_RESUME_ERROR", "R49_INITFAIL", "ERROR:"))]
    result = {"run": run, "pid": int(owned[1]) if owned else None,
              "creation_filetime": owned[2] if owned else None,
              "events": events, "hardware_trace": [line for line in text.splitlines() if line.startswith("HWTRACE ")],
              "control_trace": [line for line in text.splitlines() if line.startswith("R49_CONTROL ")],
              "errors": native_errors, "environment": {key: env[key] for key in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "TMPDIR")},
              "status": "NATIVE_FAILURE" if events["second_chance"] else "CLEAN_EXIT" if events["child_exit_hex"] == "0x00000000" and not native_errors else "INCOMPLETE_OR_ERROR"}
    save(directory / "result.json", result)
    print(json.dumps({"case": directory.name, "pid": result["pid"], "status": result["status"], "exit": events["child_exit_hex"], "trace": result["hardware_trace"]}), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--source", type=Path, default=REPO)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--capabilities", action="store_true", help="separate runtime check after two successful formal imports; not a fifth cold comparison")
    args = parser.parse_args()
    if os.name != "nt" or not 1 <= args.timeout <= 180: raise ValueError("Windows; budget 1..180")
    root = physical_e(args.root)
    source = physical_e(args.source)
    if source in root.parents or root in source.parents: raise ValueError("outside source only")
    # official evidence is prepared separately; never overwrite an executed root.
    if (root / "metadata.json").exists(): raise ValueError("already executed root refused")
    header = root / "official/core/extension/gdextension_interface.h"
    spec = root / "official/core/extension/gdextension_interface.json"
    if not header.is_file() or not spec.is_file(): raise ValueError("exact official header/spec prerequisite missing")
    env = child_env(root)
    godot = args.godot.resolve()
    byte_check = verify_pinned_engine(godot)
    help_path = Path("E:/FateDiagnostics/round45-project-native-cause-20261010-1/help.log")
    old_meta = json.loads(help_path.with_name("metadata.json").read_text(encoding="utf-8"))
    assert old_meta["godot_sha256"] == digest(godot)
    help_text = help_path.read_text(encoding="utf-8", errors="replace")
    native_inputs = {str(p.relative_to(source)): digest(p) for p in (source / EXT, source / DLL, source / "addons/fate_server_signals/SConstruct", *sorted((source / "addons/fate_server_signals/src").glob("*"))) if p.is_file()}
    assert digest(source / DLL) == "92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd", "DLL trace RVAs require exact pinned product DLL"
    metadata = {"godot": str(godot), "engine_sha256": digest(godot), "engine_commit": REVISION, "source": str(source), "timeout_s": args.timeout,
                "native_readonly_inputs": native_inputs, "header_sha256": digest(header), "spec_sha256": digest(spec), "trace_byte_check": byte_check,
                "cold_definition": "fresh project .godot and own redirected user/cache dirs; not cold OS file cache",
                "comparison_count": 4, "capabilities_separate": args.capabilities, "hardware_debug_registers_only": True,
                "driver_sha256": digest(Path(__file__)), "control_cpp_sha256": digest(Path(__file__).with_suffix(".cpp"))}
    save(root / "metadata.json", metadata)
    (root / "debugger.cpp").write_text(debugger_source(), encoding="utf-8", newline="\n")
    shutil.copyfile(Path(__file__).with_suffix(".cpp"), root / "legal_extension_control.cpp")
    (root / "owned_helper.cpp").write_text(HELPER_CPP, encoding="utf-8", newline="\n")
    build = root / "build.cmd"
    build.write_text(f'@call "D:/VS2022/Common7/Tools/VsDevCmd.bat" -arch=x64 -host_arch=x64\n@cl /nologo /utf-8 /EHsc /std:c++17 /W4 /WX "{root / "debugger.cpp"}" /Fe:"{root / "debugger.exe"}" /Fo:"{root / "debugger.obj"}" /link dbghelp.lib\n@if errorlevel 1 exit /b 1\n@cl /nologo /utf-8 /EHsc /std:c++17 /W4 /O2 /MT /LD /I"{header.parent}" "{root / "legal_extension_control.cpp"}" /Fe:"{root / "legal_control.dll"}" /Fo:"{root / "legal_control.obj"}"\n@if errorlevel 1 exit /b 1\n@cl /nologo /utf-8 /EHsc /std:c++17 /W4 /WX /O2 /MT "{root / "owned_helper.cpp"}" /Fe:"{root / "owned_helper.exe"}" /Fo:"{root / "owned_helper.obj"}"\n', encoding="utf-8")
    build_result = bounded(["cmd.exe", "/d", "/c", str(build)], root, env, root / "build.log", 90)
    save(root / "build-result.json", build_result)
    if build_result["exit"]: raise RuntimeError("diagnostic build failed")
    save(root / "diagnostic-build-fingerprints.json", {p.name: digest(p) for p in (root / "build.cmd", root / "debugger.cpp", root / "debugger.exe", root / "legal_control.dll", root / "legal_extension_control.cpp", root / "owned_helper.exe")})
    results = []
    formal_manifest = None
    for case in ("A-legal-registered", "B-same-dll-unregistered", "C-formal-cold-1", "D-formal-cold-2"):
        directory = root / case; directory.mkdir()
        project = directory / "project"
        if case.startswith(("A-", "B-")):
            project.mkdir(); (project / "project.godot").write_text(MINIMAL, encoding="utf-8", newline="\n")
            addon = project / "addons/legal_control"; addon.mkdir(parents=True)
            shutil.copyfile(root / "legal_control.dll", addon / "legal_control.dll")
            (addon / "legal_control.gdextension").write_text('[configuration]\nentry_symbol="legal_extension_control_init"\ncompatibility_minimum="4.4"\nreloadable=false\n[libraries]\nwindows.x86_64="res://addons/legal_control/legal_control.dll"\n', encoding="utf-8", newline="\n")
            manifest = {"files": {p.relative_to(project).as_posix(): digest(p) for p in project.rglob("*") if p.is_file()}, "registration_selected_by_environment": case.startswith("A-")}
            save(directory / "input-manifest.json", manifest)
        elif case.startswith("C-"):
            project, manifest = prepare_project("C-formal-cold-freeze", directory, source)
            formal_manifest = manifest
            shutil.copytree(project, root / "formal-input-snapshot")
        else:
            shutil.copytree(root / "formal-input-snapshot", project)
            manifest = formal_manifest
            assert {p.relative_to(project).as_posix(): digest(p) for p in project.rglob("*") if p.is_file()} == manifest["files"]
            save(directory / "input-manifest.json", manifest)
        assert not (project / ".godot").exists()
        case_env = child_env(directory)
        case_env["R49_REGISTER_CLASS"] = "1" if case.startswith("A-") else "0"
        tail = ["--headless", "--verbose", "--rendering-method", "gl_compatibility", "--editor", "--path", str(project), "--import"]
        validate_flags(tail, help_text)
        result = run_debugger(root, directory, godot, case_env, tail, args.timeout)
        result["case"] = case
        results.append(result)
        if any(e["code"] == "0x80000004" for e in result["events"]["second_chance"]):
            raise RuntimeError("debugger-produced second-chance single-step; invalid diagnostic, stop")
        if result["run"]["timeout"] or any("R49_INITFAIL" in e or "HW_" in e for e in result["errors"]):
            raise RuntimeError("invalid diagnostic run; stop comparison, preserve evidence")
        save(root / "progress.json", {"completed": results}) if not (root / "progress.json").exists() else None
    save(root / "cold-results.json", {"cases": results, "count": len(results), "not_release_acceptance": True})
    # Registered/unregistered are byte-for-byte identical files, including DLL.
    a = json.loads((root / "A-legal-registered/input-manifest.json").read_text())
    b = json.loads((root / "B-same-dll-unregistered/input-manifest.json").read_text())
    assert a["files"] == b["files"]
    capability = None
    if args.capabilities and all(r["status"] == "CLEAN_EXIT" for r in results[2:]):
        directory = root / "E-post-import-capabilities"; directory.mkdir()
        project = directory / "project"
        shutil.copytree(root / "D-formal-cold-2/project", project, ignore=shutil.ignore_patterns("~*.dll"))
        (root / "capabilities.gd").write_text(CAPABILITY_GD, encoding="utf-8", newline="\n")
        runtime_env = child_env(directory); runtime_env["R49_OWN_CONSOLE"] = "1"
        tail = ["--headless", "--verbose", "--rendering-method", "gl_compatibility", "--path", str(project), "--script", str(root / "capabilities.gd"), "--", str(directory / "capabilities.json"), str(root / "owned_helper.exe")]
        capability = run_debugger(root, directory, godot, runtime_env, tail, args.timeout)
        if (directory / "capabilities.json").exists():
            capability["functional_report"] = json.loads((directory / "capabilities.json").read_text())
        save(root / "capability-result.json", capability)
    final_hashes = {rel: digest(source / rel) for rel in native_inputs}
    assert final_hashes == native_inputs
    assert digest(godot) == ENGINE_SHA
    # 回读真实退出并检查准确 PID 不存活；不做 basename 查杀、不打开外部进程。
    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.OpenProcess.restype = ctypes.c_void_p
    pid_checks = []
    pids = [r["pid"] for r in results]
    if capability:
        pids.append(capability["pid"])
        child_pid = capability.get("functional_report", {}).get("owned_helper_pid")
        if child_pid: pids.append(child_pid)
    for pid in pids:
        if not pid: continue
        ctypes.set_last_error(0); handle = k32.OpenProcess(0x100000, False, pid)
        error = ctypes.get_last_error()
        if handle:
            k32.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
            state = k32.WaitForSingleObject(handle, 0)
            k32.CloseHandle.argtypes = [ctypes.c_void_p]; k32.CloseHandle(handle)
            assert state == 0, "owned child still alive"
        else: state = None; assert error == 87
        pid_checks.append({"pid": pid, "open_error": error, "wait": state, "alive": False})
    save(root / "pid-postcheck.json", pid_checks)
    for case in ("A-legal-registered", "B-same-dll-unregistered", "C-formal-cold-1", "D-formal-cold-2", "E-post-import-capabilities"):
        directory = root / case
        if directory.exists(): archive_generated(directory)
    # 根工具 build 的自有 cache 也归档后回收；源代码/构建物/日志始终保留。
    if (root / "user").exists():
        with zipfile.ZipFile(root / "build-user-originals.zip", "x", zipfile.ZIP_DEFLATED) as z:
            for p in (root / "user").rglob("*"):
                if p.is_file(): z.write(p, p.relative_to(root))
        with zipfile.ZipFile(root / "build-user-originals.zip") as z: assert z.testzip() is None
        shutil.rmtree(root / "user")
    save(root / "summary.json", {"cold_comparisons": 4, "cases": results, "capability": capability, "production_native_unchanged": True, "host_unchanged": True, "same_formal_fingerprint": formal_manifest["files"] if formal_manifest else None, "not_a_release_package": True})
    print(f"EVIDENCE={root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
