"""Bounded exported-client launcher identity evidence; no secret payload parsing."""
import ctypes as c
from ctypes import wintypes as w
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path('E:/Caches/Hermes/cache/scratch/round71-human-test-candidate-validation-v3')
SPEC = importlib.util.spec_from_file_location('gate', ROOT/'tools/run_isolated_godot_test.py')
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)
K = c.WinDLL('kernel32', use_last_error=True)
U = c.WinDLL('user32', use_last_error=True)
K.OpenProcess.argtypes = [w.DWORD,w.BOOL,w.DWORD]; K.OpenProcess.restype = w.HANDLE
K.ReadProcessMemory.argtypes = [w.HANDLE,w.LPCVOID,w.LPVOID,c.c_size_t,c.POINTER(c.c_size_t)]
K.ReadProcessMemory.restype = w.BOOL
K.CloseHandle.argtypes = [w.HANDLE]
K.GetExitCodeProcess.argtypes = [w.HANDLE,c.POINTER(w.DWORD)]
U.GetWindowThreadProcessId.argtypes = [w.HWND,c.POINTER(w.DWORD)]
U.PostMessageW.argtypes = [w.HWND,w.UINT,w.WPARAM,w.LPARAM]
U.IsWindowVisible.argtypes = [w.HWND]
U.GetWindowTextW.argtypes = [w.HWND,w.LPWSTR,c.c_int]


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        while data := f.read(1024*1024): h.update(data)
    return h.hexdigest()


def selected_env(pid):
    """Read only APPDATA/LOCALAPPDATA values from x64 process environment."""
    h = K.OpenProcess(0x410,False,pid)
    if not h: raise c.WinError(c.get_last_error())
    def mem(address,size):
        buf = c.create_string_buffer(size); used = c.c_size_t()
        if not K.ReadProcessMemory(h,address,buf,size,c.byref(used)): raise c.WinError(c.get_last_error())
        return buf.raw[:used.value]
    try:
        class PBI(c.Structure):
            _fields_ = [('reserved',c.c_void_p),('peb',c.c_void_p),('rest',c.c_void_p*4)]
        info = PBI(); n = w.ULONG()
        query = c.WinDLL('ntdll').NtQueryInformationProcess
        query.argtypes = [w.HANDLE,w.ULONG,w.LPVOID,w.ULONG,w.LPVOID]
        if query(h,0,c.byref(info),c.sizeof(info),c.byref(n)) != 0: raise RuntimeError('PEB query failed')
        params = int.from_bytes(mem(info.peb+0x20,8),'little')
        block = int.from_bytes(mem(params+0x80,8),'little')
        result = {}; raw = b''
        for offset in range(0,262144,512):
            raw += mem(block+offset,512)
            text = raw.decode('utf-16-le',errors='replace')
            if '\0\0' in text:
                for item in text.split('\0'):
                    key,sep,value = item.partition('=')
                    if sep and key.upper() in ('APPDATA','LOCALAPPDATA'): result[key.upper()] = value
                return result
        raise RuntimeError('environment terminator absent')
    finally: K.CloseHandle(h)


def job_pids(job):
    # JOBOBJECT_BASIC_PROCESS_ID_LIST: two DWORDs then ULONG_PTRs.
    buf = c.create_string_buffer(8+8*64)
    if not job.kernel.QueryInformationJobObject(job.handle,3,buf,len(buf),None): raise c.WinError(c.get_last_error())
    count = int.from_bytes(buf.raw[4:8],'little')
    return [int.from_bytes(buf.raw[8+i*8:16+i*8],'little') for i in range(count)]


def windows(pids):
    rows = []; callback_type = c.WINFUNCTYPE(w.BOOL,w.HWND,w.LPARAM)
    @callback_type
    def cb(hwnd,param):
        pid = w.DWORD(); U.GetWindowThreadProcessId(hwnd,c.byref(pid))
        if pid.value in pids and U.IsWindowVisible(hwnd):
            title = c.create_unicode_buffer(512); U.GetWindowTextW(hwnd,title,512)
            if title.value: rows.append({'pid':pid.value,'hwnd':int(hwnd),'title':title.value})
        return True
    U.EnumWindows(cb,0)
    return rows


def identities(scope):
    rows = {}
    for role in ('host','guest'):
        base = scope/'package/test-users'/role
        found = []
        # Enumerate only generated sandbox net_identity; never configkeys/savedkeys.
        for directory,dirs,names in os.walk(base):
            dirs[:] = [x for x in dirs if x.lower() not in ('savedkeys','configkeys')]
            if Path(directory).name == 'net_identity':
                files = [{'name':n,'sha256':digest(Path(directory)/n)} for n in sorted(names) if (Path(directory)/n).is_file()]
                found.append({'directory':str(Path(directory)), 'files':files, 'count':len(files)})
                dirs[:] = []
        rows[role] = found
    return rows


