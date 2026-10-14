"""One real empty worker + one save. Strict RED is retained, not save/restore approval.
Only newtests are written in the repository. Frozen/runtime products stay in E:/scratch.
No runtime recovery/identity/ticket payload is read, hashed, printed or archived.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('isolation', REPO/'tools/run_isolated_godot_test.py')
isolation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(isolation)
TEST = 'newtests/save_restore_stage_observation_test'
ENGINE = Path('E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/generated/Godot.exe')
WATCHDOG = 360
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()


def prepare():
    token = uuid.uuid4().hex
    owner = Path('E:/scratch')/('isolated-'+token)
    generated, evidence = owner/'generated', owner/'evidence'
    project, runtime = generated/'project', generated/'runtime'
    for path in (project, runtime, evidence):
        path.mkdir(parents=True, exist_ok=False)
        isolation.physical_e(path)
    isolation.physical_e(ENGINE)
    if (REPO/'override.cfg').exists():
        raise ValueError('uncovered project override')
    files = set()
    for directory in ('scripts', 'data'):
        for p in (REPO/directory).rglob('*'):
            if p.is_file() and p.suffix in {'.gd', '.uid', '.json'}:
                isolation.no_links(p)
                files.add(p.relative_to(REPO).as_posix())
    files.update({'project.godot','assets/config/server.cfg', TEST+'.gd',TEST+'.tscn',
        'addons/fate_server_signals/fate_server_signals.gdextension',
        'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll',
        'addons/webrtc_native/webrtc_native.gdextension',
        'addons/webrtc_native/lib/libwebrtc_native.windows.template_debug.x86_64.dll',
        'addons/webrtc_native/lib/libwebrtc_native.windows.template_release.x86_64.dll'})
    # Literal source/resource dependencies, never historical output/runtime trees.
    queue = list(files)
    while queue:
        rel = queue.pop()
        p = REPO/rel
        if p.suffix not in {'.gd','.tscn','.tres'}:
            continue
        for found in re.findall(r'res://([^"\s\)]+)', p.read_text(encoding='utf-8-sig')):
            candidate = REPO/found
            if candidate.is_file() and found not in files:
                if any(part in isolation.EXCLUDED for part in Path(found).parts):
                    continue
                isolation.contained(candidate, REPO)
                files.add(found)
                queue.append(found)
    source_hashes = {}
    for rel in sorted(files):
        source = isolation.no_links(REPO/rel)
        target = project/rel
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(source,target)
        source_hashes[rel] = sha(source)
    config = (project/'project.godot').read_text(encoding='utf-8-sig')
    config = '\n'.join(line for line in config.splitlines() if not line.startswith((
        'run/main_scene=', 'run/main_scene.fate_server=', 'config/icon=',
        '_mcp_game_helper=', 'enabled=PackedStringArray(', 'version_control/')))+'\n'
    config = config.replace('renderer/rendering_method="mobile"','renderer/rendering_method="gl_compatibility"')
    (project/'project.godot').write_text(config,encoding='utf-8')
    (owner/'runtime-project.godot').write_text(config,encoding='utf-8')
    env = dict(os.environ)
    for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR'):
        path = runtime/key.lower()
        path.mkdir()
        env[key] = path.as_posix()
    (runtime/'localappdata/hermes/cache/scratch').mkdir(parents=True)
    env['FATE_TEST_SCRATCH_ROOT'] = runtime.as_posix()
    env.pop('FATE_TEST_STARTUP_OBSERVATION_SECONDS',None)
    diagnostic_startup = '--diagnostic-startup' in sys.argv[1:]
    if diagnostic_startup:
        env['FATE_TEST_STARTUP_OBSERVATION_SECONDS'] = '300'
    # Do not inherit diagnostic toggles from another parallel task.
    env.pop('FD_RECOVERY_DIAGNOSTICS',None)
    manifest = {'run_id':token,'owner':str(owner),'generated':str(generated),
        'project':str(project),'runtime':str(runtime),'engine':str(ENGINE),
        'engine_sha256':sha(ENGINE),'runner_sha256':sha(Path(__file__)),
        'source_sha256':source_hashes,'project_transform':'remove main scenes/icon/developer plugins; compatibility renderer; import-only cursor autoload omission',
        'watchdog_seconds':WATCHDOG,'diagnostic_startup_seconds':300 if diagnostic_startup else 30,'processes':[],'results':{},
        'scope':'observation_only','save_restore_passed':False,'retained':True}
    (owner/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    return owner, project, runtime, evidence, env, manifest, config


def execute(label, args, project, runtime, evidence, env, records):
    out, err = evidence/(label+'.stdout.log'), evidence/(label+'.stderr.log')
    job = isolation.OwnedJob()
    cmd = [str(ENGINE),'--headless','--audio-driver','Dummy','--fixed-fps','60','--path',project.as_posix(),*args]
    rec = {'label':label,'argv':cmd,'exited':False}
    records.append(rec)
    proc = None
    start = time.monotonic()
    timeout = False
    with out.open('wb') as stdout, err.open('wb') as stderr:
        try:
            proc = subprocess.Popen(cmd,env=env,cwd=project,stdout=stdout,stderr=stderr,creationflags=4)
            rec['pid'] = proc.pid
            if proc.pid in {17120,28100}:
                raise RuntimeError('protected PID collision')
            job.attach_resume(proc)
            try:
                code = proc.wait(timeout=WATCHDOG)
            except subprocess.TimeoutExpired:
                timeout = True
                job.stop()
                code = proc.wait(timeout=15)
            deadline = time.monotonic()+20
            while job.active() and time.monotonic()<deadline:
                time.sleep(0.02)
            active = job.active()
            rec.update(exit_code=code,active_owned_processes=active,exited=active==0,
                timeout=timeout,duration_seconds=round(time.monotonic()-start,3))
        finally:
            if proc is not None and proc.poll() is None:
                job.stop()
                proc.kill()
                proc.wait(timeout=15)
            if job.active():
                job.stop()
            job.close()
    job.wait_log_release([out,err])
    rec['log_handles_released'] = True
    rec['logs'] = [str(out),str(err)]
    rec['log_sha256'] = [sha(out),sha(err)]
    stdout,stderr = out.read_text(encoding='utf-8'),err.read_text(encoding='utf-8')
    errors = [line for line in (stdout+'\n'+stderr).splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',line)]
    # Never print raw error lines: they can contain paths, identities or content.
    result = {'exit':code,'engine_error_count':len(errors),'job0':active==0,'timeout':timeout}
    if label == 'test':
        result.update(isolation.analyze(stdout,stderr,code))
        lines = [line for line in stdout.splitlines() if line.startswith('TEST_CHAIN_STAGE ')]
        names = ['worker_start','worker_ready','save_request','save_receipt','worker_release','log_collection']
        expected = [(name,value) for name in names for value in (1,-1 if name=='save_receipt' else 0)]
        collected = []
        syntax_ok = True
        for line in lines:
            match = re.fullmatch(r'TEST_CHAIN_STAGE stage=([a-z_]+) result=(-1|0|1)',line)
            if not match:
                syntax_ok = False
            else:
                collected.append((match[1],int(match[2])))
        result['actual_boundary_sequence'] = collected
        result['boundary_stdout_contract'] = syntax_ok and collected == expected
        result['check_lines'] = [line for line in stdout.splitlines() if line.startswith('CHECK ')]
        result['check_count'] = len(result['check_lines'])
        # Kernel Job0 and released log handles precede any worker-log read/archive.
        if not result['job0']:
            raise RuntimeError('cannot archive live worker outputs')
        logs = list((runtime/'rooms').glob('*/engine.*.log'))
        result['worker_log_count'] = len(logs)
        if len(logs)==1:
            job.wait_log_release(logs)
            target = evidence/'worker-engine.log'
            shutil.copyfile(logs[0],target)
            worker_text = target.read_text(encoding='utf-8')
            result['worker_log'] = str(target)
            result['worker_engine_error_count'] = sum(bool(re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',line)) for line in worker_text.splitlines())
        safe_report = runtime/'observation-evidence.json'
        if safe_report.is_file():
            report = json.loads(safe_report.read_text(encoding='utf-8'))
            (evidence/'observation-evidence.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
            result['safe_report'] = str(evidence/'observation-evidence.json')
        result['passed'] = result.get('passed') is True and result['boundary_stdout_contract'] and len(logs)==1 and result.get('worker_engine_error_count')==0 and result['job0']
    else:
        result['passed'] = code==0 and not errors and result['job0'] and not timeout
    return result


def main():
    owner,project,runtime,evidence,env,manifest,config = prepare()
    print('MANIFEST='+str(owner/'manifest.json'),flush=True)
    code = 1
    try:
        # Cold texture import first; runtime restores the original business autoload.
        (project/'project.godot').write_text('\n'.join(line for line in config.splitlines() if not line.startswith('CursorReplace=')),encoding='utf-8')
        imported = execute('import',['--editor','--import'],project,runtime,evidence,env,manifest['processes'])
        manifest['results']['import'] = imported
        (project/'project.godot').write_text(config,encoding='utf-8')
        if imported['passed']:
            tested = execute('test',['--scene','res://'+TEST+'.tscn'],project,runtime,evidence,env,manifest['processes'])
            manifest['results']['test'] = tested
            code = 0 if tested['passed'] else 1
        manifest['source_unchanged'] = all(sha(REPO/rel)==digest for rel,digest in manifest['source_sha256'].items())
        if not manifest['source_unchanged']:
            code = 1
        manifest['passed'] = code==0
    except Exception as exc:
        # Exception text may contain sensitive paths; keep type only in safe summary.
        manifest['runner_exception_type'] = type(exc).__name__
        raise
    finally:
        (owner/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
        summary = {'manifest':str(owner/'manifest.json'),'results':manifest['results'],
                   'source_unchanged':manifest.get('source_unchanged'),'save_restore_passed':False}
        print(json.dumps(summary,ensure_ascii=False),flush=True)
    return code

if __name__ == '__main__':
    sys.exit(main())
