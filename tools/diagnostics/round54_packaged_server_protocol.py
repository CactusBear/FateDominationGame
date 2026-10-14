"""Real packaged gateway; source-editor client fixture, no production mutation.
Uses round53's audited bounded Win32 Job runner, not a new native job capability.
Never terminate READY/unsaved/unknown server processes or retry first failures.
"""
import argparse
import ctypes
from ctypes import wintypes as w
import json
import os
from pathlib import Path
import subprocess
import time
import zipfile
from round53_exported_runtime import Runner, Job, safe, sha, inventory, MANIFEST, REPO

EDITOR = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
SCENE = 'res://tools/diagnostics/round54_authenticated_client.tscn'


def source_files():
    roots = ['scripts','assets','addons','data']
    result = {}
    for root in roots:
        for p in (REPO/root).rglob('*'):
            if p.is_file(): result[p.relative_to(REPO).as_posix()] = sha(p)
    for name in ['project.godot','hermesWarning.txt']:
        result[name] = sha(REPO/name)
    return result


def kernel():
    k = ctypes.WinDLL('kernel32',use_last_error=True)
    for name,args,out in [
        ('OpenProcess',[w.DWORD,w.BOOL,w.DWORD],w.HANDLE),
        ('CloseHandle',[w.HANDLE],w.BOOL),
        ('DuplicateHandle',[w.HANDLE,w.HANDLE,w.HANDLE,ctypes.POINTER(w.HANDLE),w.DWORD,w.BOOL,w.DWORD],w.BOOL),
        ('GetProcessId',[w.HANDLE],w.DWORD),
        ('GetExitCodeProcess',[w.HANDLE,ctypes.POINTER(w.DWORD)],w.BOOL),
        ('CreateToolhelp32Snapshot',[w.DWORD,w.DWORD],w.HANDLE)]:
        f = getattr(k,name);f.argtypes=args;f.restype=out
    return k


def modules(pid):
    k=kernel()
    class Module(ctypes.Structure):
        _fields_=[('size',w.DWORD),('module_id',w.DWORD),('pid',w.DWORD),('global_use',w.DWORD),('process_use',w.DWORD),('base',w.LPVOID),('base_size',w.DWORD),('handle',w.HANDLE),('name',w.WCHAR*256),('path',w.WCHAR*260)]
    for name in ['Module32FirstW','Module32NextW']:
        f=getattr(k,name);f.argtypes=[w.HANDLE,ctypes.POINTER(Module)];f.restype=w.BOOL
    h=k.CreateToolhelp32Snapshot(8|16,pid)
    if h==ctypes.c_void_p(-1).value: return {'ok':False,'error':ctypes.get_last_error()}
    result=[]; m=Module();m.size=ctypes.sizeof(m)
    valid=k.Module32FirstW(h,ctypes.byref(m))
    while valid:
        result.append({'name':m.name,'path':m.path,'sha256':sha(m.path)})
        valid=k.Module32NextW(h,ctypes.byref(m))
    k.CloseHandle(h)
    return {'ok':True,'pid':pid,'modules':result}