def run():
    scope = Path('E:/Caches/Hermes/cache/scratch')/('round71-same-machine-identity-'+uuid.uuid4().hex)
    scope.mkdir(); GATE.physical_e(scope)
    package = scope/'package'; package.mkdir()
    shutil.copytree(SOURCE/'client',package/'client')
    evidence = scope/'evidence'; evidence.mkdir()
    manifest = []
    for p in sorted((SOURCE/'client').rglob('*')):
        GATE.no_links(p)
        if p.is_file():
            rel = p.relative_to(SOURCE)
            assert not any(x.lower() in ('savedkeys','configkeys','net_identity') for x in rel.parts)
            sha = digest(p); assert sha == digest(package/rel)
            manifest.append({'path':rel.as_posix(),'sha256':sha})
    record = {'source':str(SOURCE),'scope':str(scope),'old_artifact':True,'nonfinal':True,'artifact_kind':'preexisting candidate-validation-v3; not final release','watchdog_seconds':180,'client_manifest':manifest,'launches':[],'snapshots':[],'actions':[]}
    live = []; handles = {}
    def save():
        record['current_windows'] = windows([pid for row in live for pid in job_pids(row['job'])])
        (scope/'status.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
    def launch(role):
        index = len(record['launches'])+1
        base = package/'test-users'/role
        env = dict(os.environ)
        for key,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','tmp'),('TMP','tmp'),('TMPDIR','tmp')]:
            path = base/sub; path.mkdir(parents=True,exist_ok=True); env[key] = str(path)
        log = evidence/f'{index}-{role}.engine.log'
        command = [os.environ.get('COMSPEC','C:/Windows/System32/cmd.exe'),'/d','/s','/c',f'call client\\START-CLIENT.cmd --log-file "{log}"']
        stdout = (evidence/f'{index}-{role}.stdout.log').open('wb'); stderr = (evidence/f'{index}-{role}.stderr.log').open('wb')
        proc = subprocess.Popen(command,cwd=package,env=env,stdout=stdout,stderr=stderr,creationflags=4)
        job = GATE.OwnedJob(); assert proc.pid != 28100; job.attach_resume(proc)
        row = {'index':index,'role':role,'command':command,'cwd':str(package),'launcher_pid':proc.pid,'expected_environment':{key:env[key] for key in ('APPDATA','LOCALAPPDATA')},'processes':{},'timeout':False,'normal_close_requested':False,'engine_log':str(log)}
        record['launches'].append(row)
        live.append({'record':row,'proc':proc,'job':job,'start':time.monotonic(),'streams':[stdout,stderr]})
        save()
    launch('host')
    print('SCOPE '+str(scope),flush=True)
    finish = False
    try:
        while live or not finish:
            for runtime in list(live):
                row = runtime['record']; pids = job_pids(runtime['job'])
                for pid in pids:
                    assert pid != 28100
                    if str(pid) not in row['processes']:
                        h = K.OpenProcess(0x101000,False,pid)
                        if h: handles[pid] = h
                        try: actual = selected_env(pid)
                        except Exception as exc: actual = {'read_error':str(exc)}
                        row['processes'][str(pid)] = {'environment':actual,'environment_matches':actual == row['expected_environment']}
                if runtime['proc'].poll() is not None and not pids:
                    row['launcher_exit_code'] = runtime['proc'].returncode
                    row['Job0'] = runtime['job'].active() == 0
                    for pid, data in row['processes'].items():
                        code = w.DWORD()
                        if int(pid) in handles and K.GetExitCodeProcess(handles[int(pid)],c.byref(code)): data['exit_code'] = code.value
                    runtime['job'].close()
                    for stream in runtime['streams']: stream.close()
                    live.remove(runtime)
                elif time.monotonic()-runtime['start'] >= 180:
                    row['timeout'] = True; row['Job0_before_forced_cleanup'] = runtime['job'].active() == 0
                    runtime['job'].stop()
            control = scope/'control.json'
            if control.exists():
                data = json.loads(control.read_text(encoding='utf-8')); control.unlink()
                action = data['action']; record['actions'].append(data)
                if action == 'launch': launch(data['role'])
                elif action == 'snapshot': record['snapshots'].append({'label':data['label'],'identities':identities(scope),'live_launches':[x['record']['index'] for x in live]})
                elif action == 'close':
                    for runtime in live:
                        if runtime['record']['role'] == data['role']:
                            runtime['record']['normal_close_requested'] = True
                            for win in windows(job_pids(runtime['job'])):
                                if 'Fate' in win['title']: U.PostMessageW(win['hwnd'],0x10,0,0)
                elif action == 'finish': finish = True
            save(); time.sleep(.2)
    finally:
        for runtime in live:
            runtime['record']['finally_forced_cleanup'] = True
            runtime['job'].stop(); runtime['proc'].wait(timeout=15)
            runtime['record']['Job0_after_forced_cleanup'] = runtime['job'].active() == 0
            runtime['job'].close()
            for stream in runtime['streams']: stream.close()
        for h in handles.values(): K.CloseHandle(h)
        record['final_identities'] = identities(scope)
        record['logs'] = []
        for path in sorted(evidence.glob('*.log')):
            # Engine-only logs from this sandbox; never inspect identity/config files.
            text = path.read_text(encoding='utf-8',errors='replace')
            lines = text.splitlines()
            record['logs'].append({'path':str(path),'line_count':len(lines),'script_error_count':sum('SCRIPT ERROR' in x for x in lines),'key_lines':[{'line':i,'text':x} for i,x in enumerate(lines,1) if 'SCRIPT ERROR' in x or 'ERROR:' in x or x.startswith('Godot Engine') or x.startswith('OpenGL') or x.startswith('Vulkan')]})
        record['source_manifest_unchanged'] = all(digest(SOURCE/x['path']) == x['sha256'] for x in manifest)
        record['finished'] = True
        save()
        (evidence/'result.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps({'finished':True,'scope':str(scope),'launches':len(record['launches'])}),flush=True)

if __name__ == '__main__': run()
