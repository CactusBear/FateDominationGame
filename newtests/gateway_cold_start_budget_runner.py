"""Cold application-cache startup budget probe. No production/fixture edits.

Generated diagnostic subclass preserves the original run and close assertions;
only explicit deployment-config injection, finite observation budget and root
monotonic timing are added. Existing worker log stage lines are sampled through
Win32 FILE_SHARE_READ|WRITE|DELETE handles. No config/ticket/ready payload read.
"""
import ctypes
from ctypes import wintypes as w
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import threading
import time
import uuid

PROJECT = Path('E:/Projects/Godot/FateDominationGame-master')
ENGINE = Path('E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/generated/Godot.exe')
spec = importlib.util.spec_from_file_location('isolated_budget', PROJECT/'tools/run_isolated_godot_test.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
K = ctypes.WinDLL('kernel32', use_last_error=True)
K.CreateFileW.argtypes = [w.LPCWSTR,w.DWORD,w.DWORD,w.LPVOID,w.DWORD,w.DWORD,w.HANDLE]
K.CreateFileW.restype = w.HANDLE
K.ReadFile.argtypes = [w.HANDLE,w.LPVOID,w.DWORD,ctypes.POINTER(w.DWORD),w.LPVOID]
K.ReadFile.restype = w.BOOL
K.CloseHandle.argtypes = [w.HANDLE]
K.CloseHandle.restype = w.BOOL
K.GetSystemTimes.argtypes = [ctypes.POINTER(w.FILETIME)]*3
K.GetSystemTimes.restype = w.BOOL


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(owner, data):
    (owner/'manifest.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')


def shared_log(path):
    handle = K.CreateFileW(str(path),0x80000000,7,None,3,0x80,None)
    if handle == ctypes.c_void_p(-1).value:
        if ctypes.get_last_error() in (2,3): return b''
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        buf = ctypes.create_string_buffer(256*1024)
        count = w.DWORD()
        if not K.ReadFile(handle,buf,len(buf),ctypes.byref(count),None):
            raise ctypes.WinError(ctypes.get_last_error())
        if count.value == len(buf): raise ValueError('unexpectedly large whitelisted stage log')
        return buf.raw[:count.value]
    finally:
        K.CloseHandle(handle)


def cpu_ticks():
    fields = [w.FILETIME() for _ in range(3)]
    if not K.GetSystemTimes(*(ctypes.byref(x) for x in fields)):
        raise ctypes.WinError(ctypes.get_last_error())
    return [x.dwHighDateTime*2**32+x.dwLowDateTime for x in fields]


class Memory(ctypes.Structure):
    _fields_ = [('length',w.DWORD),('load',w.DWORD)]+[(x,ctypes.c_uint64) for x in ['total_phys','available_phys','total_page','available_page','total_virtual','available_virtual','available_extended']]


class ProcessEntry(ctypes.Structure):
    _fields_ = [('size',w.DWORD),('usage',w.DWORD),('pid',w.DWORD),('heap',ctypes.c_size_t),('module',w.DWORD),('threads',w.DWORD),('parent',w.DWORD),('priority',w.LONG),('flags',w.DWORD),('exe',w.WCHAR*260)]


def load_sample():
    memory = Memory(); memory.length = ctypes.sizeof(memory)
    if not K.GlobalMemoryStatusEx(ctypes.byref(memory)): raise ctypes.WinError(ctypes.get_last_error())
    K.CreateToolhelp32Snapshot.argtypes = [w.DWORD,w.DWORD]; K.CreateToolhelp32Snapshot.restype = w.HANDLE
    K.Process32FirstW.argtypes = [w.HANDLE,ctypes.POINTER(ProcessEntry)]
    K.Process32NextW.argtypes = [w.HANDLE,ctypes.POINTER(ProcessEntry)]
    handle = K.CreateToolhelp32Snapshot(2,0)
    if handle == ctypes.c_void_p(-1).value: raise ctypes.WinError(ctypes.get_last_error())
    counts = {}; total = 0
    try:
        entry = ProcessEntry(); entry.size = ctypes.sizeof(entry)
        ok = K.Process32FirstW(handle,ctypes.byref(entry))
        while ok:
            total += 1
            name = entry.exe.lower()
            if any(x in name for x in ['godot','python','node','claude','codex','hermes']):
                counts[name] = counts.get(name,0)+1
            ok = K.Process32NextW(handle,ctypes.byref(entry))
    finally: K.CloseHandle(handle)
    return {'memory_load_percent':memory.load,'available_physical_bytes':memory.available_phys,'total_physical_bytes':memory.total_phys,'process_count':total,'relevant_images':counts,'logical_cpus':os.cpu_count()}


def observe(fixture,evidence,stop):
    previous = time.perf_counter(); previous_cpu = cpu_ticks(); counts = {}; last_load = 0
    with (evidence/'stage-observation.jsonl').open('x',encoding='utf-8') as trace, (evidence/'machine-load.jsonl').open('x',encoding='utf-8') as loads:
        while True:
            now = time.perf_counter()
            for path in sorted((fixture/'worker-rooms').glob('*/engine.*.log')):
                lines = shared_log(path).decode('utf-8',errors='strict').splitlines()
                offset = counts.get(path,0)
                for index,line in enumerate(lines[offset:],offset+1):
                    match = re.fullmatch(r'SERVER_ROOM_STARTUP stage=([a-z_]+) result=(-1|0|1)',line)
                    if match or line.startswith('SERVER_ROOM_READY '):
                        event = {'log':path.name,'line':index,'observed_monotonic':time.perf_counter(),'previous_scan_monotonic':previous}
                        event.update({'stage':match[1],'result':int(match[2])} if match else {'ready_banner':True})
                        trace.write(json.dumps(event)+'\n'); trace.flush()
                counts[path] = len(lines)
            if now-last_load >= 1 or stop.is_set():
                ticks = cpu_ticks(); denom = (ticks[1]-previous_cpu[1])+(ticks[2]-previous_cpu[2])
                load = load_sample(); load['observed_monotonic'] = now
                load['cpu_busy_percent'] = None if not denom else 100*(1-(ticks[0]-previous_cpu[0])/denom)
                load['system_times_delta_100ns'] = [y-x for x,y in zip(previous_cpu,ticks)]
                loads.write(json.dumps(load)+'\n'); loads.flush()
                previous_cpu = ticks; last_load = now
            previous = time.perf_counter()
            if stop.wait(0.05):
                # One final scan after the owned job has exited.
                for path in sorted((fixture/'worker-rooms').glob('*/engine.*.log')):
                    lines = shared_log(path).decode('utf-8').splitlines()
                    for index,line in enumerate(lines[counts.get(path,0):],counts.get(path,0)+1):
                        match = re.fullmatch(r'SERVER_ROOM_STARTUP stage=([a-z_]+) result=(-1|0|1)',line)
                        if match or line.startswith('SERVER_ROOM_READY '):
                            event = {'log':path.name,'line':index,'observed_monotonic':time.perf_counter(),'previous_scan_monotonic':previous}
                            event.update({'stage':match[1],'result':int(match[2])} if match else {'ready_banner':True})
                            trace.write(json.dumps(event)+'\n')
                return


def main():
    phase = sys.argv[1]
    if phase == 'selftest':
        owner = Path('E:/scratch')/('budget-observer-selftest-'+uuid.uuid4().hex); owner.mkdir()
        log = owner/'stage.log'; log.write_text('SERVER_ROOM_STARTUP stage=cache_population result=1\n',encoding='utf-8')
        assert shared_log(log) == log.read_bytes()
        # Prove the observer's sharing permits concurrent atomic rename.
        handle = K.CreateFileW(str(log),0x80000000,7,None,3,0x80,None)
        try:
            os.replace(log,owner/'renamed.log')
            log.write_text('SERVER_ROOM_STARTUP stage=cache_population result=0\n',encoding='utf-8')
            assert shared_log(log).splitlines()[-1] == b'SERVER_ROOM_STARTUP stage=cache_population result=0'
        finally: K.CloseHandle(handle)
        print(json.dumps(load_sample())); print('SHARED_DELETE_OBSERVER_SELFTEST_OK'); return 0
    if phase == 'prepare':
        runner.physical_e(PROJECT); runner.physical_e(ENGINE)
        startup = float(sys.argv[2]); observation = startup+10
        if startup <= 30 or startup > 900: raise ValueError('diagnostic startup must be explicit and finite in (30,900]')
        if (PROJECT/'override.cfg').exists(): raise ValueError('unexpected project override')
        token = uuid.uuid4().hex; owner = Path('E:/scratch')/('isolated-'+token)
        generated = owner/'generated'; target = generated/'project'; target.mkdir(parents=True); (owner/'evidence').mkdir()
        manifest = {'run_id':token,'owner':str(owner),'generated':str(generated),'project':str(target),'engine':str(ENGINE),'engine_sha256':sha(ENGINE),'source_hashes':{},'processes':[],'results':{},'budgets':{'seconds':1200,'bytes':6*1024**3,'min_free':1024**3},'deployment':{'startup_seconds':startup,'observation_seconds':observation,'shared_cache':False},'cleanup':'retained_evidence'}
        save(owner,manifest)
        includes = ['project.godot','scripts','assets','data','addons','tests/gateway_relisten_acceptance_test.gd','tests/gateway_relisten_acceptance_test.tscn','tests/match_journal_test.gd']
        for rel in runner.source_files(PROJECT,includes):
            if rel.name.startswith('~') and rel.suffix == '.dll': continue
            source = PROJECT/rel; dest = target/rel; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(source,dest)
            manifest['source_hashes'][rel.as_posix()] = sha(dest)
            if sha(source) != sha(dest): raise ValueError('source changed while freezing: '+rel.as_posix())
        config = (target/'project.godot').read_text(encoding='utf-8')
        (target/'project.godot').write_text(config.replace('version_control/autoload_on_startup=true','version_control/autoload_on_startup=false'),encoding='utf-8')
        manifest['frozen_project_sha256'] = sha(target/'project.godot')
        original = (target/'tests/gateway_relisten_acceptance_test.gd').read_text(encoding='utf-8')
        body = original[original.index('func check_real_worker_close('):original.index('\nfunc run()')]
        old = '\tvar gateway = Gateway.new()\n'; assert body.count(old)==1
        body = body.replace(old,old+'''\tvar args = OS.get_cmdline_user_args()
\tcheck(args.size() == 2 and args[0] == "--config", "诊断部署入口显式配置")
\tif args.size() != 2: return
\tvar deployment = preload("res://scripts/net/server/server_bootstrap.gd").read_configuration(args[1])
\tcheck(deployment is Dictionary and deployment.has("startup_seconds"), "诊断启动期限必须显式声明")
\tif not deployment is Dictionary or not deployment.has("startup_seconds"): return
\tgateway.manager.startup_seconds = float(deployment.startup_seconds)
\tprint("COLD_BUDGET_DECLARED startup_seconds=", gateway.manager.startup_seconds)
''')
        old = '\tvar id:String = gateway.manager.create_room('
        assert body.count(old)==1
        body = body.replace(old,'\tvar started_msec:int = Time.get_ticks_msec()\n'+old)
        assert body.count('+40000')==1
        body = body.replace('+40000','+int((gateway.manager.startup_seconds+10.0)*1000.0)')
        old = '\trelisten_worker_observation(gateway.manager,id,"before_ready_check")'
        body = body.replace(old,old+'\n\tprint("COLD_BUDGET_TIMING ",JSON.stringify({"create_to_ready_observed_msec":Time.get_ticks_msec()-started_msec,"ready":gateway.manager.is_ready(id),"startup_seconds":gateway.manager.startup_seconds}))')
        diagnostic = target/'newtests'; diagnostic.mkdir()
        gd = diagnostic/'gateway_cold_start_budget_test.gd'
        gd.write_text('extends "res://tests/gateway_relisten_acceptance_test.gd"\n\n'+body,encoding='utf-8')
        scene = diagnostic/'gateway_cold_start_budget_test.tscn'
        scene.write_text('[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://newtests/gateway_cold_start_budget_test.gd" id="1"]\n\n[node name="ColdStartupBudget" type="Node"]\nscript = ExtResource("1")\n',encoding='utf-8')
        cfg = generated/'server.cfg'; cfg.write_text('[server]\nstartup_seconds='+str(startup)+'\n',encoding='utf-8')
        manifest['diagnostic_files'] = {str(x.relative_to(owner)):sha(x) for x in [gd,scene,cfg]}
        manifest['scene'] = 'res://newtests/gateway_cold_start_budget_test.tscn'
        save(owner,manifest); print('OWNER='+owner.as_posix()); return 0
    owner = runner.physical_e(sys.argv[2]); manifest = json.loads((owner/'manifest.json').read_text(encoding='utf-8'))
    if phase not in {'probe','import','run','run2'} or phase in manifest['results']: raise ValueError('invalid/repeated phase')
    target = Path(manifest['project']); generated = Path(manifest['generated']); evidence = owner/'evidence'
    if phase == 'run2':
        evidence = evidence/'run2'; evidence.mkdir()
        if not manifest['results'].get('run',{}).get('passed'): raise ValueError('second bounded sample requires completed first sample')
    if sha(ENGINE) != manifest['engine_sha256']: raise ValueError('engine drift')
    if sha(target/'project.godot') != manifest['frozen_project_sha256']: raise ValueError('project drift')
    for rel,digest in manifest['source_hashes'].items():
        if rel != 'project.godot' and sha(target/rel) != digest: raise ValueError('frozen input drift: '+rel)
    for rel,digest in manifest['diagnostic_files'].items():
        if sha(owner/rel) != digest: raise ValueError('diagnostic drift: '+rel)
    fixture = generated/phase; fixture.mkdir()
    env = {k:v for k,v in os.environ.items() if not k.startswith('FD_') and k != 'FATE_TEST_SCRATCH_ROOT'}
    for key,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','tmp'),('TMP','tmp'),('TMPDIR','tmp')]:
        path = fixture/sub; path.mkdir(exist_ok=True); env[key] = path.as_posix()
    env['FATE_TEST_SCRATCH_ROOT'] = fixture.as_posix()
    if phase == 'probe':
        probe = fixture/'probe'; probe.mkdir(); config = (target/'project.godot').read_text(encoding='utf-8')
        application = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)
        threading_cfg = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)
        text = 'config_version=5\n[application]\n'+re.sub(r'^run/main_scene=.*\n','',application[1],flags=re.M)
        if threading_cfg: text += '\n[threading]\n'+threading_cfg[1]
        (probe/'project.godot').write_text(text,encoding='utf-8'); (probe/'probe.gd').write_text(runner.PROBE_SCRIPT.replace('["--headless", "--path"','["--headless", "--fixed-fps", "60", "--path"'),encoding='utf-8')
        cmd = [str(ENGINE),'--headless','--fixed-fps','60','--path',probe.as_posix(),'--script','res://probe.gd','--',manifest['run_id'],'main',generated.as_posix()]
    else:
        cmd = [str(ENGINE),'--headless','--fixed-fps','60','--path',target.as_posix()]
        cmd += ['--editor','--import'] if phase == 'import' else ['--scene',manifest['scene'],'--','--config',(generated/'server.cfg').as_posix()]
    if phase.startswith('run') and not all(manifest['results'].get(x,{}).get('passed') for x in ['probe','import']): raise ValueError('probe/import prerequisite failed')
    stop = threading.Event(); thread_errors = []; thread = None
    if phase.startswith('run'):
        assert not (fixture/'worker-rooms').exists()
        manifest['cold_cache_before'] = {'worker_rooms_exists':False,'isolated_user_root_new':True,'os_cache_flushed':False}
        def observed():
            try: observe(fixture,evidence,stop)
            except BaseException as exc: thread_errors.append(type(exc).__name__+': '+str(exc))
        thread = threading.Thread(target=observed); thread.start()
    manifest['results'][phase] = {'status':'launch_registered'}; save(owner,manifest)
    try:
        out,err,code = runner.execute(cmd,env,generated,evidence,phase,manifest['budgets'],manifest['processes'])
        stop.set()
        if thread: thread.join(timeout=10)
        errors = [line for line in (out+'\n'+err).splitlines() if 'SCRIPT ERROR' in line or line.startswith('ERROR:')]
        result = {'exit':code,'engine_errors':errors,'observer_errors':thread_errors}
        if phase == 'probe':
            result['user_probes'] = runner.verify_probe(out,generated,manifest['run_id']); result['passed'] = code==0 and not errors
        elif phase == 'import': result['passed'] = code==0 and not errors
        else:
            result.update(runner.analyze(out,err,code)); result['passed'] &= not thread_errors
            result['root_timing'] = [json.loads(x[len('COLD_BUDGET_TIMING '):]) for x in out.splitlines() if x.startswith('COLD_BUDGET_TIMING ')]
            result['first_false'] = next(([i,x] for i,x in enumerate(out.splitlines(),1) if x.startswith('CHECK ') and x.endswith(' false')),None)
            result['worker_logs'] = []
            for i,path in enumerate(sorted((fixture/'worker-rooms').glob('*/engine.*.log'))):
                archive = evidence/('worker-'+str(i)+'.engine.log'); shutil.copy2(path,archive)
                text = archive.read_text(encoding='utf-8')
                sequence = [{'line':n,'stage':m[1],'result':int(m[2])} for n,line in enumerate(text.splitlines(),1) if (m:=re.fullmatch(r'SERVER_ROOM_STARTUP stage=([a-z_]+) result=(-1|0|1)',line))]
                result['worker_logs'].append({'archive':archive.name,'sha256':sha(archive),'sequence':sequence,'ready_banner':any(x.startswith('SERVER_ROOM_READY ') for x in text.splitlines()),'engine_errors':[x for x in text.splitlines() if 'SCRIPT ERROR' in x or x.startswith('ERROR:')]})
            events = [json.loads(x) for x in (evidence/'stage-observation.jsonl').read_text(encoding='utf-8').splitlines()]
            begins = [x for x in events if x.get('stage')=='cache_population' and x.get('result')==1]
            ends = [x for x in events if x.get('stage')=='cache_population' and x.get('result')==0]
            result['cache_population_observed_seconds'] = ends[0]['observed_monotonic']-begins[0]['observed_monotonic'] if len(begins)==len(ends)==1 else None
            if len(begins)==len(ends)==1:
                result['cache_population_log_visibility_interval_seconds'] = [ends[0]['previous_scan_monotonic']-begins[0]['observed_monotonic'],ends[0]['observed_monotonic']-begins[0]['previous_scan_monotonic']]
            result['cache_population_sampling_note'] = 'External log-visibility timing; not worker-internal call timing. Interval bounds sampling only; logger flush and OS scheduling delays are not separately measured.'
            loads = [json.loads(x) for x in (evidence/'machine-load.jsonl').read_text(encoding='utf-8').splitlines()]
            cpu = [x['cpu_busy_percent'] for x in loads if x['cpu_busy_percent'] is not None]
            result['load_summary'] = {'samples':len(loads),'cpu_busy_percent_mean':sum(cpu)/len(cpu),'cpu_busy_percent_max':max(cpu),'memory_load_percent_min':min(x['memory_load_percent'] for x in loads),'memory_load_percent_max':max(x['memory_load_percent'] for x in loads),'first':loads[0],'last':loads[-1]}
            result['passed'] &= len(result['worker_logs'])==1 and not any(x['engine_errors'] for x in result['worker_logs'])
        manifest['results'][phase] = result
        print(json.dumps(result,ensure_ascii=False))
        print('\n'.join(x for x in out.splitlines() if x.startswith(('COLD_BUDGET_','CHECK ','RESULT ','RELISTEN_WORKER ','RELISTEN_CLOSE '))))
    except BaseException as exc:
        manifest['results'][phase] = {'error':type(exc).__name__+': '+str(exc),'passed':False}; raise
    finally:
        stop.set()
        if thread: thread.join(timeout=10)
        manifest['current_source_drift_after_phase'] = [rel for rel,digest in manifest['source_hashes'].items() if not (PROJECT/rel).exists() or sha(PROJECT/rel)!=digest]
        save(owner,manifest); print('MANIFEST='+ (owner/'manifest.json').as_posix())
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