def process_handles(owner_handle,owner_pid,target_pid):
    """Read actual Windows process handles in the still-live gateway."""
    class Entry(ctypes.Structure):
        _fields_=[('object',w.LPVOID),('pid',ctypes.c_size_t),('handle',ctypes.c_size_t),('access',w.ULONG),('backtrace',w.USHORT),('type',w.USHORT),('attributes',w.ULONG),('reserved',w.ULONG)]
    k=kernel();own_probe=k.OpenProcess(0x1000,False,os.getpid())
    if not own_probe:raise ctypes.WinError(ctypes.get_last_error())
    n=ctypes.WinDLL('ntdll').NtQuerySystemInformation
    n.argtypes=[w.ULONG,w.LPVOID,w.ULONG,ctypes.POINTER(w.ULONG)];n.restype=ctypes.c_long
    size=1024*1024
    while True:
        b=ctypes.create_string_buffer(size);needed=w.ULONG();status=n(64,b,size,ctypes.byref(needed))
        if status==0: break
        if status & 0xffffffff != 0xc0000004: return {'ok':False,'ntstatus':hex(status & 0xffffffff)}
        size=max(size*2,needed.value+65536)
        if size>128*1024*1024: raise RuntimeError('system handle table exceeds diagnostic bound')
    count=ctypes.c_size_t.from_buffer(b).value
    offset=ctypes.sizeof(ctypes.c_size_t)*2
    if offset+count*ctypes.sizeof(Entry)>size: raise RuntimeError('invalid handle table bounds')
    process_type=None
    for i in range(count):
        e=Entry.from_buffer(b,offset+i*ctypes.sizeof(Entry))
        if e.pid==os.getpid() and e.handle==int(own_probe):process_type=int(e.type);break
    k.CloseHandle(own_probe)
    if process_type is None:raise RuntimeError('cannot independently identify Process handle object type')
    handles=[];failed=0
    for i in range(count):
        e=Entry.from_buffer(b,offset+i*ctypes.sizeof(Entry))
        if e.pid != owner_pid or e.type != process_type: continue
        duplicate=w.HANDLE()
        if not k.DuplicateHandle(owner_handle,w.HANDLE(e.handle),w.HANDLE(-1),ctypes.byref(duplicate),0,False,2):
            failed+=1;continue
        actual=k.GetProcessId(duplicate)
        if actual==target_pid: handles.append({'handle':int(e.handle),'granted_access':int(e.access),'object_type_index':int(e.type)})
        k.CloseHandle(duplicate)
    return {'ok':failed==0,'owner_pid':owner_pid,'target_pid':target_pid,'matching_process_handles':handles,'duplicate_failures':failed,'scope':'gateway handle table, not ClassDB method enumeration'}


