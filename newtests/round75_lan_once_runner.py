"""Single-attempt LAN production-entry probe; no termination APIs are called.

prepare -> import -> record -> (only after record success) restore.
Two real Lobby sessions own distinct ENet connections in each client process;
production manager owns a separate authority engine. Identities are only opened
by production GDScript; this runner never reads identity or recovery files.
"""
import ctypes
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

PROJECT = Path('E:/Projects/Godot/FateDominationGame-master')
ENGINE_SOURCE = Path('E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/generated/Godot.exe')
TEST = 'newtests/round75_lan_once_test'
spec = importlib.util.spec_from_file_location('isolated', PROJECT/'tools/run_isolated_godot_test.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def keep_job_non_killing(job):
    # Clear KILL_ON_JOB_CLOSE before root assignment. Never use job.stop().
    class Basic(ctypes.Structure):
        _fields_ = [('process_time',ctypes.c_int64),('job_time',ctypes.c_int64),('flags',w.DWORD),
                    ('minimum',ctypes.c_size_t),('maximum',ctypes.c_size_t),('active',w.DWORD),
                    ('affinity',ctypes.c_size_t),('priority',w.DWORD),('scheduling',w.DWORD)]
    class Extended(ctypes.Structure):
        _fields_ = [('basic',Basic),('io',ctypes.c_uint64*6),('process_memory',ctypes.c_size_t),
                    ('job_memory',ctypes.c_size_t),('peak_process',ctypes.c_size_t),('peak_job',ctypes.c_size_t)]
    limits = Extended()
    if not job.kernel.SetInformationJobObject(job.handle,9,ctypes.byref(limits),ctypes.sizeof(limits)):
        raise ctypes.WinError(ctypes.get_last_error())


def main():
    phase = sys.argv[1]
    if phase not in {'prepare','import','record','restore'}:
        raise ValueError('unknown phase')
    if phase == 'prepare':
        helper.physical_e(PROJECT)
        helper.physical_e(ENGINE_SOURCE)
        owner = Path('E:/scratch')/('round75-lan-once-'+uuid.uuid4().hex)
        owner.mkdir()
        generated, evidence = owner/'generated', owner/'evidence'
        project = generated/'project'
        project.mkdir(parents=True)
        evidence.mkdir()
        includes = ['project.godot','scripts','assets','data','addons',TEST+'.gd',TEST+'.tscn',
                    'tests/net_port_fixture.gd','tests/round36_gateway_equivalence.gd','tests/helpers/recovery_equivalence.gd']
        files = helper.source_files(PROJECT,includes)
        hashes = {}
        for rel in files:
            if rel.name.startswith('~') and rel.suffix == '.dll':
                continue
            src, dst = PROJECT/rel, project/rel
            dst.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(src,dst)
            digest = sha(dst)
            if digest != sha(src):
                raise RuntimeError('source changed during freeze: '+rel.as_posix())
            hashes[rel.as_posix()] = digest
        cfg = project/'project.godot'
        original = cfg.read_text(encoding='utf-8')
        # Development editor integration only; no rule/runtime budget changes.
        cfg.write_text(original.replace('version_control/autoload_on_startup=true','version_control/autoload_on_startup=false'),encoding='utf-8',newline='\n')
        engine = generated/'Godot.exe'
        shutil.copy2(ENGINE_SOURCE,engine)
        record = {'owner':owner.as_posix(),'generated':generated.as_posix(),'project':project.as_posix(),
                  'engine':engine.as_posix(),'engine_source':ENGINE_SOURCE.as_posix(),'engine_sha256':sha(engine),
                  'frozen_project_sha256':sha(cfg),'source_hashes':hashes,'processes':[], 'results':{},
                  'scene':'res://'+TEST+'.tscn','protected_pids':[17120,28100],
                  'termination_policy':'no kill, no terminate, no KILL_ON_JOB_CLOSE; retain UNKNOWN',
                  'client_layout':'two production Lobby/ENet sessions in one parent engine, distinct worker engine',
                  'runtime':(generated/'runtime').as_posix()}
        save(owner/'manifest.json',record)
        print('OWNER='+owner.as_posix())
        return 0
    owner = helper.physical_e(sys.argv[2])
    manifest_path = owner/'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    generated, project, engine = [Path(manifest[k]) for k in ('generated','project','engine')]
    evidence = owner/'evidence'
    # Lock is created BEFORE spawn; interruptions cannot permit repeated stages.
    with (owner/(phase+'.attempt.lock')).open('x',encoding='utf-8') as f:
        f.write('single attempt reserved\n')
    if phase == 'record' and (manifest['results'].get('import',{}).get('exit') != 0 or manifest['results']['import'].get('errors')):
        raise RuntimeError('import prerequisite failed')
    if phase == 'restore' and manifest['results'].get('record',{}).get('passed') is not True:
        raise RuntimeError('first divergence: restore not attempted')
    if sha(engine) != manifest['engine_sha256'] or sha(project/'project.godot') != manifest['frozen_project_sha256']:
        raise RuntimeError('engine/config freeze drift')
    for rel,digest in manifest['source_hashes'].items():
        if rel != 'project.godot' and sha(project/rel) != digest:
            raise RuntimeError('freeze drift: '+rel)
    fixture = generated/('env-'+phase)
    fixture.mkdir()
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(('FD_','R75_','FATE_','ROUND')):
            env.pop(key)
    for key,folder in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','tmp'),('TMP','tmp'),('TMPDIR','tmp')]:
        directory = fixture/folder
        directory.mkdir(exist_ok=True)
        env[key] = directory.as_posix()
    env['FATE_TEST_SCRATCH_ROOT'] = (generated/'runtime').as_posix()
    env['R75_ONCE_RUNTIME_ROOT'] = (generated/'runtime').as_posix()
    env['R75_ONCE_EVIDENCE_ROOT'] = evidence.as_posix()
    env['R75_ONCE_CASE'] = phase
    command = [engine.as_posix(),'--headless','--fixed-fps','60','--path',project.as_posix()]
    command += ['--editor','--import'] if phase == 'import' else ['--scene','res://'+TEST+'.tscn']
    item = {'phase':phase,'command':command,'env_paths':{key:env[key] for key in ['APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR']},
            'exited':False,'kill_called':False,'stdout':(evidence/(phase+'.stdout.log')).as_posix(),
            'stderr':(evidence/(phase+'.stderr.log')).as_posix()}
    manifest['processes'].append(item)
    save(manifest_path,manifest)
    job = helper.OwnedJob()
    keep_job_non_killing(job)
    started = time.monotonic()
    last_stage = None
    last_active = None
    event_offset = 0
    sample_at = 0
    stop_requested = False
    with Path(item['stdout']).open('wb') as out, Path(item['stderr']).open('wb') as err, (evidence/(phase+'.job.jsonl')).open('a',encoding='utf-8') as telemetry:
        proc = subprocess.Popen(command,cwd=generated,env=env,stdout=out,stderr=err,creationflags=0x00000004)
        if proc.pid in (17120,28100):
            raise RuntimeError('unexpected protected PID collision; root remains suspended')
        item['pid'] = proc.pid
        job.attach_resume(proc)
        print('COMMAND='+subprocess.list2cmdline(command),flush=True)
        print('PID='+str(proc.pid),flush=True)
        while True:
            elapsed = time.monotonic()-started
            active = job.active()
            stages = []
            events_file = evidence/'stages.jsonl'
            if phase != 'import' and events_file.exists():
                with events_file.open('r',encoding='utf-8') as f:
                    f.seek(event_offset)
                    while True:
                        pos = f.tell()
                        line = f.readline()
                        if not line or not line.endswith('\n'):
                            event_offset = pos
                            break
                        event_offset = f.tell()
                        event = json.loads(line)
                        if event['pid'] == proc.pid and event['kind'] in {'enter','failure','finished'}:
                            stages.append({'stage':event['stage'],'kind':event['kind'],'client_ticks_msec':event['ticks_msec']})
                            last_stage = event['stage']
            if stages or active != last_active or elapsed >= sample_at:
                sample = {'elapsed_seconds':round(elapsed,3),'root_pid':proc.pid,'root_exit':proc.poll(),
                          'active_owned_processes':active,'stage':last_stage,'events':stages}
                telemetry.write(json.dumps(sample,ensure_ascii=False)+'\n'); telemetry.flush()
                save(manifest_path,manifest)
                print('JOB '+json.dumps(sample,ensure_ascii=False),flush=True)
                last_active = active
                sample_at = elapsed+10
            if proc.poll() is not None and active == 0:
                break
            # Explicit runner observation ceiling, never modifies product deadlines.
            # Only request the fixture's normal-close path; retain unresolved jobs.
            if phase != 'import' and elapsed > 1200 and not stop_requested:
                (evidence/'stop-normal.request').write_text('normal close requested; no force stop\n',encoding='utf-8')
                stop_requested = True
                item['normal_stop_requested'] = True
                save(manifest_path,manifest)
            time.sleep(0.1)
        item.update(exit_code=proc.wait(),duration_seconds=round(time.monotonic()-started,3),active_owned_processes=job.active(),exited=True)
    job.wait_log_release([Path(item['stdout']),Path(item['stderr'])])
    job.close()
    stdout = Path(item['stdout']).read_text(encoding='utf-8')
    stderr = Path(item['stderr']).read_text(encoding='utf-8')
    errors = [line for line in (stdout+'\n'+stderr).splitlines() if 'SCRIPT ERROR' in line or line.startswith('ERROR:')]
    result = {'exit':item['exit_code'],'errors':errors,'active_owned_processes':item['active_owned_processes']}
    if phase != 'import':
        result.update(helper.analyze(stdout,stderr,item['exit_code']))
        final = evidence/'final.json'
        if final.is_file():
            # public-only file emitted by this fixture, never recovery/identity state.
            observed = json.loads(final.read_text(encoding='utf-8'))
            result['first_stage'] = observed.get('first_stage')
            result['failures'] = observed.get('failures')
            shutil.copy2(final,evidence/(phase+'.final.json'))
    manifest['results'][phase] = result
    save(manifest_path,manifest)
    print(json.dumps(result,ensure_ascii=False))
    for line in stdout.splitlines():
        if line.startswith(('CHECK ','RESULT ')):
            print(line)
    print('MANIFEST='+manifest_path.as_posix())
    return 0 if (phase == 'import' and result['exit'] == 0 and not errors) or result.get('passed') is True else 1


if __name__ == '__main__':
    raise SystemExit(main())
