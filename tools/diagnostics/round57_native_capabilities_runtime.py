"""Same official engine, isolated candidate DLL; no production writes or retries.

Each invocation owns one fresh physical E root, non-killing Job and approved
temporary fixtures. Runtime, full cold import and owned-console scopes differ.
"""
from __future__ import annotations
import argparse
import ctypes
from ctypes import wintypes as w
import hashlib
import json
import msvcrt
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.diagnostics.project_extension_lifecycle_probe import (
    physical_e, child_env, digest, debugger_source, prepare_project, EXT, DLL, MINIMAL,
)
from tools.diagnostics.native_cold_import_debug import parse_debug_log

ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
ENGINE_SHA = 'ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424'
NEW_DLL = Path('E:/FateDiagnostics/round59-native-build-20261010-1/libfate_server_signals.windows.template_release.x86_64.dll')
NEW_SHA = '9c14b69f1ccd859b91658e3333ccfd55c51d5d6055ff3861a702bacc75480895'
BUILD_MANIFEST = NEW_DLL.parent / 'manifest.json'
OLD_RUNTIME_RECEIPT = Path('E:/FateDiagnostics/round57-native-runtime-20261010-2/result.json')
OLD_RUNTIME_RECEIPT_SHA = '0abeac44d23d6cc97a6f0c50bd19cdc3d7f6dba5a87522d1910df1393c7de8dc'


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


class Info(ctypes.Structure):
    _fields_ = [('attrs', w.DWORD), ('creation', w.FILETIME), ('access', w.FILETIME),
                ('write', w.FILETIME), ('volume', w.DWORD), ('high_size', w.DWORD),
                ('low_size', w.DWORD), ('links', w.DWORD), ('high_index', w.DWORD), ('low_index', w.DWORD)]


class Accounting(ctypes.Structure):
    _fields_ = [('user', ctypes.c_int64), ('kernel', ctypes.c_int64),
                ('period_user', ctypes.c_int64), ('period_kernel', ctypes.c_int64),
                ('faults', w.DWORD), ('total', w.DWORD), ('active', w.DWORD), ('terminated', w.DWORD)]


class Win:
    def __init__(self):
        self.k = ctypes.WinDLL('kernel32', use_last_error=True)
        for name, args, result in [
            ('OpenProcess', [w.DWORD, w.BOOL, w.DWORD], w.HANDLE),
            ('GetProcessTimes', [w.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p], w.BOOL),
            ('WaitForSingleObject', [w.HANDLE, w.DWORD], w.DWORD),
            ('GetExitCodeProcess', [w.HANDLE, ctypes.POINTER(w.DWORD)], w.BOOL),
            ('GetProcessHandleCount', [w.HANDLE, ctypes.POINTER(w.DWORD)], w.BOOL),
            ('CloseHandle', [w.HANDLE], w.BOOL),
            ('CreateEventW', [ctypes.c_void_p, w.BOOL, w.BOOL, w.LPCWSTR], w.HANDLE),
            ('SetEvent', [w.HANDLE], w.BOOL),
            ('CreateFileW', [w.LPCWSTR, w.DWORD, w.DWORD, ctypes.c_void_p, w.DWORD, w.DWORD, w.HANDLE], w.HANDLE),
            ('GetFileInformationByHandle', [w.HANDLE, ctypes.POINTER(Info)], w.BOOL),
            ('CreateSymbolicLinkW', [w.LPCWSTR, w.LPCWSTR, w.DWORD], w.BOOLEAN),
            ('CreateJobObjectW', [ctypes.c_void_p, w.LPCWSTR], w.HANDLE),
            ('AssignProcessToJobObject', [w.HANDLE, w.HANDLE], w.BOOL),
            ('QueryInformationJobObject', [w.HANDLE, ctypes.c_int, ctypes.c_void_p, w.DWORD, ctypes.c_void_p], w.BOOL),
        ]:
            f = getattr(self.k, name); f.argtypes = args; f.restype = result

    def creation(self, handle):
        c, e, k, u = (w.FILETIME() for _ in range(4))
        if not self.k.GetProcessTimes(handle, ctypes.byref(c), ctypes.byref(e), ctypes.byref(k), ctypes.byref(u)):
            raise ctypes.WinError(ctypes.get_last_error())
        return (c.dwHighDateTime << 32) | c.dwLowDateTime

    def process(self, pid, creation):
        h = self.k.OpenProcess(0x1000 | 0x100000, False, pid)
        if not h: raise ctypes.WinError(ctypes.get_last_error())
        if self.creation(h) != creation:
            self.k.CloseHandle(h); raise RuntimeError('PID/creation mismatch')
        return h

    def identity(self, path):
        h = self.k.CreateFileW(str(path), 0x80, 7, None, 3, 0x02000000 | 0x00200000, None)
        if h == ctypes.c_void_p(-1).value: raise ctypes.WinError(ctypes.get_last_error())
        try:
            info = Info()
            if not self.k.GetFileInformationByHandle(h, ctypes.byref(info)): raise ctypes.WinError(ctypes.get_last_error())
            # Godot JSON parser uses doubles: preserve full NTFS index as decimal text.
            return {'volume': str(info.volume), 'file_index': str((info.high_index << 32) | info.low_index)}
        finally: self.k.CloseHandle(h)