class ProtocolRunner(Runner):
    def __init__(self,root):
        self.root=safe(root); approved=safe('E:/Caches/Hermes/cache/scratch')
        if self.root==approved or not self.root.is_relative_to(approved): raise ValueError('private E scratch required')
        self.root.mkdir(parents=True,exist_ok=False)
        self.mpath=self.root/'actualruntime.json'
        self.parent=json.loads(MANIFEST.read_text(encoding='utf-8'))
        self.state={'owner':'round54-packaged-server-protocol','root':self.root.as_posix(),'parent_manifest':MANIFEST.as_posix(),'parent_manifest_sha256':sha(MANIFEST),'runs':[],'verdict':'NOT_COMPLETE','limitations':['source-editor client fixture, not release client GUI','full match save/restore and multi-machine not tested','old pack has no new native status actor; ClassDB/full methods and runtime manager cfg getter unverified','external test Job is not new C++ Job capability']}
        self.live=[];self.source_before=source_files()
        self.state['source_before']=self.source_before
        self.state['fixture_sources']={name:sha(REPO/'tools/diagnostics'/name) for name in ['round54_authenticated_client.gd','round54_authenticated_client.tscn','round54_packaged_server_protocol.py']}
        self.state['editor']={'path':EDITOR.as_posix(),'sha256':sha(EDITOR)}
        self.state['round53_runtime_read']={'path':'E:/Caches/Hermes/cache/scratch/round53-exported-runtime-sa3/runtime.json','sha256':sha('E:/Caches/Hermes/cache/scratch/round53-exported-runtime-sa3/runtime.json')}
        self.save();self.verify('initial')

    def command(self,role,args):
        if role=='fixture':
            return [str(EDITOR),'--headless','--audio-driver','Dummy','--rendering-method','gl_compatibility','--path',REPO.as_posix(),*args]
        return super().command(role,args)

    def console(self,label,cfg,command):
        if any(x['label']==label for x in self.state['runs']):label += '-readback-'+str(len(self.state['runs']))
        r,text=self.run(label,'server',['--','--server-console',cfg['console_dir']],user_label='server-own',stdin=command+'\nexit\n')
        receipts=[json.loads(line.split(' ',1)[1]) for line in text.splitlines() if line.startswith('CONSOLE_RESULT ')]
        self.state.setdefault('console_receipts',{})[label]={'command':command,'responses':receipts};self.save()
        if r['exit_code']!=0 or r['errors'] or len(receipts)!=1:raise RuntimeError('console engine/receipt failed: '+label)
        return receipts[0]

    def poll_until(self,check,start,reason):
        while time.monotonic()-start<180:
            result=check()
            if result:return result
            time.sleep(.03)
        self.state['preserved_unsaved_or_unknown_process']=True;self.save()
        raise RuntimeError(reason+'; original 180s budget, preserve live process')

    def execute(self):
        cfg,path=self.config('protocol','json')
        # Explicit approved deployment defaults; client omits simulation fields.
        cfg['identity_registry']='user://round54_own_registry.json'
        path.write_text(json.dumps(cfg,ensure_ascii=False),encoding='utf-8')
        self.state['deployments']['protocol'].update(configuration=cfg,config_sha256=sha(path));self.save()
        gateway=self.start('gateway','server',['--','--server-gateway','--config',path.as_posix()],user_label='server-own')
        self.wait_ready(gateway,cfg)
        self.state['gateway_module_presence']=modules(gateway[0].pid);self.save()
        output=self.root/'client-public-receipt.json'
        r,text=self.run('authenticated-client-scene','fixture',['--fixed-fps','60','--scene',SCENE,'--',str(cfg['port']),output.as_posix()],user_label='client-own')
        receipt=json.loads(output.read_text()) if output.exists() else None
        self.state['authenticated_client']=receipt;self.save()
        if r['exit_code']!=0 or r['errors'] or not receipt or not receipt.get('ok') or not receipt.get('authenticated'):
            self.state['verdict']='FIRST_SETTINGS_FAILURE_STOPPED_NO_RETRY'
            self.capture_failure(cfg);self.save()
            raise RuntimeError('first real authenticated settings attempt failed; no budget/retry/sleep extension')
        user=safe(receipt['user_root'])
        if not user.is_relative_to(self.root/'users'/'client-own') or receipt['pid']!=r['pid']:raise RuntimeError('actual own E client identity root mismatch')
        self.close_existing(gateway,cfg,receipt)

    def close_existing(self,gateway,cfg,receipt):
        room_id=receipt['room_id'];room_dir=safe(Path(cfg['storage_root'])/room_id)
        ready=json.loads((room_dir/'ready.json').read_text())
        conf=json.loads((room_dir/'config.json').read_text())
        self.state['room_ready']=ready
        self.state['worker_config_public']={k:conf[k] for k in ['id','port','instance_id','authority_host_mode','data_root','settings'] if k in conf}
        self.state['worker_config_sha256']=sha(room_dir/'config.json')
        pid=int(ready['pid'])
        if ready.get('id')!=room_id or ready.get('ok') is not True or pid<=0:raise RuntimeError('worker READY binding mismatch')
        self.state['worker_module_presence']=modules(pid)
        k=kernel();worker=k.OpenProcess(0x100000|0x1000,False,pid)
        if not worker:raise ctypes.WinError(ctypes.get_last_error())
        self.state['gateway_process_handles_before_close']=process_handles(int(gateway[0]._handle),gateway[0].pid,pid);self.save()
        before=self.state['gateway_process_handles_before_close']
        if not before['ok'] or not before['matching_process_handles']:raise RuntimeError('no observable original gateway worker handle')
        rooms=self.console('room-ready',cfg,'rooms')
        if not rooms.get('ok') or not any(x['id']==room_id and x['ready'] and x['pid']==pid for x in rooms['result']):raise RuntimeError('manager current READY mismatch')
        clients=self.console('clients-after-fixture-close',cfg,'list')
        if not clients.get('ok') or clients['result']!=[]:raise RuntimeError('lobby not empty after fixture disconnect')
        close=self.console('room-close',cfg,'room '+room_id+' close')
        if close.get('ok') is not True:raise RuntimeError('formal close rejected')
        request_id=close['result']['request_id']
        response_path=room_dir/'control'/(request_id+'.response.json')
        response=self.poll_until(lambda:json.loads(response_path.read_text()) if response_path.exists() else None,gateway[5],'no final close response')
        request_path=room_dir/'control'/(request_id+'.request.json')
        request=json.loads(request_path.read_text()) if request_path.exists() else None
        self.state['close_request']=request;self.state['close_response']=response;self.save()
        for key,value in [('room',room_id),('pid',pid),('instance',ready['instance']),('authority_host_mode','dedicated'),('request_id',request_id)]:
            if response.get(key)!=value:raise RuntimeError('final close binding mismatch: '+key)
        result=response.get('result',{})
        if response.get('ok') is not True or result.get('closing') is not True or result.get('saved') is not False or result.get('room_state_saved') is not True:raise RuntimeError('not exact empty lobby state save close receipt')
        def exited():
            code=w.DWORD()
            if not k.GetExitCodeProcess(worker,ctypes.byref(code)):raise ctypes.WinError(ctypes.get_last_error())
            return {'exit_code':code.value} if code.value!=259 else None
        self.state['worker_exit']=self.poll_until(exited,gateway[5],'worker no normal exit')
        k.CloseHandle(worker)
        def released():
            if gateway[0].poll() is not None:raise RuntimeError('gateway exited before handle release observation')
            proof=process_handles(int(gateway[0]._handle),gateway[0].pid,pid)
            return proof if proof['ok'] and not proof['matching_process_handles'] else None
        self.state['gateway_process_handles_after_close']=self.poll_until(released,gateway[5],'original worker handle still present')
        final=self.console('room-result',cfg,'room '+room_id+' result '+request_id)
        if any(final.get(key)!=response.get(key) for key in response):raise RuntimeError('public console final response readback mismatch')
        self.state['worker_release_public_rooms']=self.console('rooms-after-release',cfg,'rooms')
        self.state['match_save']=False
        stop=self.console('gateway-stop',cfg,'stop')
        if not stop.get('ok'):raise RuntimeError('formal gateway stop rejected')
        if stop.get('result',{}).get('failures'):
            self.state['verdict']='BLOCKED_GATEWAY_STOP_AFTER_SAVED_LOBBY_NATIVE_RELEASE'
            self.state['gateway_stop_terminal_cause']=stop['result']['failures']
            self.state['preserved_gateway_pid']=gateway[0].pid
            self.save()
            raise RuntimeError('formal stop final failure; no wait/budget extension/retry/kill')
        gr,gt=self.finish(gateway)
        if gr['exit_code']!=0 or gr['errors'] or gr['active_owned_processes']!=0 or self.state['worker_exit']['exit_code']!=0:raise RuntimeError('normal exit/Job accounting failed')
        self.state['verdict']='SERVER_PROTOCOL_GREEN'

    def capture_failure(self,cfg):
        observations=[]
        root=Path(cfg['storage_root'])
        if root.exists():
            for directory in root.iterdir():
                if not directory.is_dir():continue
                obj={'directory':directory.as_posix(),'files':[p.relative_to(directory).as_posix() for p in directory.rglob('*') if p.is_file() and not any(x in p.name.lower() for x in ['identity','registry','private'])]}
                for name in ['config.json','ready.json','startup-progress.json']:
                    p=directory/name
                    if p.exists():
                        doc=json.loads(p.read_text());obj[name]={k:doc[k] for k in ['id','pid','port','instance','instance_id','authority_host_mode','settings','stage','error','ok'] if k in doc};obj[name+'_sha256']=sha(p)
                observations.append(obj)
        self.state['first_settings_failure_observations']=observations

    def archive(self):
        self.verify('final')
        self.state['final_diagnostic_sources']={name:sha(REPO/'tools/diagnostics'/name) for name in ['round54_authenticated_client.gd','round54_authenticated_client.tscn','round54_packaged_server_protocol.py']}
        frozen=Path(self.parent['roles']['server']['project'])/'scripts/net/server/server_shutdown.gd'
        self.state['frozen_stop_consumer']={'path':frozen.as_posix(),'sha256':sha(frozen),'reason':'start() only recognizes shutdown-local _closed; prior console close manager binding is not adopted before checking a released native handle'}
        after=source_files()
        self.state['source_after_differences']={'added':sorted(after.keys()-self.source_before.keys()),'removed':sorted(self.source_before.keys()-after.keys()),'changed':[k for k in self.source_before if k in after and self.source_before[k]!=after[k]]}
        if any(self.state['source_after_differences'].values()):self.state['source_concurrency']='CHANGED_BY_OTHER_OWNER_OR_UNKNOWN; no source immutability claim'
        else:self.state['source_concurrency']='READ_ONLY_SOURCE_UNCHANGED'
        self.save()
        files=[self.mpath,*sorted((self.root/'logs').glob('*')),*sorted((self.root/'deployments').rglob('engine.*.log'))]
        public=self.root/'client-public-receipt.json'
        if public.exists():files.append(public)
        archive=self.root/'public-evidence.zip'
        members={p.relative_to(self.root).as_posix():p for p in files}
        for name in self.state['final_diagnostic_sources']:members['sources/'+name]=REPO/'tools/diagnostics'/name
        manifest={name:sha(path) for name,path in members.items()}
        with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as z:
            for name,path in members.items():z.write(path,name)
        import hashlib
        with zipfile.ZipFile(archive) as z:
            if z.testzip() is not None or {n:hashlib.sha256(z.read(n)).hexdigest() for n in z.namelist()}!=manifest:raise RuntimeError('archive readback failed')
        self.state['archive']={'path':archive.as_posix(),'sha256':sha(archive),'files':manifest,'excludes':'identities, registry, recovery stores; no deletion authorized or performed'};self.save()


