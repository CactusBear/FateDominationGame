"""R53 explicit runtime extension deployment; diagnostic only until proven.

Each child is owned, bounded to 180 seconds and never warm-retried. Inputs,
first failures, native assets and generated caches are preserved by manifest.
"""
from __future__ import annotations
import argparse
import base64
import ctypes
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import shutil
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.request
import zipfile

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools/release'))
import freeze_prepare
sys.path.insert(0, str(REPO))
from tools.diagnostics.project_extension_lifecycle_probe import physical_e, child_env
from tools.diagnostics.legal_extension_control import CAPABILITY_GD, HELPER_CPP

ENGINE_SHA = 'ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424'
DLL_SHA = '92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd'
REV = 'ed1daf0bf001b61586d9930840f2f1394092c079'
EXT = 'addons/fate_server_signals/fate_server_signals.gdextension'
DLL = 'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll'
METHODS = {'FateServerSignals':['enable','protect_worker','disable','take_request'],
           'FateProcessOwner':['available','spawn','state','verify','terminate','release'],
           'FateAtomicFileReplace':['replace_validated_file'],
           'FateCollectionIdentity':['is_supported','candidate_key']}

RUNNER_CPP = r'''
#define NOMINMAX
#include <windows.h>
#include <cstdio>
#include <cwchar>
#include <string>
#include <vector>
static BOOL WINAPI ignore(DWORD){return TRUE;}
static unsigned long long creation(HANDLE h){FILETIME c,e,k,u;if(!GetProcessTimes(h,&c,&e,&k,&u))return 0;return ((unsigned long long)c.dwHighDateTime<<32)|c.dwLowDateTime;}
static bool members(DWORD engine,DWORD keeper){DWORD ids[16]{};DWORD n=GetConsoleProcessList(ids,16);bool e=false,k=false,s=false;if(n!=3)return false;
 for(DWORD i=0;i<n;i++){if(ids[i]==engine)e=true;else if(ids[i]==keeper)k=true;else if(ids[i]==GetCurrentProcessId())s=true;else return false;}
 std::printf("R53_CONSOLE_MEMBERS engine=%lu keeper=%lu sender=%lu count=%lu\n",engine,keeper,GetCurrentProcessId(),n);std::fflush(stdout);return e&&k&&s;}
int wmain(int argc,wchar_t**argv){
 if(argc==6&&!std::wcscmp(argv[1],L"--send-break")){DWORD e=wcstoul(argv[2],nullptr,10),k=wcstoul(argv[3],nullptr,10);
  HANDLE eh=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,e),kh=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,k);
  if(!eh||!kh||creation(eh)!=_wcstoui64(argv[4],nullptr,10)||creation(kh)!=_wcstoui64(argv[5],nullptr,10)||WaitForSingleObject(eh,0)!=WAIT_TIMEOUT||WaitForSingleObject(kh,0)!=WAIT_TIMEOUT)return 5;
  FreeConsole();if(!AttachConsole(k)||!SetConsoleCtrlHandler(ignore,TRUE))return 6;
  if(!members(e,k)||!members(e,k))return 7;
  BOOL ok=GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT,0);CloseHandle(eh);CloseHandle(kh);return ok?0:8;}
 if(argc!=5)return 2;
 SetConsoleCtrlHandler(ignore,TRUE);
 std::wstring cmd=L"\""+std::wstring(argv[1])+L"\" "+argv[4];std::vector<wchar_t>w(cmd.begin(),cmd.end());w.push_back(0);
 STARTUPINFOW s{};s.cb=sizeof(s);s.dwFlags=STARTF_USESTDHANDLES;s.hStdOutput=GetStdHandle(STD_OUTPUT_HANDLE);s.hStdError=GetStdHandle(STD_ERROR_HANDLE);s.hStdInput=GetStdHandle(STD_INPUT_HANDLE);
 wchar_t keeper_pid[32]{};swprintf_s(keeper_pid,L"%lu",GetCurrentProcessId());SetEnvironmentVariableW(L"R49_OWN_DEBUGGER_PID",keeper_pid);
 PROCESS_INFORMATION p{};if(!CreateProcessW(argv[1],w.data(),nullptr,nullptr,TRUE,DEBUG_ONLY_THIS_PROCESS,nullptr,argv[2],&s,&p))return 3;
 std::printf("R53_OWNED engine=%lu creation=%llu keeper=%lu keeper_creation=%llu\n",p.dwProcessId,creation(p.hProcess),GetCurrentProcessId(),creation(GetCurrentProcess()));std::fflush(stdout);
 unsigned long long until=GetTickCount64()+_wcstoui64(argv[3],nullptr,10);bool done=false,timeout=false;DWORD code=0;
 while(!done){DEBUG_EVENT d{};if(!WaitForDebugEvent(&d,100)){if(GetLastError()!=ERROR_SEM_TIMEOUT||GetTickCount64()>until){if(!timeout){TerminateProcess(p.hProcess,0xDEAD);timeout=true;std::printf("R53_TIMEOUT owned=%lu\n",p.dwProcessId);}}continue;}
  DWORD status=DBG_CONTINUE;
  if(d.dwDebugEventCode==LOAD_DLL_DEBUG_EVENT){wchar_t path[32768]{};if(d.u.LoadDll.hFile){GetFinalPathNameByHandleW(d.u.LoadDll.hFile,path,32768,0);CloseHandle(d.u.LoadDll.hFile);}std::printf("R53_MODULE %ls\n",path);}
  if(d.dwDebugEventCode==EXCEPTION_DEBUG_EVENT){auto&e=d.u.Exception;std::printf("R53_EXCEPTION code=%08lx first=%lu pc=%p\n",e.ExceptionRecord.ExceptionCode,e.dwFirstChance,e.ExceptionRecord.ExceptionAddress);if(e.ExceptionRecord.ExceptionCode!=EXCEPTION_BREAKPOINT)status=DBG_EXCEPTION_NOT_HANDLED;}
  if(d.dwDebugEventCode==CREATE_PROCESS_DEBUG_EVENT){if(d.u.CreateProcessInfo.hFile)CloseHandle(d.u.CreateProcessInfo.hFile);if(d.u.CreateProcessInfo.hProcess!=p.hProcess)CloseHandle(d.u.CreateProcessInfo.hProcess);if(d.u.CreateProcessInfo.hThread!=p.hThread)CloseHandle(d.u.CreateProcessInfo.hThread);}
  if(d.dwDebugEventCode==CREATE_THREAD_DEBUG_EVENT)CloseHandle(d.u.CreateThread.hThread);
  if(d.dwDebugEventCode==EXIT_PROCESS_DEBUG_EVENT){done=true;code=d.u.ExitProcess.dwExitCode;std::printf("R53_EXIT engine=%lu code=%lu hex=%08lx timeout=%d\n",p.dwProcessId,code,code,timeout);}
  std::fflush(stdout);if(!ContinueDebugEvent(d.dwProcessId,d.dwThreadId,status)){TerminateProcess(p.hProcess,0xDEAD);timeout=true;}
 }
 WaitForSingleObject(p.hProcess,10000);CloseHandle(p.hThread);CloseHandle(p.hProcess);return timeout?125:code?1:0;
}
'''