class Job:
    """Outer diagnostic lease deliberately has NO kill-on-close/termination API."""
    def __init__(self, win):
        self.win = win
        self.handle = win.k.CreateJobObjectW(None, None)
        if not self.handle: raise ctypes.WinError(ctypes.get_last_error())
        self.runs = []

    def spawn(self, command, cwd, env, stream, console=False):
        gate = "import subprocess,sys; assert input()=='GO'; sys.exit(subprocess.run(sys.argv[1:],creationflags=subprocess.CREATE_NO_WINDOW,stdout=sys.stdout,stderr=sys.stderr).returncode)"
        if console:
            gate = "import subprocess,sys; assert input()=='GO'; s=subprocess.STARTUPINFO(); s.dwFlags|=subprocess.STARTF_USESHOWWINDOW; s.wShowWindow=0; sys.exit(subprocess.run(sys.argv[1:],creationflags=subprocess.CREATE_NEW_CONSOLE,startupinfo=s,stdout=sys.stdout,stderr=sys.stderr).returncode)"
        # The gate never belongs to the keeper console: only the debugger/keeper
        # creates that console after it already inherits this exact Job.
        flags = subprocess.CREATE_NO_WINDOW
        startup = subprocess.STARTUPINFO(); startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow = 0
        p = subprocess.Popen([sys.executable, '-B', '-c', gate, *command], cwd=cwd, env=env,
                             stdin=subprocess.PIPE, stdout=stream, stderr=subprocess.STDOUT,
                             creationflags=flags, startupinfo=startup)
        if not self.win.k.AssignProcessToJobObject(self.handle, int(p._handle)):
            # No GO delivered: closing pipe lets the owned gate exit normally.
            p.stdin.close(); p.wait(timeout=10); raise ctypes.WinError(ctypes.get_last_error())
        p.stdin.write(b'GO\n'); p.stdin.flush(); p.stdin.close()
        return p

    def run(self, command, cwd, env, path, seconds=180, console=False):
        start = time.monotonic()
        with path.open('xb') as f:
            p = self.spawn(command, cwd, env, f, console)
            try: code = p.wait(timeout=seconds + 15)
            except subprocess.TimeoutExpired: code = None
        out = {'argv': command, 'gate_pid': p.pid, 'exit': code, 'timeout': code is None, 'elapsed_s': time.monotonic()-start, 'log': str(path)}
        self.runs.append(out)
        return out

    def observe(self):
        i = Accounting()
        if not self.win.k.QueryInformationJobObject(self.handle, 1, ctypes.byref(i), ctypes.sizeof(i), None):
            raise ctypes.WinError(ctypes.get_last_error())
        return {'active': i.active, 'total': i.total, 'terminated': i.terminated, 'kill_on_close': False}

    def close_zero(self):
        until = time.monotonic() + 12
        r = self.observe()
        while r['active'] and time.monotonic() < until:
            time.sleep(.02); r = self.observe()
        if r['active']: return {**r, 'handles_released': False}
        ok = bool(self.win.k.CloseHandle(self.handle)); self.handle = None
        return {**r, 'handles_released': ok}