def finalize_preworker_negative(root):
    r=ProtocolRunner.__new__(ProtocolRunner);r.root=safe(root);r.mpath=r.root/'actualruntime.json'
    r.state=json.loads(r.mpath.read_text());r.parent=json.loads(MANIFEST.read_text(encoding='utf-8'))
    r.live=[];r.source_before=r.state['source_before']
    if r.state['verdict']!='FIRST_SETTINGS_FAILURE_STOPPED_NO_RETRY':raise RuntimeError('not failed initial client schema scope')
    cfg=r.state['deployments']['protocol']['configuration']
    gateway=next(x for x in r.state['runs'] if x['label']=='gateway')
    k=kernel();h=k.OpenProcess(0x100000|0x1000,False,gateway['pid'])
    if not h:raise ctypes.WinError(ctypes.get_last_error())
    rooms=r.console('preworker-negative-rooms',cfg,'rooms')
    root=Path(cfg['storage_root'])
    if rooms!={'ok':True,'result':[]} or (root.exists() and any(root.iterdir())):raise RuntimeError('not empty; preserve unknown server')
    stop=r.console('preworker-negative-stop',cfg,'stop')
    if not stop.get('ok'):raise RuntimeError('empty server stop rejected')
    def exited():
        value=w.DWORD()
        if not k.GetExitCodeProcess(h,ctypes.byref(value)):raise ctypes.WinError(ctypes.get_last_error())
        return {'exit_code':value.value} if value.value!=259 else None
    proof=r.poll_until(exited,time.monotonic(),'empty server no exit after formal stop')
    k.CloseHandle(h)
    if proof['exit_code']!=0:raise RuntimeError('empty gateway nonzero exit')
    gateway.update(exited=True,exit_code=0,exit_hex='0x00000000',post_runner_exact_pid_exit_observation=proof,active_owned_processes=None,job_accounting='original runner already returned; do not infer active0',stdout_sha256=sha(gateway['stdout']),stderr_sha256=sha(gateway['stderr']))
    r.state['verdict']='PREWORKER_SCHEMA_NEGATIVE_NO_WORKER_LAUNCHED'
    r.state['first_cause_exact']='SERVER_ROOM_CREATE_FAILED: 人数配置必须显式提供整数; malformed client settings {}, no worker config/READY/staging created'
    r.save();r.archive()
    print(json.dumps({'verdict':r.state['verdict'],'gateway_pid':gateway['pid'],'exit_code':proof['exit_code'],'runtime':r.mpath.as_posix()},ensure_ascii=False))
    return 0