PROTOTYPE_GD = '''extends "res://scripts/net/server/server_bootstrap.gd"
const REQUIRED = __METHODS__
func _ready() -> void:
    var before: Array = []
    for name in REQUIRED: before.append(ClassDB.class_exists(name))
    print("R53_NATIVE_BEFORE ", JSON.stringify(before))
    if before.has(true) or not GDExtensionManager.get_loaded_extensions().is_empty():
        _signal_fail("R53 unexpected automatic native loading")
        return
    var descriptor: String = ProjectSettings.globalize_path("res://").path_join("../native/fate_server_signals.gdextension").simplify_path()
    var status: int = GDExtensionManager.load_extension(descriptor)
    var results: Dictionary = {}
    for name in REQUIRED:
        var valid: bool = ClassDB.class_exists(name) and ClassDB.can_instantiate(name)
        for method in REQUIRED[name]: valid = valid and ClassDB.class_has_method(name, method)
        results[name] = valid
    print("R53_NATIVE_AFTER ", JSON.stringify({"status":status,"loaded":GDExtensionManager.is_extension_loaded(descriptor),"classes":results}))
    if status != GDExtensionManager.LOAD_STATUS_OK or results.values().has(false):
        _signal_fail("R53 explicit extension initialization failed")
        return
    super._ready()
func _exit_tree() -> void:
    if _signaling != null: print("R53_SIGNAL_DIAGNOSTICS ", JSON.stringify(_signaling.diagnostics()))
    super._exit_tree()
'''