def safe_debugger():
    source = debugger_source()
    # Remove all optional software-breakpoint mutation code from the readonly dependency.
    a = source.index('            for(DWORD64 rva:trace_rvas)')
    b = source.index('            module(pi.hProcess', a)
    source = source[:a] + source[b:]
    a = source.index('            if(ev.u.Exception.ExceptionRecord.ExceptionCode==EXCEPTION_BREAKPOINT &&\n               breakpoints.count')
    b = source.index('            if(ev.u.Exception.ExceptionRecord.ExceptionCode==EXCEPTION_BREAKPOINT && ev.u.Exception.dwFirstChance)', a)
    source = source[:a] + source[b:]
    source = source.replace('    PROCESS_INFORMATION pi{};', '''    SetErrorMode(SEM_FAILCRITICALERRORS|SEM_NOGPFAULTERRORBOX);
    DebugSetProcessKillOnExit(FALSE);
    SetConsoleCtrlHandler([](DWORD code)->BOOL{return code==CTRL_C_EVENT || code==CTRL_BREAK_EVENT;},TRUE);
    bool own_console=GetEnvironmentVariableW(L"R57_OWN_CONSOLE",nullptr,0)>0;
    std::printf("R57_KEEPER pid=%lu\\n",GetCurrentProcessId());std::fflush(stdout);
    PROCESS_INFORMATION pi{};''')
    source = source.replace('DEBUG_ONLY_THIS_PROCESS|CREATE_NO_WINDOW', 'DEBUG_ONLY_THIS_PROCESS|(own_console?0:CREATE_NO_WINDOW)')
    # A debugger watchdog may detach its owned engine, NEVER kill ready fixtures.
    source = source.replace('TerminateProcess(pi.hProcess,0xDEAD)', 'DebugActiveProcessStop(pi.dwProcessId)')
    source = source.replace('            if(timedout && WaitForSingleObject(pi.hProcess,0)==WAIT_OBJECT_0)break;', '            if(timedout)break;')
    source = source.replace('        std::fflush(stdout);\n        if(!ContinueDebugEvent', '        std::fflush(stdout);\n        if(timedout)break;\n        if(!ContinueDebugEvent')
    source = source.replace('    WaitForSingleObject(pi.hProcess,10000);SymCleanup(pi.hProcess);', '''    if(exited)WaitForSingleObject(pi.hProcess,10000);
    if(own_console && exited) {
        DWORD ids[32]{};DWORD n=GetConsoleProcessList(ids,32);
        std::printf("R57_KEEPER_RELEASE members=%lu self=%lu\\n",n,GetCurrentProcessId());
        if(n!=1 || ids[0]!=GetCurrentProcessId()){SymCleanup(pi.hProcess);return 8;}
    }
    SymCleanup(pi.hProcess);''')
    assert 'WriteProcessMemory(' not in source and 'TerminateProcess(' not in source
    return source