def resume_observation(root):
    r=ProtocolRunner.__new__(ProtocolRunner);r.root=safe(root);r.mpath=r.root/'actualruntime.json'
    r.state=json.loads(r.mpath.read_text());r.parent=json.loads(MANIFEST.read_text(encoding='utf-8'))
    r.live=[];r.source_before=r.state['source_before']
    if r.state.get('authenticated_client',{}).get('ok') is not True or r.state.get('close_response'):raise RuntimeError('not an unclosed settings-success observation scope')
    record=next(x for x in r.state['runs'] if x['label']=='gateway')
    k=kernel()
    class ObservedRoot:
        def __init__(self,pid):
            self.pid=pid;self._handle=k.OpenProcess(0x1fffff,False,pid)
            if not self._handle:raise ctypes.WinError(ctypes.get_last_error())
        def poll(self):
            code=w.DWORD()
            if not k.GetExitCodeProcess(self._handle,ctypes.byref(code)):raise ctypes.WinError(ctypes.get_last_error())
            return None if code.value==259 else code.value
        def wait(self,timeout):
            start=time.monotonic()
            while time.monotonic()-start<timeout:
                value=self.poll()
                if value is not None:return value
                time.sleep(.03)
            raise TimeoutError('exact gateway observer wait')
    process=ObservedRoot(record['pid']);job=Job()
    if not job.k.AssignProcessToJobObject(job.handle,process._handle):raise ctypes.WinError(ctypes.get_last_error())
    worker=k.OpenProcess(0x1fffff,False,r.state['room_ready']['pid'])
    if not worker:raise ctypes.WinError(ctypes.get_last_error())
    if not job.k.AssignProcessToJobObject(job.handle,worker):raise ctypes.WinError(ctypes.get_last_error())
    k.CloseHandle(worker)
    out=Path(record['stdout']).open('ab');err=Path(record['stderr']).open('ab')
    record['observation_resumed_same_pids_no_restart']=True
    record['resumed_diagnostic_job']='actual private Win32 Job assigned existing gateway and original worker; not new native production Job capability'
    r.state['diagnostic_observer_correction']='original Process handle was already found; 101 non-Process handle duplication failures were an over-strict diagnostic check. Restrict to independently observed Process object type, no worker or client retry.'
    gateway=(process,job,out,err,record,time.monotonic());r.live.append(gateway);r.save()
    try:r.close_existing(gateway,r.state['deployments']['protocol']['configuration'],r.state['authenticated_client'])
    except Exception as e:
        r.state.setdefault('failures',[]).append({'phase':'same-instance-close-observer','first_cause':str(e),'no_retry':True});r.save();raise
    finally:
        r.archive();k.CloseHandle(process._handle)
    print(json.dumps({'verdict':r.state['verdict'],'gateway_pid':record['pid'],'worker_pid':r.state['room_ready']['pid'],'runtime':r.mpath.as_posix()},ensure_ascii=False))
    return 0