def sha(p):
    with Path(p).open('rb') as f: return hashlib.file_digest(f, 'sha256').hexdigest()

def save(p, v):
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open('x', encoding='utf-8', newline='\n') as f: json.dump(v, f, ensure_ascii=False, indent=2)

def negative_passed(code, output, *, expected_exit, reason, allowed_errors):
    errors = [line for line in output.splitlines() if line.startswith(('ERROR:','SCRIPT ERROR:'))]
    return (expected_exit in range(1, 126) and code == expected_exit
            and 'SERVER_SIGNALING_READY' not in output and errors.count(reason) == 1
            and errors == allowed_errors)

def native_readback(text):
    def payload(prefix):
        rows = [json.loads(line[len(prefix):]) for line in text.splitlines() if line.startswith(prefix)]
        return rows[0] if len(rows) == 1 else None
    before, after = payload('R53_NATIVE_BEFORE '), payload('R53_NATIVE_AFTER ')
    return before == [False]*4 and after is not None and after.get('status') == 0 and after.get('loaded') is True and after.get('classes') == dict.fromkeys(METHODS, True)

def compile_runner(root):
    (root/'runner.cpp').write_text(RUNNER_CPP, encoding='utf-8', newline='\n')
    cmd = root/'build.cmd'
    cmd.write_text('@call "D:/VS2022/Common7/Tools/VsDevCmd.bat" -arch=x64 -host_arch=x64\n@cl /nologo /utf-8 /EHsc /std:c++17 /W4 /WX /O2 /MT "'+str(root/'runner.cpp')+'" /Fe:"'+str(root/'runner.exe')+'" /Fo:"'+str(root/'runner.obj')+'"\n', encoding='utf-8')
    p = subprocess.run(['cmd.exe','/d','/c',str(cmd)], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    (root/'build.log').write_bytes(p.stdout)
    save(root/'build-result.json', {'exit':p.returncode})
    if p.returncode: raise RuntimeError('console fixture build failed')
    return root/'runner.exe'

def compile_capability_helper(root):
    (root/'capability_helper.cpp').write_text(HELPER_CPP,encoding='utf-8',newline='\n')
    cmd=root/'build-helper.cmd'
    cmd.write_text('@call "D:/VS2022/Common7/Tools/VsDevCmd.bat" -arch=x64 -host_arch=x64\n@cl /nologo /utf-8 /EHsc /std:c++17 /W4 /WX /O2 /MT "'+str(root/'capability_helper.cpp')+'" /Fe:"'+str(root/'capability_helper.exe')+'" /Fo:"'+str(root/'capability_helper.obj')+'"\n',encoding='utf-8')
    p=subprocess.run(['cmd.exe','/d','/c',str(cmd)],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
    (root/'build-helper.log').write_bytes(p.stdout)
    if p.returncode:raise RuntimeError('capability helper build failed')
    return root/'capability_helper.exe'

def official(root):
    mapping = {'manager-current.xml':'https://raw.githubusercontent.com/godotengine/godot/master/doc/classes/GDExtensionManager.xml',
               'classdb-current.xml':'https://raw.githubusercontent.com/godotengine/godot/master/doc/classes/ClassDB.xml',
               'manager-pinned.cpp':f'https://raw.githubusercontent.com/godotengine/godot/{REV}/core/extension/gdextension_manager.cpp',
               'filesystem-pinned.cpp':f'https://raw.githubusercontent.com/godotengine/godot/{REV}/editor/file_system/editor_file_system.cpp',
               'loader-pinned.cpp':f'https://raw.githubusercontent.com/godotengine/godot/{REV}/core/extension/gdextension_library_loader.cpp'}
    result = {}
    for name,url in mapping.items():
        p=root/'official'/name;p.parent.mkdir(exist_ok=True)
        p.write_bytes(urllib.request.urlopen(url, timeout=25).read())
        result[name]={'url':url,'sha256':sha(p)}
    save(root/'official.json',result)

def prepare(root, source):
    rels = freeze_prepare.inventory(source, role='signaling', cold=True)
    hashes = {r:sha(source/r) for r in rels}
    project=root/'project';project.mkdir()
    transformed=freeze_prepare.transform(source, 'FateDomination_demo_v1', rels, 'signaling')
    for rel in rels:
        if rel in (EXT,DLL): continue
        dst=project/rel;dst.parent.mkdir(parents=True, exist_ok=True)
        if rel in transformed: dst.write_text(transformed[rel],encoding='utf-8',newline='\n')
        else: shutil.copyfile(source/rel,dst)
    native=root/'native';native.mkdir()
    shutil.copyfile(source/DLL,native/Path(DLL).name)
    # A declared external deployment map, not a production descriptor edit.
    text=(source/EXT).read_text(encoding='utf-8')
    text=text.replace('"res://'+DLL+'"','"'+Path(DLL).name+'"')
    (native/'fate_server_signals.gdextension').write_text(text,encoding='utf-8',newline='\n')
    (project/'prototype.gd').write_text(PROTOTYPE_GD.replace('__METHODS__',json.dumps(METHODS)),encoding='utf-8',newline='\n')
    (project/'prototype.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://prototype.gd" id="1"]\n[node name="Prototype" type="Node"]\nscript = ExtResource("1")\n',encoding='utf-8',newline='\n')
    p=project/'project.godot';p.write_text(p.read_text(encoding='utf-8').replace('res://assets/scenes/main_menu/server_bootstrap.tscn','res://prototype.tscn'),encoding='utf-8',newline='\n')
    if any(sha(source/r)!=h for r,h in hashes.items()): raise RuntimeError('source drift while preparing')
    files={p.relative_to(root).as_posix():sha(p) for p in root.rglob('*') if p.is_file()}
    save(root/'input-manifest.json',{'source':str(source),'source_files':hashes,'files':files,'external_descriptor':str(native/'fate_server_signals.gdextension'),'mapping':{'windows.x86_64':Path(DLL).name},'cache_before':False})
    return project

def frame(sock, value):
    data=json.dumps(value).encode();mask=os.urandom(4);n=len(data)
    header=bytes([0x81,0x80|n]) if n<126 else bytes([0x81,0x80|126])+struct.pack('!H',n)
    sock.sendall(header+mask+bytes(v^mask[i%4] for i,v in enumerate(data)))

def receive(sock):
    def exact(n):
        out=b''
        while len(out)<n:
            part=sock.recv(n-len(out))
            if not part: raise RuntimeError('unexpected websocket close')
            out+=part
        return out
    a,b=exact(2);n=b&127
    if n==126:n=struct.unpack('!H',exact(2))[0]
    if n==127:n=struct.unpack('!Q',exact(8))[0]
    if a!=0x81 or b&128 or n>262144:raise RuntimeError('unexpected server frame')
    return json.loads(exact(n))

def connect(port):
    s=socket.create_connection(('127.0.0.1',port),timeout=10)
    s.sendall(b'GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n')
    buf=b''
    while not buf.endswith(b'\r\n\r\n'):buf+=s.recv(1)
    if not buf.startswith(b'HTTP/1.1 101'):raise RuntimeError('websocket handshake failed')
    return s

def traffic(port):
    with connect(port) as host,connect(port) as peer:
        frame(host,{'kind':'create'});created=receive(host)
        if created.get('kind')!='created':raise RuntimeError('create failed')
        frame(peer,{'kind':'join','room':created['room']});joined=receive(host)
        if joined.get('kind')!='join_request':raise RuntimeError('join failed')
        nonce=os.urandom(16).hex()
        def invite(kind,origin,target):
            content={'v':1,'nonce':nonce,'from':origin,'to':target,'type':kind,'sdp':'v=0\r\n','candidates':[]}
            return 'FATEP2P1:'+base64.b64encode(json.dumps(content).encode()).decode()
        offer=invite('offer',1,2);answer=invite('answer',2,1)
        frame(host,{'kind':'offer','client':joined['client'],'code':offer})
        if receive(peer)!={'kind':'offer','code':offer}:raise RuntimeError('offer not forwarded')
        frame(peer,{'kind':'answer','code':answer})
        if receive(host)!={'kind':'answer','client':joined['client'],'code':answer}:raise RuntimeError('answer not forwarded')
        forbidden=[]
        for kind in ['game','save','rules','match_command']:
            frame(peer,{'kind':kind});reply=receive(peer)
            if reply!={'kind':'error','reason':'信令服务不接受此消息'}:raise RuntimeError('forbidden traffic accepted')
            forbidden.append(kind)
        return {'create':True,'join':True,'offer':True,'answer':True,'forbidden_rejected':forbidden,'game_payloads_forwarded':False}

def run(root, runner, executable, argv, env, label, *, interaction=None):
    log=root/(label+'.log');q=queue.Queue();lines=[]
    startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    command=[str(runner),str(executable),str(root/'project'),'180000',subprocess.list2cmdline(argv)]
    proc=subprocess.Popen(command,env=env,cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NEW_CONSOLE,startupinfo=startup)
    def reader():
        with log.open('xb') as f:
            for raw in iter(proc.stdout.readline,b''):
                f.write(raw);f.flush();line=raw.decode('utf-8',errors='replace').rstrip();lines.append(line);q.put(line)
        q.put(None)
    t=threading.Thread(target=reader);t.start();start=time.monotonic();owned=None;details={}
    try:
        while True:
            line=q.get(timeout=max(0.01,180-(time.monotonic()-start)))
            if line is None:break
            m=re.fullmatch(r'R53_OWNED engine=(\d+) creation=(\d+) keeper=(\d+) keeper_creation=(\d+)',line)
            if m:owned=[int(x) for x in m.groups()]
            if interaction and line.startswith('SERVER_SIGNALING_READY '):
                payload=json.loads(line.split(' ',1)[1]);details=interaction(payload)
                if owned is None or owned[2]!=proc.pid:raise RuntimeError('unregistered console owner')
                sender=subprocess.run([str(runner),'--send-break',str(owned[0]),str(owned[2]),str(owned[1]),str(owned[3])],cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW,timeout=15)
                (root/(label+'-sender.log')).write_bytes(sender.stdout)
                if sender.returncode:raise RuntimeError('fail-closed console sender refused')
                details['ctrl_break_sender_exit']=sender.returncode
        proc.wait(timeout=10);t.join(timeout=10)
    except BaseException:
        # The native runner retains and bounds its exact engine HANDLE.
        proc.wait(timeout=max(1,190-(time.monotonic()-start)));t.join(timeout=10)
        raise
    text='\n'.join(lines);match=re.search(r'R53_EXIT engine=(\d+) code=(\d+) hex=([0-9a-f]+) timeout=(\d+)',text)
    if match is None:raise RuntimeError('missing owned-child exit receipt')
    result={'keeper_pid':proc.pid,'owned':owned,'exit':int(match[2]),'hex':match[3],'timeout':bool(int(match[4])),'elapsed':time.monotonic()-start,'argv':command,'details':details,'log':str(log),'module_loaded':DLL.split('/')[-1].lower() in text.lower(),'errors':[s for s in lines if s.startswith(('ERROR:','SCRIPT ERROR:'))]}
    save(root/(label+'-result.json'),result)
    return result,text

def archive_generated(root):
    targets=[root/'project/.godot',root/'user']+[p for p in (root/'project').rglob('~*.dll')]
    files=[p for x in targets if x.exists() for p in ([x] if x.is_file() else x.rglob('*')) if p.is_file()]
    entries={p.relative_to(root).as_posix():sha(p) for p in files}
    archive=root/'generated-originals.zip'
    with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED) as z:
        for p in files:z.write(p,p.relative_to(root).as_posix())
    with zipfile.ZipFile(archive) as z:
        if z.testzip() or any(hashlib.sha256(z.read(n)).hexdigest()!=h for n,h in entries.items()):raise RuntimeError('archive verification failed')
    save(root/'generated-archive.json',{'sha256':sha(archive),'files':entries})
    for x in targets:
        if x.is_dir():shutil.rmtree(x)
        elif x.exists():x.unlink()

def negative_contract(result, text, *, require_script_backtrace=True):
    reason='ERROR: 信令配置不可读或包含未知 CFG 段/嵌套覆盖'
    allowed=['ERROR: Parse JSON failed. Error at line 0: Unknown error getting token',reason]
    return (negative_passed(result['exit'],text,expected_exit=2,reason=reason,allowed_errors=allowed)
            and 'at: parse_string (core/io/json.cpp:629)' in text
            and 'at: push_error (core/variant/variant_utility.cpp:1023)' in text
            and (not require_script_backtrace or re.search(r'\[0\] _signal_fail \(res://scripts/net/server/server_bootstrap.gd:\d+\)',text) is not None))

def capabilities(sample, runner, godot, env, helper, *, descriptor=None, project_override=True, label='native-four-capabilities'):
    script=sample/'capabilities.gd'
    text=CAPABILITY_GD.replace('func _initialize() -> void:\n    _run.call_deferred()',
        'func _initialize() -> void:\n    var descriptor: String = OS.get_environment("R53_DESCRIPTOR")\n    if GDExtensionManager.load_extension(descriptor) != GDExtensionManager.LOAD_STATUS_OK:\n        quit(2)\n        return\n    _run.call_deferred()')
    if script.exists():
        if script.read_text(encoding='utf-8')!=text:raise RuntimeError('capability source changed between argv controls')
    else:script.write_text(text,encoding='utf-8',newline='\n')
    env={**env,'R53_DESCRIPTOR':str(descriptor or sample/'native/fate_server_signals.gdextension')}
    argv=['--headless','--rendering-method','gl_compatibility']
    if project_override:argv+=['--path',str(sample/'project')]
    argv+=['--script',str(script),'--',str(sample/'capabilities.json'),str(helper)]
    result,text=run(sample,runner,godot,argv,env,label)
    receipt=json.loads((sample/'capabilities.json').read_text())
    checks=[l for l in text.splitlines() if l.startswith('R49_CAP ')]
    if result['exit'] or result['errors'] or not receipt.get('ok') or len(checks)!=23 or any(not l.endswith('=true') for l in checks):raise RuntimeError('four real native capabilities failed')
    return {**result,'checks':len(checks),'ok':receipt['ok']}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--source',type=Path,default=REPO);ap.add_argument('--root',type=Path,required=True);ap.add_argument('--godot',type=Path,required=True);ap.add_argument('--continue-audit-only',action='store_true')
    a=ap.parse_args();root=physical_e(a.root,fresh=not a.continue_audit_only)
    if not a.continue_audit_only:root.mkdir()
    source=a.source.resolve();godot=a.godot.resolve()
    if sha(godot)!=ENGINE_SHA or sha(source/DLL)!=DLL_SHA:raise RuntimeError('pinned engine or production DLL changed')
    if a.continue_audit_only:
        manifest=json.loads((root/'manifest.json').read_text())
        if manifest.get('failure')!='negative exit/reason/error-scope mismatch' or len(manifest['samples'])!=1:raise RuntimeError('continuation refuses product failure or repeated input')
        first=root/'fresh-1';negative=manifest['samples'][0]['negative']
        if not negative_contract(negative,Path(negative['log']).read_text(encoding='utf-8')):raise RuntimeError('offline negative contract still failed')
        save(root/'offline-first-negative-contract.json',{'passed':True,'expected_exit':2,'scope':'json.cpp parse_string + bootstrap._signal_fail','original_manifest_sha256':sha(root/'manifest.json'),'raw_log_sha256':sha(negative['log']),'no_process_rerun':True})
        tools=root/'continuation-tools';tools.mkdir()
        runner=compile_runner(tools)
        indices=(2,)
    else:
        tools=root
        official(root);runner=compile_runner(tools);manifest={'engine':{'path':str(godot),'sha256':sha(godot)},'dll_sha256':sha(source/DLL),'samples':[],'production_modified':False,'status':'RUNNING'}
        indices=(1,2)
    helper=compile_capability_helper(tools)
    try:
        if a.continue_audit_only:
            env=os.environ.copy()
            for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR'):env[key]=str(first/'user'/key)
            manifest['samples'][0]['capabilities']=capabilities(first,runner,godot,env,helper)
            archive_generated(first)
        for index in indices:
            sample=root/('fresh-'+str(index));sample.mkdir();project=prepare(sample,source);env=child_env(sample)
            cold,text=run(sample,runner,godot,['--headless','--verbose','--rendering-method','gl_compatibility','--editor','--path',str(project),'--import'],env,'first-cold')
            manifest['samples'].append({'root':str(sample),'cold':cold})
            if cold['exit'] or cold['timeout'] or cold['module_loaded'] or cold['errors']:raise RuntimeError('first cold failed; no retry')
            extension_list=project/'.godot/extension_list.cfg'
            if extension_list.exists() and extension_list.read_text().strip():raise RuntimeError('unexpected auto extension list')
            with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
            config=sample/'signaling.json';save(config,{'roles':['relay'],'p2p_signaling':True,'port':port,'bind_address':'127.0.0.1'})
            runtime,text=run(sample,runner,godot,['--headless','--rendering-method','gl_compatibility','--path',str(project),'--','--server-signaling','--config',str(config)],env,'actual-runtime',interaction=lambda p:traffic(p['port']))
            manifest['samples'][-1]['runtime']=runtime
            if runtime['exit'] or runtime['errors'] or not runtime['module_loaded'] or not native_readback(text) or runtime['details'].get('ctrl_break_sender_exit')!=0:raise RuntimeError('runtime/native/traffic/CTRL_BREAK failed')
            negative,text=run(sample,runner,godot,['--headless','--rendering-method','gl_compatibility','--path',str(project),'--','--server-signaling','--config',str(sample/'missing.json')],env,'negative-missing')
            manifest['samples'][-1]['negative']=negative
            if not negative_contract(negative,text):raise RuntimeError('negative exit/reason/error-scope mismatch')
            manifest['samples'][-1]['capabilities']=capabilities(sample,runner,godot,env,helper)
            archive_generated(sample)
        manifest['status']='PROTOTYPE_TWO_FRESH_GREEN_NOT_RELEASE'
    except Exception as exc:
        manifest['status']='BLOCKED';manifest['failure']=str(exc)
    if manifest['status']=='PROTOTYPE_TWO_FRESH_GREEN_NOT_RELEASE':manifest.pop('failure',None)
    target=root/('manifest-continuation.json' if a.continue_audit_only else 'manifest.json')
    save(target,manifest)
    print(json.dumps({'status':manifest['status'],'failure':manifest.get('failure'),'manifest':str(target)},ensure_ascii=False))
    return 0 if manifest['status']=='PROTOTYPE_TWO_FRESH_GREEN_NOT_RELEASE' else 1

if __name__=='__main__':raise SystemExit(main())