class Controller:
    def __init__(self, root, win, helper, env, job):
        self.root, self.win, self.helper, self.env, self.job = root, win, helper, env, job
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.loop, daemon=True)
        self.events, self.trees, self.cases, self.handles, self.counts, self.errors = [], {}, {}, [], {}, []
        self.senders = {}
        self.engine = None

    def event(self):
        name = 'Local\\FateRound57-' + uuid.uuid4().hex
        h = self.win.k.CreateEventW(None, True, False, name)
        if not h: raise ctypes.WinError(ctypes.get_last_error())
        self.events.append(h)
        return name, h

    def wait_json(self, path):
        until = time.monotonic() + 10
        while time.monotonic() < until:
            try: return json.loads(path.read_text(encoding='utf-8'))
            except (FileNotFoundError, json.JSONDecodeError): time.sleep(.02)
        raise RuntimeError('fixture readiness timeout: ' + str(path))

    def engine_handle(self, pid):
        if self.engine: return self.engine
        text = (self.root / 'debug.raw.log').read_text(encoding='utf-8', errors='replace')
        m = re.search(r'OWNED pid=(\d+) creation_filetime=(\d+)', text)
        if not m or int(m[1]) != pid: raise RuntimeError('engine not debugger registered')
        self.engine = self.win.process(pid, int(m[2])); self.handles.append(self.engine)
        return self.engine

    def dispatch(self, d):
        action = d['action']; self.engine_handle(int(d['engine_pid']))
        if action == 'count':
            count = w.DWORD()
            if not self.win.k.GetProcessHandleCount(self.engine, ctypes.byref(count)): raise ctypes.WinError(ctypes.get_last_error())
            self.counts[d['label']] = count.value
            return {'ok': True, 'handle_count': count.value, 'label': d['label']}
        if action == 'tree_prepare':
            directory = self.root / ('tree-' + d['mode']); directory.mkdir()
            gate, gh = self.event(); end, eh = self.event()
            self.trees[str(directory)] = {'mode': d['mode'], 'gate_handle': gh, 'end_handle': eh, 'processes': {}}
            return {'ok': True, 'directory': str(directory), 'gate': gate, 'end': end}
        if action.startswith('tree_'):
            directory = d['directory']; tree = self.trees[directory]
            if action == 'tree_ready':
                roles = ('root',) if self.trees[d['directory']]['mode'].startswith('solo') else ('root', 'child', 'grandchild')
                for role in roles:
                    info = self.wait_json(Path(directory) / (role + '.ready'))
                    if role == 'root' and info['pid'] != d['pid']: raise RuntimeError('root mismatch')
                    h = self.win.process(info['pid'], info['creation_time']); self.handles.append(h)
                    tree['processes'][role] = {**info, 'handle': h}
                return {'ok': True, 'registered': {k: {a:b for a,b in v.items() if a!='handle'} for k,v in tree['processes'].items()}}
            if action == 'tree_root_exit': self.win.k.SetEvent(tree['gate_handle']); return {'ok': True, 'explicit_root_event': True}
            if action == 'tree_finish':
                self.win.k.SetEvent(tree['end_handle'])
                if d.get('root'): self.win.k.SetEvent(tree['gate_handle'])
                return {'ok': True, 'explicit_owned_fixture_event': True}
            if action == 'tree_alive':
                roles = ['child', 'grandchild'] if d.get('only_descendants') else list(tree['processes'])
                states = {r: self.win.k.WaitForSingleObject(tree['processes'][r]['handle'], 0) for r in roles}
                return {'ok': all(v==258 for v in states.values()), 'states': states, 'saved': False, 'label': d['label']}
            if action == 'tree_exited':
                result = {}
                for role, info in tree['processes'].items():
                    state = self.win.k.WaitForSingleObject(info['handle'], 10000)
                    code = w.DWORD(); self.win.k.GetExitCodeProcess(info['handle'], ctypes.byref(code))
                    result[role] = {'wait': state, 'exit': code.value}
                return {'ok': all(v['wait']==0 for v in result.values()), 'natural_child_exit': True, 'results': result}
        if action == 'cleanup_prepare': return self.cleanup_prepare(d['kind'])
        if action == 'cleanup_readback':
            case = self.cases[d['case']]; target = case['target']; expected_delete = case['kind']=='correct'
            if case.get('lock'):
                self.win.k.SetEvent(case['lock_event']); case['lock'].wait(timeout=10)
            if expected_delete:
                ok = not target.exists() and bool(d['result'].get('ok'))
            else:
                ok = target.is_file() and digest(target)==case['original_sha'] and not bool(d['result'].get('ok'))
            return {'ok': ok, 'expected_deleted': expected_delete, 'independent_readback': str(target), 'exists': target.exists(), 'sha256': digest(target) if target.is_file() else None}
        if action == 'atomic_prepare':
            source = self.root/'atomic-source.tmp'; target = self.root/'atomic-target.tmp'
            source.write_bytes(b'round57-new'); target.write_bytes(b'round57-old')
            return {'ok': True, 'source': str(source), 'target': str(target), 'size': source.stat().st_size}
        if action == 'atomic_readback':
            target=self.root/'atomic-target.tmp'; source=self.root/'atomic-source.tmp'
            return {'ok': target.read_bytes()==b'round57-new' and not source.exists(), 'sha256': digest(target), 'source_absent': not source.exists()}
        if action == 'break_start':
            text = (self.root / 'debug.raw.log').read_text(encoding='utf-8', errors='replace')
            keeper = int(re.search(r'R57_KEEPER pid=(\d+)', text)[1])
            kh = self.win.k.OpenProcess(0x1000 | 0x100000, False, keeper)
            if not kh: raise ctypes.WinError(ctypes.get_last_error())
            try: kc = self.win.creation(kh)
            finally: self.win.k.CloseHandle(kh)
            ack, ah = self.event()
            path = self.root / ('sender-' + d['label'] + '.raw.log')
            stream = path.open('xb')
            cmd = [str(self.helper), '--send', str(keeper), str(d['engine_pid']), str(kc), str(self.win.creation(self.engine)), ack]
            proc = self.job.spawn(cmd, self.root, self.env, stream, console=False)
            self.senders[d['label']] = {'proc': proc, 'stream': stream, 'path': path, 'ack': ah, 'event': ack}
            return {'ok': True, 'sender_pid': proc.pid, 'ack_event': ack, 'label': d['label'], 'registered': {'keeper': [keeper, kc], 'engine': [d['engine_pid'], self.win.creation(self.engine)], 'sender': [proc.pid, self.win.creation(int(proc._handle))]}}
        if action == 'break_ack':
            sender = self.senders[d['label']]
            self.win.k.SetEvent(sender['ack'])
            return {'ok': True, 'event_acknowledged': True, 'label': d['label']}
        if action == 'break_finish':
            sender = self.senders.pop(d['label'])
            try: code = sender['proc'].wait(timeout=20)
            finally:
                sender['stream'].close()
            content = sender['path'].read_text(encoding='utf-8', errors='replace')
            ok = code == 0 and content.count('R57_CONSOLE count=3') == 2 and 'R57_SEND sent=1' in content and 'R57_EVENT_ACK' in content
            return {'ok': ok, 'run': {'argv': [str(self.helper), '--send', d['label']], 'gate_pid': sender['proc'].pid, 'exit': code, 'log': str(sender['path'])}, 'raw': content, 'enumeration_to_broadcast_toctou': True, 'real_event_ack_before_detach': 'R57_EVENT_ACK' in content}
        raise RuntimeError('unknown controller action ' + action)

    def cleanup_prepare(self, kind):
        directory = self.root / ('remove-' + kind); directory.mkdir()
        approved=directory/'approved'; approved.mkdir(); parent=approved/'ordinary'; parent.mkdir()
        target=parent/'owned-temporary.tmp'; target.write_bytes(b'round57-explicit-ordinary-temporary')
        root_id=self.win.identity(approved); parent_id=self.win.identity(parent); file_id=self.win.identity(target)
        sha=digest(target); size=target.stat().st_size
        case={'target':target,'original_sha':sha,'kind':kind}; self.cases[str(directory)]=case
        result={'ok':True,'case':str(directory),'root':str(approved),'file':str(target),'root_id':root_id,'parent_id':parent_id,'file_id':file_id,'size':size,'sha256':sha,'expected_stage':'deleted_absence_confirmed'}
        stages={'wrong_root':'approved_root_identity_changed','wrong_parent':'parent_identity_changed','wrong_file':'file_identity_changed','size':'size_changed','hash':'sha256_changed','locked':'exclusive_open','directory':'regular_single_link_required','hardlink':'regular_single_link_required','leaf_junction':'regular_single_link_required','ancestor_junction':'ancestor_not_plain_directory','ancestor_changed':'parent_identity_changed','root_changed':'approved_root_identity_changed','symlink':'regular_single_link_required','outside':'outside_approved_root','dotdot':'unsafe_path'}
        if kind!='correct': result['expected_stage']=stages[kind]
        if kind.startswith('wrong_'):
            key={'wrong_root':'root_id','wrong_parent':'parent_id','wrong_file':'file_id'}[kind]
            result[key]={**result[key], 'file_index':str(int(result[key]['file_index'])+1)}
        elif kind=='size': result['size']+=1
        elif kind=='hash': result['sha256']='0'*64
        elif kind=='locked':
            event,eh=self.event(); case['lock_event']=eh
            f=(directory/'lock.raw.log').open('xb'); case['lock_log']=f
            case['lock']=self.job.spawn([str(self.helper),'--lock',str(target),str(directory),event],directory,self.env,f)
            info=self.wait_json(directory/'lock.ready'); h=self.win.process(info['pid'],info['creation_time']); self.handles.append(h)
        elif kind=='directory':
            folder=parent/'occupied-directory'; folder.mkdir(); (folder/'protected.tmp').write_bytes(b'protected')
            result['file']=str(folder); result['file_id']=self.win.identity(folder)
        elif kind=='hardlink': os.link(target,parent/'second-link.tmp')
        elif kind in ('leaf_junction','ancestor_junction'):
            link=parent/'leaf-junction' if kind=='leaf_junction' else approved/'linked-parent'
            destination=directory/'junction-destination'; destination.mkdir()
            carried=destination/'owned-temporary.tmp'; carried.write_bytes(target.read_bytes())
            cmd=['cmd.exe','/d','/c','mklink','/J',str(link),str(destination)]
            r=self.job.run(cmd,directory,self.env,directory/'junction.raw.log',15)
            if r['exit']!=0: raise RuntimeError('junction fixture failed')
            if kind=='leaf_junction': result['file']=str(link); result['file_id']=self.win.identity(link)
            else:
                result['file']=str(link/'owned-temporary.tmp'); result['parent_id']=self.win.identity(destination); result['file_id']=self.win.identity(carried); case['target']=carried
        elif kind in ('ancestor_changed','root_changed'):
            old=parent if kind=='ancestor_changed' else approved
            relocated=directory/('prior-'+old.name); old.rename(relocated)
            if kind=='ancestor_changed':
                old.mkdir(); replacement=old/target.name
            else:
                old.mkdir(); (old/'ordinary').mkdir(); replacement=old/'ordinary'/target.name
            replacement.write_bytes(target.name.encode()+b'-replacement')
            case['target']=replacement; case['original_sha']=digest(replacement)
            result['file_id']=self.win.identity(replacement)
            result['size']=replacement.stat().st_size; result['sha256']=digest(replacement)
            if kind=='root_changed': result['parent_id']=self.win.identity(replacement.parent)
        elif kind=='symlink':
            link=parent/'leaf-symlink.tmp'
            if not self.win.k.CreateSymbolicLinkW(str(link),str(target),2):
                error=ctypes.get_last_error()
                if error==1314: return {'ok':True,'skip':True,'reason':'WinError1314: no symlink privilege; not claimed PASS'}
                raise ctypes.WinError(error)
            result['file']=str(link); result['file_id']=self.win.identity(link)
        elif kind=='outside': result['root']=str(approved/'not-parent')
        elif kind=='dotdot': result['file']=str(parent)+'\\..\\ordinary\\'+target.name
        save(directory/'producer-approved.json',{**result,'producer':'round57-owned-temporary-fixture','ordinary_temporary_only':True,'not_records_identity_archive':True})
        return result

    def loop(self):
        done=set()
        while not self.stop.is_set():
            for request in sorted(self.root.glob('rpc-*.request.json')):
                if request in done: continue
                try: d=json.loads(request.read_text(encoding='utf-8'))
                except json.JSONDecodeError: continue
                try: result=self.dispatch(d)
                except Exception as e:
                    result={'ok':False,'error':repr(e)}; self.errors.append({'request':str(request),'error':repr(e)})
                response=request.with_name(request.name.replace('.request.','.response.'))
                tmp=response.with_suffix('.writing'); save(tmp,result); tmp.rename(response)
                done.add(request)
            self.stop.wait(.01)

    def finish(self):
        self.stop.set(); self.thread.join(timeout=15)
        sender_waits = []
        for label, sender in list(self.senders.items()):
            # Never terminate a sender; a pending wait is allowed to expire naturally.
            wait = sender['proc'].wait(timeout=20)
            sender['stream'].close()
            sender_waits.append({'label': label, 'pid': sender['proc'].pid, 'wait': wait, 'log': str(sender['path'])})
        self.senders.clear()
        # Only this controller's explicitly registered events, never PID terminate.
        for h in self.events: self.win.k.SetEvent(h)
        waits=[]
        for directory,tree in self.trees.items():
            for role,info in tree['processes'].items():
                state=self.win.k.WaitForSingleObject(info['handle'],10000)
                waits.append({'directory':directory,'role':role,'pid':info['pid'],'creation_time':info['creation_time'],'wait':state})
        for case in self.cases.values():
            if case.get('lock'):
                case['lock'].wait(timeout=10); case['lock_log'].close()
        closed=[bool(self.win.k.CloseHandle(h)) for h in [*self.handles,*self.events]]
        return {'owned_pid_waits':waits,'sender_waits':sender_waits,'all_registered_exited':all(x['wait']==0 for x in waits),'controller_handles_closed':all(closed),'handle_counts':self.counts,'errors':self.errors,'thread_stopped':not self.thread.is_alive()}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--scope',choices=['runtime','cold','signals'],required=True)
    args=parser.parse_args()
    if os.name!='nt': raise RuntimeError('Windows only')
    root=physical_e(args.root,fresh=True); root.mkdir(parents=True)
    lock=open('E:/FateDiagnostics/round57-new-dll-runtime.lock','a+b'); lock.seek(0)
    if not lock.read(1): lock.write(b'0'); lock.flush()
    lock.seek(0); msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
    win=Win(); job=Job(win); env=child_env(root)
    source_inputs={str(p.relative_to(REPO)):digest(p) for p in [REPO/EXT,REPO/DLL,REPO/'addons/fate_server_signals/SConstruct',*sorted((REPO/'addons/fate_server_signals/src').glob('*'))] if p.is_file()}
    assert digest(ENGINE)==ENGINE_SHA and digest(NEW_DLL)==NEW_SHA and NEW_DLL.stat().st_size==452608
    old_receipt_before=digest(OLD_RUNTIME_RECEIPT)
    assert old_receipt_before == OLD_RUNTIME_RECEIPT_SHA
    build_manifest=json.loads(BUILD_MANIFEST.read_text(encoding='utf-8'))
    build_sources=build_manifest.get('sources', {})
    build_source_match=all(Path(path).is_file() and digest(Path(path)) == value for path, value in build_sources.items() if Path(path).suffix in ('.cpp', '.hpp'))
    assert build_manifest.get('laststage') == 'COMPLETE' and build_manifest.get('formal_unchanged') and build_manifest.get('frozen_inputs_unchanged')
    assert build_manifest.get('dll', {}).get('sha256') == NEW_SHA and build_source_match
    source_fingerprint=hashlib.sha256(json.dumps(source_inputs, sort_keys=True).encode()).hexdigest()
    manifest=json.loads(BUILD_MANIFEST.read_text(encoding='utf-8'))
    manifest['runtime_source_match']=build_source_match
    manifest['runtime_source_fingerprint']=source_fingerprint
    manifest['runtime_dll_sha256']=NEW_SHA
    save(root/'build-manifest-readback.json',manifest)
    save(root/'metadata.json',{'scope':args.scope,'engine':str(ENGINE),'engine_sha256':ENGINE_SHA,'dll':str(NEW_DLL),'dll_sha256':NEW_SHA,'source_inputs':source_inputs,'source_fingerprint':source_fingerprint,'source_to_dll_hashmatch':f'{source_fingerprint}->{NEW_SHA}','build_manifest':str(BUILD_MANIFEST),'build_source_match':build_source_match,'driver_sha256':digest(Path(__file__)),'fixture_sha256':digest(Path(__file__).with_name('round57_native_fixture.cpp')),'gd_sha256':digest(Path(__file__).with_name('round57_native_capabilities.gd')),'retry':False,'failure_must_be_false':True,'original_ctrl_self_exit_hex':'0xc000013a','step_budget_s':180,'source_readonly':True,'runtime_policy_not_automatic_cleanup':True})
    (root/'debugger.cpp').write_text(safe_debugger(),encoding='utf-8')
    shutil.copyfile(Path(__file__).with_name('round57_native_fixture.cpp'),root/'fixture.cpp')
    build=root/'build-diagnostics.cmd'
    build.write_text(f'@call "D:/VS2022/Common7/Tools/VsDevCmd.bat" -arch=x64 -host_arch=x64\n@cl /nologo /utf-8 /EHsc /std:c++17 /W4 "{root/"debugger.cpp"}" /Fe:"{root/"debugger.exe"}" /Fo:"{root/"debugger.obj"}" /link dbghelp.lib\n@if errorlevel 1 exit /b 1\n@cl /nologo /utf-8 /EHsc /std:c++17 /W4 /MT "{root/"fixture.cpp"}" /Fe:"{root/"fixture.exe"}" /Fo:"{root/"fixture.obj"}"\n',encoding='utf-8')
    r=job.run(['cmd.exe','/d','/c',str(build)],root,env,root/'build.raw.log',180)
    save(root/'build-result.json',r)
    if r['exit']!=0: raise RuntimeError('diagnostic build failed; no runtime attempted')
    if args.scope=='cold':
        project,inputs=prepare_project('C-formal-cold-freeze',root,REPO)
    else:
        project=root/'project'; project.mkdir(); (project/'project.godot').write_text(MINIMAL,encoding='utf-8')
        for rel in (EXT,DLL):
            dest=project/rel; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(REPO/rel,dest)
        inputs={'classification':'EXPLICIT_RUNTIME_LOADER_NO_EDITOR_NO_INHERITED_CACHE','files':{p.relative_to(project).as_posix():digest(p) for p in project.rglob('*') if p.is_file()}}
    shutil.copyfile(NEW_DLL,project/DLL)
    # Descriptor bytes stay identical; replace only its selected DLL in the owned freeze.
    inputs['files'][DLL.as_posix()]=digest(project/DLL)
    inputs['isolated_candidate_override']={'path':DLL.as_posix(),'source':str(NEW_DLL),'sha256':NEW_SHA}
    save(root/'candidate-input-manifest.json',inputs)
    assert not (project/'.godot').exists()
    tail=['--headless','--verbose','--rendering-method','gl_compatibility','--path',str(project)]
    controller=None
    if args.scope=='cold': tail+=['--editor','--import']
    else:
        gd=root/'capabilities.gd'; shutil.copyfile(Path(__file__).with_name('round57_native_capabilities.gd'),gd)
        tail+=['--script',str(gd),'--',str(root),str(root/'fixture.exe'),args.scope]
        controller=Controller(root,win,root/'fixture.exe',env,job); controller.thread.start()
    help_text=Path('E:/FateDiagnostics/round45-project-native-cause-20261010-1/help.log').read_text(encoding='utf-8',errors='replace')
    for flag in tail:
        if flag.startswith('--') and flag!='--' and flag not in help_text: raise RuntimeError('unsupported official CLI flag '+flag)
    if args.scope=='signals': env['R57_OWN_CONSOLE']='1'
    command=[str(root/'debugger.exe'),str(ENGINE),str(project),'180000',subprocess.list2cmdline(tail)]
    result=job.run(command,root,env,root/'debug.raw.log',180,console=args.scope=='signals')
    text=(root/'debug.raw.log').read_text(encoding='utf-8',errors='replace')
    parsed=parse_debug_log(text)
    errors=[line for line in text.splitlines() if 'ERROR:' in line or 'TIMEOUT ' in line or 'CREATE_ERROR' in line or 'CONTINUE_ERROR' in line]
    cleanup=controller.finish() if controller else {'not_applicable':True}
    functional=json.loads((root/'functional.json').read_text(encoding='utf-8')) if (root/'functional.json').is_file() else None
    unchanged=source_inputs=={rel:digest(REPO/rel) for rel in source_inputs} and digest(ENGINE)==ENGINE_SHA and digest(NEW_DLL)==NEW_SHA
    remaining=job.close_zero()
    old_receipt_unchanged=digest(OLD_RUNTIME_RECEIPT)==old_receipt_before
    ok=result['exit']==0 and parsed['child_exit_hex']=='0x00000000' and not parsed['second_chance'] and not errors and unchanged and build_source_match and old_receipt_unchanged and remaining['active']==0 and remaining['handles_released']
    if args.scope!='cold': ok=ok and functional is not None and bool(functional['ok']) and cleanup['all_registered_exited'] and cleanup['controller_handles_closed'] and not cleanup['errors']
    summary={'scope':args.scope,'ok':ok,'run':result,'native_events':parsed,'headless_errors':errors,'functional':functional,'owned_cleanup':cleanup,'remaining_job':remaining,'production_inputs_unchanged':unchanged,'build_source_match':build_source_match,'source_to_dll_hashmatch':f'{source_fingerprint}->{NEW_SHA}','old_failure_receipt_sha256':old_receipt_before,'old_failure_receipt_unchanged':old_receipt_unchanged,'original_ctrl_self_exit_hex':'0xc000013a','candidate_dll_loaded':NEW_DLL.name.lower() in text.lower(),'not_production_package':True,'no_automatic_cleanup_green':True,'failure_must_be_false':True,'first_failure_preserved':not ok,'cold_definition':'fresh project and redirected user caches; OS file cache not claimed cold'}
    save(root/'result.json',summary)
    print(json.dumps({'scope':args.scope,'ok':ok,'evidence':str(root),'engine_exit':parsed['child_exit_hex'],'errors':errors,'remaining_job':remaining,'failures':functional.get('failures') if functional else None},ensure_ascii=False))
    msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1); lock.close()
    return 0 if ok else 1


if __name__=='__main__': raise SystemExit(main())