def audit_final(root):
    r=ProtocolRunner.__new__(ProtocolRunner);r.root=safe(root);r.mpath=r.root/'actualruntime.json'
    r.state=json.loads(r.mpath.read_text());r.parent=json.loads(MANIFEST.read_text(encoding='utf-8'))
    r.live=[];r.source_before=r.state['source_before']
    record=next(x for x in r.state['runs'] if x['label']=='gateway')
    stop=r.state['console_receipts']['gateway-stop']['responses'][0]
    text=Path(record['stdout']).read_text(encoding='utf-8')
    if not stop.get('result',{}).get('failures') or 'SERVER_STOP_FAILED' not in text:raise RuntimeError('no raw formal stop failure')
    r.state['verdict']='BLOCKED_GATEWAY_STOP_AFTER_SAVED_LOBBY_NATIVE_RELEASE'
    r.state['gateway_stop_terminal_cause']=stop['result']['failures']
    r.state['preserved_gateway_pid']=record['pid']
    k=kernel();h=k.OpenProcess(0x1000,False,record['pid'])
    if not h:raise ctypes.WinError(ctypes.get_last_error())
    value=w.DWORD()
    if not k.GetExitCodeProcess(h,ctypes.byref(value)):raise ctypes.WinError(ctypes.get_last_error())
    k.CloseHandle(h)
    record.update(final_live_readback={'pid':record['pid'],'still_active':value.value==259,'native_exit_code':None if value.value==259 else value.value},stdout_sha256=sha(record['stdout']),stderr_sha256=sha(record['stderr']),preserved_unsaved_or_unknown_process=value.value==259)
    r.state['not_claimed']=['gateway normal stop exit0','Job active0 for preserved live gateway','full ClassDB methods or manager runtime config getter','match save','release client GUI or multi-machine']
    r.archive()
    print(json.dumps({'verdict':r.state['verdict'],'gateway':record['final_live_readback'],'worker_exit':r.state['worker_exit'],'handle_before':len(r.state['gateway_process_handles_before_close']['matching_process_handles']),'handle_after':len(r.state['gateway_process_handles_after_close']['matching_process_handles']),'archive':r.state['archive']['sha256'],'runtime':r.mpath.as_posix()},ensure_ascii=False))
    return 0


def main():
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--finalize-preworker-negative',action='store_true');p.add_argument('--resume-observation',action='store_true');p.add_argument('--audit-final',action='store_true');args=p.parse_args()
    if args.audit_final:return audit_final(args.root)
    if args.finalize_preworker_negative:return finalize_preworker_negative(args.root)
    if args.resume_observation:return resume_observation(args.root)
    r=ProtocolRunner(args.root);code=0
    try:r.execute()
    except Exception as e:
        r.state.setdefault('failures',[]).append({'first_cause':str(e),'no_retry':True});r.save();code=1
    finally:r.archive()
    print(json.dumps({'verdict':r.state['verdict'],'exit':code,'runtime':r.mpath.as_posix(),'failures':r.state.get('failures',[])},ensure_ascii=False))
    return code

if __name__=='__main__':raise SystemExit(main())
