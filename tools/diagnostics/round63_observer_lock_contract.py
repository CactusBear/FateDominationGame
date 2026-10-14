"""Owned synthetic Windows observer/publication causality, fixed three samples.

Only new diagnostics. Replays frozen archive and actual tree_bytes; holds real
read/stat boundaries by events, records actual Win32 calls in owned descendants.
Never attaches, retries publication, copies game data, or archives payloads.
"""
from __future__ import annotations
import sys
sys.dont_write_bytecode = True
import argparse, ast, ctypes as c, hashlib, importlib.util, json, os, re, shutil, subprocess, threading, uuid
from ctypes import wintypes as w
from pathlib import Path, PureWindowsPath
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[2]
ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
HISTORY = Path('E:/scratch/isolated-eaec18432e9e4e6cb0ec49d82f0d8ffc/evidence/runner.py')
VARIANTS = ('none','tree_bytes','archive_python','archive_fileaccess','archive_sharedelete','ordinary_lock','archive_sharedelete_afterexit')

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

def digest(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def declared_file(scope, path):
    raw = str(path).replace('\\','/')
    if any(x in {'.','..'} for x in raw.split('/')) or ':' in raw[2:]:raise ValueError('noncanonical file')
    p, root = PureWindowsPath(raw), PureWindowsPath(scope['fixture_root'])
    token = scope.get('run_id','')
    if not re.fullmatch('[a-f0-9]{32}', token) or root.parts[-3:] != ('isolated-'+token,'generated','f'):raise ValueError('invalid declared ownership')
    if not p.is_absolute() or p.drive.upper()!='E:' or not p.is_relative_to(root) or str(p) not in {str(PureWindowsPath(x)) for x in scope['files']}:raise ValueError('undeclared observation file')
    return p

def read_declared(scope,path,reader):
    declared_file(scope,path)
    return reader(Path(path))

def emit(prefix, row):print(prefix+' '+json.dumps(row,separators=(',',':')),flush=True)

def api():
    k=c.WinDLL('kernel32',use_last_error=True)
    sig={
        'GetCurrentThreadId':([],w.DWORD),
        'CreateFileW':([w.LPCWSTR,w.DWORD,w.DWORD,w.LPVOID,w.DWORD,w.DWORD,w.HANDLE],w.HANDLE),
        'ReadFile':([w.HANDLE,w.LPVOID,w.DWORD,c.POINTER(w.DWORD),w.LPVOID],w.BOOL),
        'CloseHandle':([w.HANDLE],w.BOOL),
        'MoveFileW':([w.LPCWSTR,w.LPCWSTR],w.BOOL),
        'ReplaceFileW':([w.LPCWSTR,w.LPCWSTR,w.LPCWSTR,w.DWORD,w.LPVOID,w.LPVOID],w.BOOL),
        'CreateEventW':([w.LPVOID,w.BOOL,w.BOOL,w.LPCWSTR],w.HANDLE),
        'OpenEventW':([w.DWORD,w.BOOL,w.LPCWSTR],w.HANDLE),
        'SetEvent':([w.HANDLE],w.BOOL),
        'WaitForSingleObject':([w.HANDLE,w.DWORD],w.DWORD),
        'GetFileInformationByHandle':([w.HANDLE,w.LPVOID],w.BOOL),
    }
    for name,(args,ret) in sig.items():getattr(k,name).argtypes=args;getattr(k,name).restype=ret
    return k

class FileInfo(c.Structure):
    _fields_=[('attributes',w.DWORD),('creation',w.FILETIME),('access',w.FILETIME),('write',w.FILETIME),('volume',w.DWORD),('size_high',w.DWORD),('size_low',w.DWORD),('links',w.DWORD),('index_high',w.DWORD),('index_low',w.DWORD)]

def identity(k,path):
    h=k.CreateFileW(str(path),0x80,7,None,3,0x02000000|0x00200000,None)
    if h==c.c_void_p(-1).value:raise c.WinError(c.get_last_error())
    try:
        info=FileInfo()
        if not k.GetFileInformationByHandle(h,c.byref(info)):raise c.WinError(c.get_last_error())
        if info.attributes&0x400:raise ValueError('reparse identity')
        return {'volume':str(info.volume),'file_index':str(info.index_high<<32|info.index_low),'links':info.links}
    finally:k.CloseHandle(h)

def read_handle(k,h):
    b=c.create_string_buffer(4096);n=w.DWORD()
    if not k.ReadFile(h,b,len(b),c.byref(n),None):raise c.WinError(c.get_last_error())
    return b.raw[:n.value]

def old_archive(namespace):
    text=HISTORY.read_text(encoding='utf-8')
    node=next(x for x in ast.parse(text).body if isinstance(x,ast.FunctionDef) and x.name=='archive')
    exec(compile(ast.Module(body=[node],type_ignores=[]),str(HISTORY),'exec'),namespace)
    return namespace['archive']

def shared_reader(namespace):
    path=PROJECT/'tests/round62_loader_error_boundary_runner.py'
    node=next(x for x in ast.parse(path.read_text(encoding='utf-8')).body if isinstance(x,ast.FunctionDef) and x.name=='shared_read')
    exec(compile(ast.Module(body=[node],type_ignores=[]),str(path),'exec'),namespace)
    return namespace['shared_read']

GDSCRIPT = r'''extends SceneTree
func _initialize():
    var a = OS.get_cmdline_user_args()
    var role = a[0]
    if role == "reader":
        a[1] = a[1].replace("\\", "/")
        a[2] = a[2].replace("\\", "/")
        read_tree(a[1], a)
        quit(0)
    elif role == "rename":
        var code = DirAccess.rename_absolute(a[1], a[2])
        print("GODOT_OPERATION " + JSON.stringify({"ok":code == OK,"godot_error":code,"pid":OS.get_process_id()}))
        quit(0)
    else:
        if not ClassDB.class_exists("FateAtomicFileReplace"):
            print("GODOT_OPERATION " + JSON.stringify({"blocked":"native_class_missing"}))
            quit(24)
            return
        var backend = ClassDB.instantiate("FateAtomicFileReplace")
        var result = backend.call("replace_validated_file", a[1], a[2], int(a[3]))
        result["pid"] = OS.get_process_id()
        print("GODOT_OPERATION " + JSON.stringify(result))
        quit(0)
func read_tree(root:String, a:PackedStringArray):
    var directory = DirAccess.open(root)
    if directory == null:
        quit(25)
        return
    directory.list_dir_begin()
    var name = directory.get_next()
    while not name.is_empty():
        var path = root.path_join(name)
        if directory.current_is_dir():
            if name != "." and name != "..": read_tree(path, a)
        elif path == a[2]:
            var f = FileAccess.open(path, FileAccess.READ)
            if f == null:
                quit(26)
                return
            print("GODOT_HOLD_READY")
            var release_line = OS.read_string_from_stdin()
            if release_line.strip_edges() != "release":
                f.close()
                quit(27)
                return
            var bytes = f.get_buffer(f.get_length())
            var hash = HashingContext.new()
            hash.start(HashingContext.HASH_SHA256)
            hash.update(bytes)
            print("GODOT_OBSERVER " + JSON.stringify({"sha256":hash.finish().hex_encode(),"bytes":bytes.size(),"pid":OS.get_process_id()}))
            f.close()
        name = directory.get_next()
    directory.list_dir_end()
'''

# Reviewed scoped utilities are reused from assembly_publish_failure_capture.
# New wmain supports only DEBUG_PROCESS descendants it has created. No attach.
DEBUG_MAIN = r'''
struct Pending { std::string api; std::wstring path,second; DWORD64 teb=0,ret=0,access=0,share=0,seq=0; };
struct State {
 HANDLE process=nullptr; DWORD parent=0; DWORD64 base=0;
 std::map<DWORD,HANDLE> threads; std::map<DWORD64,BP> breaks;
 std::map<DWORD,DWORD64> steps; std::map<DWORD,Pending> pending;
 std::map<DWORD,std::vector<DWORD>> suspended;
};
std::map<DWORD,State> states;
std::map<DWORD64,std::string> names;
DWORD64 serial=0;
void suspend_other(State &s,DWORD tid) {
 for(auto t:s.threads)if(t.first!=tid){must(SuspendThread(t.second)!=DWORD(-1),"owned_thread_suspend");s.suspended[tid].push_back(t.first);}
}
void resume_other(State &s,DWORD tid) {
 for(auto id:s.suspended[tid])if(s.threads.count(id))must(ResumeThread(s.threads[id])!=DWORD(-1),"owned_thread_resume");s.suspended.erase(tid);
}
std::wstring handlepath(HANDLE process,HANDLE handle) {
 HANDLE duplicate=nullptr; if(!DuplicateHandle(process,handle,GetCurrentProcess(),&duplicate,0,FALSE,DUPLICATE_SAME_ACCESS))return L"";
 wchar_t path[32768]{};DWORD n=GetFinalPathNameByHandleW(duplicate,path,32768,0);CloseHandle(duplicate);return n&&n<32768?std::wstring(path):L"";
}
void install_exports(State &s,HANDLE file,DWORD64 base) {
 wchar_t path[32768]{};DWORD n=GetFinalPathNameByHandleW(file,path,32768,0);if(!n)return;
 auto normalizedPath=normalized(path);auto basename=normalizedPath.substr(normalizedPath.find_last_of(wchar_t(92))+1);
 if(basename!=L"kernelbase.dll"&&basename!=L"kernel32.dll")return;
 HMODULE lookup=GetModuleHandleW(basename.c_str());must(lookup!=nullptr,"local_loaded_api_module");
 for(auto name:{"CreateFileW","MoveFileW","ReplaceFileW","SetFileInformationByHandle","GetFileInformationByName"}) {
  auto fn=GetProcAddress(lookup,name);if(!fn)continue;HMODULE local=nullptr;
  must(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,(LPCWSTR)fn,&local)!=0,"actual_export_module");
  wchar_t localPath[32768]{};must(GetModuleFileNameW(local,localPath,32768)!=0,"actual_export_module_path");auto localName=normalized(localPath);localName=localName.substr(localName.find_last_of(wchar_t(92))+1);if(localName!=basename)continue;
  DWORD64 off=(DWORD64)fn-(DWORD64)local,pc=base+off;
  unsigned char remote[8]{};must(readmem(pc,remote,8),"export_bytes_read");must(std::equal(remote,remote+8,(unsigned char*)fn),"same_actual_export_bytes");
  arm(pc,10,true);names[pc]=name;
 }
}
int wmain(int argc,wchar_t **argv) {
 if(argc!=5)return 2;
 SetErrorMode(SEM_FAILCRITICALERRORS|SEM_NOGPFAULTERRORBOX);
 fixture_root=argv[4];source_root=fixture_root;
 try {
  must(normalized(fixture_root).rfind(L"e:\\scratch\\isolated-",0)==0,"E_UUID_scope");
  SetLastError(0x4321);must(*(DWORD*)((unsigned char*)NtCurrentTeb()+0x68)==0x4321,"TEB_LastErrorValue_layout");
  std::wstring cmd=L"\""+std::wstring(argv[1])+L"\" -B \""+argv[2]+L"\" --actor \""+argv[3]+L"\"";
  std::vector<wchar_t> text(cmd.begin(),cmd.end());text.push_back(0);
  STARTUPINFOW st{};st.cb=sizeof(st);st.dwFlags=STARTF_USESTDHANDLES;st.hStdOutput=GetStdHandle(STD_OUTPUT_HANDLE);st.hStdError=GetStdHandle(STD_ERROR_HANDLE);st.hStdInput=GetStdHandle(STD_INPUT_HANDLE);
  PROCESS_INFORMATION pi{};must(CreateProcessW(argv[1],text.data(),nullptr,nullptr,TRUE,DEBUG_PROCESS|CREATE_NO_WINDOW,nullptr,nullptr,&st,&pi)!=0,"owned_python_create");
  CloseHandle(pi.hThread);CloseHandle(pi.hProcess);
  ULONGLONG deadline=GetTickCount64()+240000;bool alive=true;DWORD rootcode=0;
  while(alive){
   DEBUG_EVENT ev{};if(!WaitForDebugEvent(&ev,100)){must(GetLastError()==ERROR_SEM_TIMEOUT,"debug_wait");must(GetTickCount64()<deadline,"owned_capture_deadline");continue;}
   DWORD status=DBG_CONTINUE;
   if(ev.dwDebugEventCode==CREATE_PROCESS_DEBUG_EVENT){
    auto &s=states[ev.dwProcessId];s.process=ev.u.CreateProcessInfo.hProcess;s.base=(DWORD64)ev.u.CreateProcessInfo.lpBaseOfImage;s.threads[ev.dwThreadId]=ev.u.CreateProcessInfo.hThread;
    BOOL inJob=FALSE;must(IsProcessInJob(s.process,nullptr,&inJob)&&inJob,"owned_descendant_job");
    FILETIME ct,et,kt,ut;must(GetProcessTimes(s.process,&ct,&et,&kt,&ut)!=0,"creation_time");
    std::printf("OWNED_PID pid=%lu creation=%llu in_job=%d root=%d\n",ev.dwProcessId,((uint64_t)ct.dwHighDateTime<<32)|ct.dwLowDateTime,inJob,ev.dwProcessId==pi.dwProcessId);
    if(ev.u.CreateProcessInfo.hFile)CloseHandle(ev.u.CreateProcessInfo.hFile);
   } else {
    must(states.count(ev.dwProcessId)!=0,"only_created_debug_child");auto &s=states[ev.dwProcessId];target_process=s.process;bp.swap(s.breaks);
    switch(ev.dwDebugEventCode){
    case CREATE_THREAD_DEBUG_EVENT:s.threads[ev.dwThreadId]=ev.u.CreateThread.hThread;break;
    case EXIT_THREAD_DEBUG_EVENT:if(s.threads.count(ev.dwThreadId)){CloseHandle(s.threads[ev.dwThreadId]);s.threads.erase(ev.dwThreadId);}break;
    case LOAD_DLL_DEBUG_EVENT:install_exports(s,ev.u.LoadDll.hFile,(DWORD64)ev.u.LoadDll.lpBaseOfDll);if(ev.u.LoadDll.hFile)CloseHandle(ev.u.LoadDll.hFile);break;
    case EXCEPTION_DEBUG_EVENT:{
     DWORD code=ev.u.Exception.ExceptionRecord.ExceptionCode;DWORD64 pc=(DWORD64)ev.u.Exception.ExceptionRecord.ExceptionAddress;
     if(code==EXCEPTION_SINGLE_STEP&&s.steps.count(ev.dwThreadId)){
      auto address=s.steps[ev.dwThreadId];patch(address,0xcc);s.steps.erase(ev.dwThreadId);CONTEXT ctx{};ctx.ContextFlags=CONTEXT_ALL;must(GetThreadContext(s.threads[ev.dwThreadId],&ctx)!=0,"step_context");ctx.EFlags&=~0x100;must(SetThreadContext(s.threads[ev.dwThreadId],&ctx)!=0,"step_restore");resume_other(s,ev.dwThreadId);break;
     }
     if(code==EXCEPTION_BREAKPOINT&&bp.count(pc)){
      BP b=bp[pc];patch(pc,b.original);CONTEXT ctx{};ctx.ContextFlags=CONTEXT_ALL;must(GetThreadContext(s.threads[ev.dwThreadId],&ctx)!=0,"break_context");ctx.Rip=pc;
      if(b.kind==10){
       Pending p;p.api=names[pc];
       if(p.api=="CreateFileW"||p.api=="MoveFileW"||p.api=="ReplaceFileW"||p.api=="GetFileInformationByName"){p.path=wide(ctx.Rcx);if(p.api=="MoveFileW"||p.api=="ReplaceFileW")p.second=wide(ctx.Rdx);}
       else p.path=handlepath(s.process,(HANDLE)ctx.Rcx);
       if(inside(p.path,fixture_root)&&!s.pending.count(ev.dwThreadId)){
        p.access=ctx.Rdx;p.share=ctx.R8;p.teb=teb(s.threads[ev.dwThreadId]);p.seq=++serial;must(readmem(ctx.Rsp,&p.ret,8),"return_address");
        s.pending[ev.dwThreadId]=p;arm(p.ret,11,false);
        std::printf("OBS_API_BEGIN seq=%llu pid=%lu tid=%lu api=%s path=%s second=%s access=%llu share=%llu teb=0x%llx return_pc=0x%llx return_rva=0x%llx\n",p.seq,ev.dwProcessId,ev.dwThreadId,p.api.c_str(),utf8(p.path).c_str(),utf8(p.second).c_str(),p.access,p.share,p.teb,p.ret,p.ret-s.base);
       }
       suspend_other(s,ev.dwThreadId);ctx.EFlags|=0x100;s.steps[ev.dwThreadId]=pc;
      } else {
       must(b.kind==11&&s.pending.count(ev.dwThreadId),"paired_target_return");auto p=s.pending[ev.dwThreadId];must(pc==p.ret,"same_return_pc");
       DWORD error=0;must(readmem(p.teb+0x68,&error,4),"same_thread_LastErrorValue");
       std::printf("OBS_API_END seq=%llu pid=%lu tid=%lu api=%s return=%llu last_error=%lu teb=0x%llx return_pc=0x%llx\n",p.seq,ev.dwProcessId,ev.dwThreadId,p.api.c_str(),ctx.Rax,error,p.teb,pc);
       s.pending.erase(ev.dwThreadId);bp.erase(pc);
      }
      must(SetThreadContext(s.threads[ev.dwThreadId],&ctx)!=0,"restore_original_call");break;
     }
     if(code==EXCEPTION_BREAKPOINT&&ev.u.Exception.dwFirstChance)break;
     status=DBG_EXCEPTION_NOT_HANDLED;if(!ev.u.Exception.dwFirstChance){std::printf("SECOND_CHANCE pid=%lu code=%lu\n",ev.dwProcessId,code);must(false,"owned_crash");}break;
    }
    case EXIT_PROCESS_DEBUG_EVENT:
     std::printf("OWNED_EXIT pid=%lu exit=%lu\n",ev.dwProcessId,ev.u.ExitProcess.dwExitCode);if(ev.dwProcessId==pi.dwProcessId)rootcode=ev.u.ExitProcess.dwExitCode;
     must(s.pending.empty(),"no_missing_API_returns");for(auto t:s.threads)CloseHandle(t.second);CloseHandle(s.process);break;
    }
    bp.swap(s.breaks);
   }
   std::fflush(stdout);must(ContinueDebugEvent(ev.dwProcessId,ev.dwThreadId,status)!=0,"continue_owned");
   if(ev.dwDebugEventCode==EXIT_PROCESS_DEBUG_EVENT)states.erase(ev.dwProcessId);
   alive=!states.empty();
  }
  std::printf("CAPTURE_EXIT root_code=%lu\n",rootcode);return rootcode?1:0;
 }catch(const std::exception &e){std::printf("CAPTURE_BLOCK %s\n",e.what());for(auto &s:states)TerminateProcess(s.second.process,126);return 2;}
}
'''

def actor(scopepath):
    scope=json.loads(Path(scopepath).read_text(encoding='utf-8'));r=load('round63_actual_runner',PROJECT/'tools/run_isolated_godot_test.py');native=load('round63_native_scope',PROJECT/'tools/diagnostics/assembly_native_probe.py')
    generated=native.safe(scope['generated']);fixture=native.within(scope['fixture_root'],generated)
    if fixture!=generated/'f' or digest(scope['engine'])!=scope['engine_sha256']:raise ValueError('changed engine/scope')
    k=api();rows=[]
    for case in scope['cases']:
        source,target,observed=map(Path,[case['source'],case['target'],case['observed']])
        native.within(source,fixture);native.within(target,fixture);declared_file(scope,observed);native.safe(observed)
        expected=case['old_sha256'];parent_before=identity(k,target.parent);old_id=identity(k,observed)
        source_id=identity(k,source)
        if digest(observed)!=expected or source_id['volume']!=old_id['volume']:raise ValueError('preflight identity/hash failed')
        emit('CASE_BEGIN',case)
        ready=threading.Event();release=threading.Event();observer={'variant':case['variant'],'held':False};observer_errors=[]
        base=observed.parent if case['operation']=='replace' else source
        observer_process=None
        def gate():
            observer['held']=True;observer['pid']=os.getpid();observer['tid']=k.GetCurrentThreadId()
            emit('OBSERVER_GATE',{'case':case['id'],**observer});ready.set()
            if not release.wait(30):raise ValueError('hold timeout')
        def observe():
            try:
                variant=case['variant']
                if variant in {'none','archive_sharedelete_afterexit'}:gate();return
                if variant=='tree_bytes':
                    original=Path.stat
                    def stat(path,*a,**kw):
                        value=original(path,*a,**kw)
                        if path==observed and not observer['held']:gate()
                        return value
                    original_open=Path.open
                    def no_content_open(path,*a,**kw):
                        if threading.get_ident()==observer_thread_id:raise AssertionError('tree_bytes must not open content')
                        return original_open(path,*a,**kw)
                    observer_thread_id=threading.get_ident()
                    with patch.object(Path,'stat',stat),patch.object(Path,'open',no_content_open):
                        observer['tree_bytes']=r.tree_bytes(base)
                    return
                if variant=='archive_python':
                    original=Path.open;observer_thread_id=threading.get_ident()
                    def opened(path,*a,**kw):
                        if threading.get_ident()==observer_thread_id and path.is_relative_to(fixture):declared_file(scope,path)
                        stream=original(path,*a,**kw)
                        if path==observed and not observer['held']:
                            import msvcrt
                            observer['handle']=msvcrt.get_osfhandle(stream.fileno());gate()
                        return stream
                    archive_dest=generated/'archive'/case['id'];archive_dest.mkdir(parents=True)
                    ns={'fixtures':base,'g':generated,'ev':archive_dest,'r':r,'hashlib':hashlib,'archive_lock':threading.Lock()}
                    # Missing appdata/localappdata are intentional empty original roots.
                    with patch.object(Path,'open',opened):old_archive(ns)()
                    copies=[p for p in (archive_dest/'runtime').rglob('*.json')]
                    observer['archive_hashes']=[digest(p) for p in copies]
                    observer['archived_expected']=expected in observer['archive_hashes']
                    return
                if variant=='archive_sharedelete':
                    original_dll=c.WinDLL
                    class Function:
                        def __init__(self,f):self.f=f
                        def __setattr__(self,key,value):
                            if key in {'argtypes','restype'}:setattr(self.f,key,value)
                            else:object.__setattr__(self,key,value)
                        def __call__(self,*a):
                            h=self.f(*a)
                            if str(a[0])==str(observed) and h!=c.c_void_p(-1).value:observer['handle']=h;observer['share_declared']=a[2];gate()
                            return h
                    class Proxy:
                        def __init__(self,dll):self.dll=dll;self.CreateFileW=Function(dll.CreateFileW)
                        def __getattr__(self,key):return getattr(self.dll,key)
                    def dll(name,*a,**kw):return Proxy(original_dll(name,*a,**kw)) if name=='kernel32' else original_dll(name,*a,**kw)
                    ns={'r':r}
                    with patch.object(c,'WinDLL',dll):data=read_declared(scope,observed,shared_reader(ns))
                    observer.update(sha256=hashlib.sha256(data).hexdigest(),bytes=len(data));return
                if variant=='ordinary_lock':
                    h=k.CreateFileW(str(observed),0x80000000,3,None,3,0,None)
                    if h==c.c_void_p(-1).value:raise c.WinError(c.get_last_error())
                    try:observer.update(handle=h,share_declared=3);gate();data=read_handle(k,h);observer.update(sha256=hashlib.sha256(data).hexdigest(),bytes=len(data))
                    finally:k.CloseHandle(h)
                    return
                raise ValueError('unknown variant')
            except Exception as exc:observer_errors.append(repr(exc));ready.set()
        thread=None
        try:
            if case['variant']=='archive_fileaccess':
                cmd=[scope['engine'],'--headless','--path',scope['project'],'--script','res://probe.gd','--','reader',str(base),str(observed)]
                observer_process=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8')
                observer_prefix=[]
                def reader_ready():
                    for line in observer_process.stdout:
                        observer_prefix.append(line)
                        if line.strip()=='GODOT_HOLD_READY':ready.set();return
                    observer_errors.append('reader exited before actual open readiness');ready.set()
                handshake=threading.Thread(target=reader_ready);handshake.start()
                if not ready.wait(30) or observer_errors:raise ValueError('FileAccess actual open gate failed '+repr(observer_errors))
                handshake.join(1)
                observer['held']=True
            else:
                thread=threading.Thread(target=observe);thread.start()
                if not ready.wait(30) or observer_errors:raise ValueError('observer failed before ready '+repr(observer_errors))
            # Fresh-reader independently opened while the original reader remains held.
            fresh_old_error=None
            fresh_old=digest(observed)
            if fresh_old!=expected:raise ValueError('held old object changed before call')
            if case['actor']=='winapi':
                c.set_last_error(0)
                if case['operation']=='rename':ok=k.MoveFileW(str(source),str(target));api_name='MoveFileW'
                else:ok=k.ReplaceFileW(str(target),str(source),None,0,None,None);api_name='ReplaceFileW'
                error=c.get_last_error()
                result={'ok':bool(ok),'native_error':error if not ok else None,'raw_last_error':error,'api':api_name,'pid':os.getpid()}
            else:
                cmd=[scope['engine'],'--headless','--path',scope['project'],'--script','res://probe.gd','--',case['operation'],str(source),str(target),str(case['new_bytes'])]
                p=subprocess.run(cmd,capture_output=True,text=True,encoding='utf-8',timeout=30)
                emit('GODOT_RAW',{'case':case['id'],'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
                results=[json.loads(x.split(' ',1)[1]) for x in p.stdout.splitlines() if x.startswith('GODOT_OPERATION ')]
                if p.returncode or len(results)!=1 or 'SCRIPT ERROR' in p.stderr or 'ERROR:' in p.stderr:raise ValueError('Godot actual operation failed to execute')
                result=results[0]
            after_path=target/'payload.json' if case['operation']=='rename' and result['ok'] else observed
            old_after=identity(k,after_path);fresh_new=digest(after_path)
            if case['operation']=='rename':
                content_ok=fresh_new==expected and old_after==old_id and source.exists()==(not result['ok'])
            else:
                content_ok=fresh_new==(case['new_sha256'] if result['ok'] else expected) and source.exists()==(not result['ok'])
                if result['ok']:content_ok=content_ok and old_after==source_id and old_after!=old_id
                else:content_ok=content_ok and digest(source)==case['new_sha256'] and old_after==old_id
            if parent_before!=identity(k,target.parent):raise ValueError('publication parent identity changed')
            row={'id':case['id'],'variant':case['variant'],'actor':case['actor'],'operation':case['operation'],'result':result,'parent_identity':parent_before,'old_identity':old_id,'source_identity':source_id,'after_identity':old_after,'fresh_old_sha256':fresh_old,'fresh_old_open_error':fresh_old_error,'fresh_after_sha256':fresh_new,'content_ok':content_ok,'held_during_operation':observer['held']}
        finally:
            release.set()
            if thread:thread.join(30)
            if observer_process:
                out,err=observer_process.communicate(input='release\n',timeout=30)
                out=''.join(observer_prefix)+out
                emit('GODOT_READER_RAW',{'case':case['id'],'exit':observer_process.returncode,'stdout':out,'stderr':err})
                values=[json.loads(x.split(' ',1)[1]) for x in out.splitlines() if x.startswith('GODOT_OBSERVER ')]
                if observer_process.returncode or len(values)!=1 or err.strip():observer_errors.append('FileAccess readback failed '+err)
                else:observer.update(values[0])
        row['observer']=observer;row['observer_errors']=observer_errors
        if case['variant']=='archive_python':row['observer_content_ok']=observer.get('archived_expected') is True
        elif case['variant'] in {'archive_fileaccess','archive_sharedelete','ordinary_lock'}:row['observer_content_ok']=observer.get('sha256')==expected
        else:row['observer_content_ok']=not observer_errors
        emit('CASE_END',row);rows.append(row)
    text=json.dumps(rows,indent=2);Path(scope['results']).write_text(text,encoding='utf-8')
    if json.loads(Path(scope['results']).read_text(encoding='utf-8'))!=rows:raise ValueError('actor readback')


def capture_source():
    capture=load('round63_assembly_capture',PROJECT/'tools/diagnostics/assembly_publish_failure_capture.py')
    debug=load('round63_debug_prefix',PROJECT/'tools/diagnostics/native_cold_import_debug.py')
    # Preserve existing path, TEB, scoped memory and breakpoint helpers exactly.
    cpp=debug.DEBUGGER_CPP.split('int wmain(',1)[0]+capture.CPP.split('void receive_gate()',1)[0]+DEBUG_MAIN
    if 'DebugActiveProcess(' in cpp or 'Sleep(' in cpp:raise ValueError('attach/sleep prohibited')
    return capture,cpp

def parse_api(text):
    pending={};rows=[]
    for line in text.splitlines():
        if line.startswith('OBS_API_BEGIN '):
            row=dict(re.findall(r'(\w+)=([^\s]*)',line));seq=row['seq']
            if seq in pending:raise ValueError('duplicate begin')
            pending[seq]=row
        elif line.startswith('OBS_API_END '):
            end=dict(re.findall(r'(\w+)=([^\s]*)',line));row=pending.pop(end['seq'])
            if any(row[x]!=end[x] for x in ['pid','tid','api','teb','return_pc']):raise ValueError('mismatched API return')
            row.update(return_value=int(end['return']),last_error=int(end['last_error']))
            failed=(row['return_value']==2**64-1) if row['api']=='CreateFileW' else row['return_value']==0
            row['failure_error']=row['last_error'] if failed else None
            rows.append(row)
    if pending:raise ValueError('incomplete actual API pairs')
    return rows


def execute():
    r=load('round63_isolation',PROJECT/'tools/run_isolated_godot_test.py');capture,cpp=capture_source()
    binding=capture.engine_binding(ENGINE)
    dll=PROJECT/'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll'
    if digest(dll)!='92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd':raise ValueError('not approved old DLL')
    token=uuid.uuid4().hex;owner=r.physical_e('E:/scratch')/('isolated-'+token);owner.mkdir();g=owner/'generated';g.mkdir();ev=owner/'evidence';ev.mkdir()
    report={'run_id':token,'generated':str(g),'processes':[],'passed':False,'engine_binding':binding,'old_dll_sha256':digest(dll),'historical_root_cause':'UNPROVEN; this matrix tests only mechanism','repetitions':3,'payload_archived':False}
    print('ROUND63_OWNER '+str(owner),flush=True)
    def save():
        text=json.dumps(report,ensure_ascii=False,indent=2);(owner/'manifest.json').write_text(text,encoding='utf-8');(ev/'report.json').write_text(text,encoding='utf-8')
        if json.loads((ev/'report.json').read_text(encoding='utf-8'))!=report:raise ValueError('report readback')
    try:
        project=g/'project';project.mkdir();fixture=g/'f';fixture.mkdir()
        engine=g/'Godot.exe';shutil.copyfile(ENGINE,engine)
        targetdll=project/'addons/fate_server_signals/bin'/dll.name;targetdll.parent.mkdir(parents=True);shutil.copyfile(dll,targetdll)
        extension=PROJECT/'addons/fate_server_signals/fate_server_signals.gdextension';shutil.copyfile(extension,project/'addons/fate_server_signals/fate_server_signals.gdextension')
        cache=project/'.godot';cache.mkdir();(cache/'extension_list.cfg').write_text('res://addons/fate_server_signals/fate_server_signals.gdextension\n',encoding='utf-8')
        (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Round63OwnedObserver"\n[threading]\nworker_pool/max_threads=20\n',encoding='utf-8')
        (project/'probe.gd').write_text(GDSCRIPT,encoding='utf-8')
        report['source_hashes']={str(x):digest(x) for x in [ENGINE,dll,extension,HISTORY,PROJECT/'tests/round62_loader_error_boundary_runner.py',PROJECT/'tools/run_isolated_godot_test.py',PROJECT/'tools/diagnostics/assembly_native_probe.py',PROJECT/'tools/diagnostics/assembly_publish_failure_capture.py',PROJECT/'tools/diagnostics/native_cold_import_debug.py']}
        report['frozen_hashes']={str(x.relative_to(g)):digest(x) for x in [engine,targetdll,project/'probe.gd',project/'project.godot']}
        cases=[];files=[]
        for variant in VARIANTS:
            for actorname in ['godot','winapi']:
                for op in ['rename','replace']:
                    for n in range(3):
                        name=f'{variant}-{actorname}-{op}-{n}';base=fixture/name;base.mkdir()
                        old=('synthetic-round63-old-'+name).encode();new=('synthetic-round63-new-'+name+'-complete').encode()
                        if op=='rename':source=base/'data.building-0';source.mkdir();observed=source/'payload.json';observed.write_bytes(old);target=base/'data'
                        else:target=observed=base/'payload.json';observed.write_bytes(old);source=base/'complete.tmp';source.write_bytes(new)
                        files.append(str(observed))
                        if op=='rename':files.append(str(target/'payload.json'))
                        cases.append({'id':name,'variant':variant,'actor':actorname,'operation':op,'source':str(source),'target':str(target),'observed':str(observed),'old_sha256':hashlib.sha256(old).hexdigest(),'new_sha256':hashlib.sha256(new).hexdigest(),'new_bytes':len(new)})
        scope={'version':1,'run_id':token,'generated':str(g),'fixture_root':str(fixture),'files':files,'cases':cases,'engine':str(engine),'engine_sha256':digest(engine),'project':str(project),'results':str(g/'results.json')}
        # Existing assembly path/identity helper is reused read-only, never relaxed.
        native=load('round63_preflight_native',PROJECT/'tools/diagnostics/assembly_native_probe.py');native.safe(fixture)
        for case in cases:declared_file(scope,case['observed']);native.within(case['source'],fixture);native.within(case['target'],fixture)
        scopepath=g/'scope.json';scopepath.write_text(json.dumps(scope,indent=2),encoding='utf-8');report['scope_sha256']=digest(scopepath);report['case_count']=len(cases)
        (g/'capture.cpp').write_text(cpp,encoding='utf-8')
        build=g/'build-round63.cmd';build.write_text(f'@call "D:/VS2022/Common7/Tools/VsDevCmd.bat" -arch=x64 -host_arch=x64\n@cl /nologo /EHsc /std:c++17 /W4 "{g / "capture.cpp"}" /Fe:"{g / "capture.exe"}" /Fo:"{g / "capture.obj"}" /link dbghelp.lib bcrypt.lib\n',encoding='utf-8')
        env=os.environ.copy()
        for key in list(env):
            if key.startswith('HERMES_ASSEMBLY_'):env.pop(key,None)
        for key in ['APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR']:
            p=g/key.lower();p.mkdir();env[key]=str(p)
        out,err,code=capture.compile_owned(r,['cmd.exe','/d','/c',str(build)],env,g,ev,report['processes'])
        if code:raise ValueError('capture build failed '+err)
        command=[str(g/'capture.exe'),sys.executable,str(Path(__file__).resolve()),str(scopepath),str(fixture)]
        report['command']=command;save()
        out,err,code=r.execute(command,env,g,ev,'observer-matrix',{'seconds':240,'bytes':1024**3,'min_free':1024**3},report['processes'])
        report.update(exit=code,api_calls=parse_api(out),rows=json.loads((g/'results.json').read_text(encoding='utf-8')))
        report['blocks']=[x for x in (out+'\n'+err).splitlines() if re.search(r'CAPTURE_BLOCK|SECOND_CHANCE|SCRIPT ERROR|^\s*ERROR:|Traceback',x)]
        for row in report['rows']:
            case=next(x for x in cases if x['id']==row['id']);path=case['observed'].replace('\\','/').lower()
            actual=[x for x in report['api_calls'] if x['api']=='CreateFileW' and x['path'].removeprefix('\\\\?\\').replace('\\','/').lower()==path and int(x['access'])&0x80000000
                    and int(x['pid'])==row['observer'].get('pid')
                    and ('tid' not in row['observer'] or int(x['tid'])==row['observer']['tid'])
                    and ('handle' not in row['observer'] or x['return_value']==row['observer']['handle'])]
            row['actual_read_opens']=[{k:x[k] for k in ['seq','pid','tid','share','access','return_value','failure_error','teb']} for x in actual]
            expected_share=3 if row['variant'] in {'archive_python','archive_fileaccess','ordinary_lock'} else 7
            row['observer_open_verified']=not actual if row['variant'] in {'none','tree_bytes','archive_sharedelete_afterexit'} else any(int(x['share'])==expected_share and x['failure_error'] is None for x in actual)
            if row['variant']=='archive_sharedelete_afterexit':
                if not all(x.get('exited') is True and x.get('active_owned_processes')==0 for x in report['processes']):raise ValueError('afterexit archive requires actual Job0')
                published=Path(case['target'])/'payload.json' if case['operation']=='rename' else Path(case['target'])
                declared_file(scope,published);native.safe(published)
                data=read_declared(scope,published,shared_reader({'r':r}));archive=g/'afterexit-archive'/case['id'];archive.parent.mkdir(exist_ok=True);archive.write_bytes(data)
                row['after_job0_archive']={'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'copy_readback':digest(archive)==row['fresh_after_sha256'],'job0_before_open':True}
                row['observer_content_ok']=row['after_job0_archive']['copy_readback']
            # Denials depend on observed WinAPI, not an expectation promoted to fact.
            row['operation_api']=[x for x in report['api_calls'] if x['api'] in {'MoveFileW','ReplaceFileW','SetFileInformationByHandle'} and (x['path'].removeprefix('\\\\?\\').replace('\\','/').lower() in {case['source'].replace('\\','/').lower(),case['target'].replace('\\','/').lower()})]
            row['actual_api_verified']=len(row['operation_api'])==1 and bool(row['operation_api'][0]['return_value'])==row['result']['ok']
        report['summary']=[]
        for variant in VARIANTS:
            for actorname in ['godot','winapi']:
                for op in ['rename','replace']:
                    rows=[x for x in report['rows'] if (x['variant'],x['actor'],x['operation'])==(variant,actorname,op)]
                    report['summary'].append({'variant':variant,'actor':actorname,'operation':op,'samples':len(rows),'success':sum(x['result']['ok'] for x in rows),'errors':[x['operation_api'][0]['failure_error'] if x['operation_api'] else 'no_publication_call' for x in rows]})
        report['source_drift']=[p for p,h in report['source_hashes'].items() if digest(p)!=h]
        report['frozen_drift']=[p for p,h in report['frozen_hashes'].items() if digest(g/p)!=h]
        report['passed']=code==0 and not report['blocks'] and len(report['rows'])==len(VARIANTS)*2*2*3 and all(x['content_ok'] and x['held_during_operation'] and x['observer_content_ok'] and not x['observer_errors'] and x['observer_open_verified'] and x['actual_api_verified'] for x in report['rows']) and not report['source_drift'] and not report['frozen_drift']
        for name in ['capture.cpp','scope.json']:shutil.copyfile(g/name,ev/name)
        shutil.copyfile(Path(__file__),ev/Path(__file__).name)
        report['artifact_hashes']={p.name:digest(p) for p in ev.iterdir() if p.is_file() and p.name!='report.json'}
        report['artifact_readback']=all(digest(ev/p)==h for p,h in report['artifact_hashes'].items())
        report['passed']=report['passed'] and report['artifact_readback']
    except Exception as exc:report['error']=repr(exc);report['passed']=False;raise
    finally:
        save()
        if all(x.get('exited') is True and x.get('active_owned_processes')==0 for x in report['processes']):
            report['cleanup_bytes']=r.tree_bytes(g);r.delete_owned(g,owner);report['generated_exists']=g.exists()
        else:report['cleanup_block']='owned Job0 missing'
        save();print(json.dumps({'owner':str(owner),'passed':report['passed'],'error':report.get('error'),'generated_exists':report.get('generated_exists'),'summary':report.get('summary')},ensure_ascii=False,indent=2),flush=True)
    return 0 if report['passed'] else 1

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--execute',action='store_true');p.add_argument('--actor',type=Path);a=p.parse_args()
    if sum([a.execute,a.actor is not None])!=1:p.error('one explicit mode required')
    if a.actor:actor(a.actor)
    else:raise SystemExit(execute())
