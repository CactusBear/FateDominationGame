"""Round66: frozen real Lobby/RoomControl; only owned E fixtures and Job."""
import ctypes
from ctypes import wintypes
import hashlib
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
sys.path.insert(0, str(REPO / 'tools'))
from run_isolated_godot_test import OwnedJob, physical_e, no_links, analyze
ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
SUITE = sys.argv[1] if len(sys.argv) > 1 else 'recovery_save_observation_test'
COUNT = '--count-branches' in sys.argv
SCOPE = Path('E:/scratch') / ('round66-save-observation-' + uuid.uuid4().hex)
SCOPE.mkdir(parents=True)
physical_e(SCOPE)
PROJECT, EVIDENCE, FIXTURES = (SCOPE / x for x in ('project', 'evidence', 'fixtures'))
for p in (PROJECT, EVIDENCE, FIXTURES): p.mkdir()
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
# Source-only allowlist. No cache, archive, recovery, identity or runtime sources.
files = set()
for directory in ['scripts', 'data']:
    for p in (REPO / directory).rglob('*'):
        if p.is_file() and p.suffix in {'.gd', '.uid', '.json'}:
            files.add(p.relative_to(REPO).as_posix())
for name in ['project.godot', 'assets/config/server.cfg', 'addons/fate_server_signals/fate_server_signals.gdextension', 'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll', 'newtests/recovery_save_observation_test.gd', 'newtests/recovery_save_observation_test.tscn']:
    files.add(name)
if SUITE != 'recovery_save_observation_test':
    files.update({'tests/' + SUITE + '.gd', 'tests/' + SUITE + '.tscn'})
# Follow literal res dependencies from selected source files, never a runtime tree.
queue = list(files)
while queue:
    name = queue.pop()
    p = REPO / name
    if p.suffix not in {'.gd', '.tscn', '.tres'}: continue
    for found in re.findall(r'res://([^"\s\)]+)', p.read_text(encoding='utf-8-sig')):
        candidate = REPO / found
        if candidate.is_file() and found not in files and not found.startswith(('test/', 'reports/', 'runtime_reports/')):
            files.add(found)
            queue.append(found)
source_hashes = {}
for name in sorted(files):
    source = no_links(REPO / name)
    if not source.is_file(): raise FileNotFoundError(name)
    destination = PROJECT / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    source_hashes[name] = sha(source)
# Recorded test-only project setup; preserve application user dir/autoload/threading.
config = (PROJECT / 'project.godot').read_text(encoding='utf-8-sig')
config = '\n'.join(x for x in config.splitlines() if not x.startswith(('run/main_scene=', 'run/main_scene.fate_server=', 'config/icon=', '_mcp_game_helper=', 'enabled=PackedStringArray(', 'version_control/')))
config = config.replace('renderer/rendering_method="mobile"', 'renderer/rendering_method="gl_compatibility"')
(PROJECT / 'project.godot').write_text(config, encoding='utf-8')
if COUNT:
    p = PROJECT / 'scripts/io/atomic_file_replace.gd'
    text = p.read_text(encoding='utf-8')
    text, n = re.subn(r'(static func replace_validated_file\([^\n]+\n)', r'\1\tprint("SAVE_BRANCH native")\n', text)
    assert n == 1
    p.write_text(text, encoding='utf-8')
    p = PROJECT / 'scripts/net/session/lobby_session.gd'
    text = p.read_text(encoding='utf-8')
    token = 'DirAccess.rename_absolute(temporary, recovery_state_path)'
    assert text.count(token) == 1
    text = text.replace(token, 'preload("res://newtests/observed_rename.gd").rename(temporary, recovery_state_path)')
    p.write_text(text, encoding='utf-8')
    (PROJECT / 'newtests/observed_rename.gd').write_text('extends RefCounted\nstatic func rename(source:String, target:String) -> Error:\n\tprint("SAVE_BRANCH initial")\n\treturn DirAccess.rename_absolute(source, target)\n', encoding='utf-8')
(FIXTURES / 'locked.old').write_bytes(b'old locked ordinary bytes')
(FIXTURES / 'directory.old').mkdir()
env = dict(os.environ)
for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR'):
    p = SCOPE / key.lower()
    p.mkdir()
    env[key] = p.as_posix()
(SCOPE / 'localappdata/hermes/cache/scratch').mkdir(parents=True)
for key in ('ROUND66_FIXTURES', 'ROUND56_HANDOFF_ROOT', 'HERMES_SHUTDOWN_TEST_ROOT'):
    env[key] = FIXTURES.as_posix()
records = []
def run(label, args, fixtures=False):
    out, err = (EVIDENCE / (label + x) for x in ('.stdout.log', '.stderr.log'))
    job = OwnedJob()
    handles = []
    kernel = job.kernel
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR,wintypes.DWORD,wintypes.DWORD,ctypes.c_void_p,wintypes.DWORD,wintypes.DWORD,wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    start = time.monotonic()
    with out.open('wb') as stdout, err.open('wb') as stderr:
        proc = subprocess.Popen([str(ENGINE),'--headless','--audio-driver','Dummy','--fixed-fps','60','--path',PROJECT.as_posix(), *args], env=env, stdout=stdout, stderr=stderr, cwd=PROJECT, creationflags=4)
        try:
            if fixtures:
                # Open exact owned fixture while root is suspended; no delete sharing.
                names = [('locked.old',1)]
                initial_temp = 'initial_locked.json.%d.tmp' % proc.pid
                (FIXTURES / initial_temp).write_bytes(b'ordinary controlled temp')
                names.append((initial_temp,3))
                (FIXTURES / ('open_failure.json.%d.tmp' % proc.pid)).mkdir()
                for name, share in names:
                    handle = kernel.CreateFileW(str(FIXTURES/name),0x80000000,share,None,3,0x80,None)
                    if handle == ctypes.c_void_p(-1).value: raise ctypes.WinError(ctypes.get_last_error())
                    handles.append(handle)
            job.attach_resume(proc)
            try: code = proc.wait(timeout=180)
            except subprocess.TimeoutExpired:
                job.stop(); code = proc.wait(timeout=15)
            deadline = time.monotonic() + 10
            while job.active() and time.monotonic() < deadline:
                time.sleep(0.02)
            active = job.active()
        finally:
            for handle in handles: kernel.CloseHandle(handle)
            if proc.poll() is None: proc.kill(); proc.wait()
            if job.active(): job.stop()
            job.close()
    job.wait_log_release([out, err])
    stdout, stderr = out.read_text(encoding='utf-8'), err.read_text(encoding='utf-8')
    record = {'label':label,'argv':proc.args,'pid':proc.pid,'exit_code':code,'active_owned_processes':active,'seconds':time.monotonic()-start,'analysis':analyze(stdout,stderr,code) if label=='test' else {'passed':code==0 and not re.search(r'SCRIPT ERROR|^ERROR:',stdout+'\n'+stderr,re.M)},'log_sha256':{p.name:sha(p) for p in (out,err)}}
    records.append(record)
    return stdout, stderr, record
# Texture imports precede cursor autoload parsing in the cold fixture only.
# Runtime restores the unchanged autoload definition, not a stub.
(PROJECT / 'project.godot').write_text('\n'.join(x for x in config.splitlines() if not x.startswith('CursorReplace=')), encoding='utf-8')
stdout, stderr, imported = run('import', ['--editor','--import'])
(PROJECT / 'project.godot').write_text(config, encoding='utf-8')
if not imported['analysis']['passed']:
    print(stdout); print(stderr)
    (EVIDENCE/'manifest.json').write_text(json.dumps({'records':records,'source_sha256':source_hashes},ensure_ascii=False,indent=2),encoding='utf-8')
    print('EVIDENCE',EVIDENCE)
    raise SystemExit(1)
scene = ('newtests/' if SUITE == 'recovery_save_observation_test' else 'tests/') + SUITE + '.tscn'
stdout, stderr, tested = run('test', ['--scene','res://'+scene], SUITE == 'recovery_save_observation_test')
errors = []
cases = {}
if SUITE == 'recovery_save_observation_test':
    current = None
    for line in stdout.splitlines():
        if line.startswith('SAVE_CASE_BEGIN '):
            current = line.split()[-1]; cases[current] = {'diagnostics':[], 'native':0, 'initial':0}
        elif line.startswith('SAVE_CASE_END '): current = None
        elif line.startswith('SAVE_BRANCH '):
            if current is None: errors.append('branch outside case')
            else: cases[current][line.split()[-1]] += 1
        elif line.startswith('RECOVERY_SAVE_DIAGNOSTIC '):
            if current is None: errors.append('diagnostic outside case')
            else: cases[current]['diagnostics'].append(json.loads(line[len('RECOVERY_SAVE_DIAGNOSTIC '):]))
    expected = {'empty_path':None,'nonhost':None,'path':'path','seat':'seat','snapshot':'snapshot','initial_success':None,'replace_success':None,'native_locked':'native_commit','initial_locked':'initial_commit','initial_directory':'initial_commit','write_open':'write','success_after_failure':None}
    for name, stage in expected.items():
        events = cases.get(name,{}).get('diagnostics',[])
        if stage is None:
            if events: errors.append(name+' unexpected failure diagnostic')
        elif len(events) != 1: errors.append(name+' missing single real failure diagnostic')
        else:
            d = events[0]
            if set(d) != {'version','stage','native_stage','native_error','godot_error','pid'} or d['stage'] != stage or d['pid'] != tested['pid']: errors.append(name+' unsafe or incorrect schema')
            if name=='native_locked' and (d['native_stage']!='native_replace' or d['native_error']!=32 or d['godot_error'] is not None): errors.append('lost actual native 32')
            if name in {'initial_locked','write_open'} and (type(d['godot_error']) is not int or d['godot_error']<=0 or d['native_error'] is not None): errors.append(name+' lost same-call Godot Error')
    if COUNT:
        for name, case in cases.items():
            expected_count = (1 if name in {'replace_success','native_locked','success_after_failure'} else 0, 1 if name in {'initial_success','initial_locked'} else 0)
            if (case['native'],case['initial']) != expected_count: errors.append(name+' branch count mismatch')
    if (FIXTURES/'locked.old').read_bytes() != b'old locked ordinary bytes': errors.append('ordinary old target changed')
    # Never read/hash/copy generated recovery or secret-bearing temp payloads.
unchanged = all(sha(REPO/name)==digest for name,digest in source_hashes.items())
manifest = {'suite':SUITE,'scope':str(SCOPE),'branch_instrumentation':COUNT,'cases':cases,'errors':errors,'records':records,'source_sha256':source_hashes,'source_unchanged':unchanged,'engine_sha256':sha(ENGINE),'runner_sha256':sha(Path(__file__)),'project_config_sha256':sha(PROJECT/'project.godot'),'passed':all(x['analysis']['passed'] and x['active_owned_processes']==0 for x in records) and not errors and unchanged,'payload_policy':'no generated recovery/temp content read, hash, or archive by runner; only approved diagnostics and control test stdout'}
manifest['runtime_consumed'] = False
(EVIDENCE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
# Consume only this UUID's generated runtime after kernel Job0; never open payloads.
if all(x['active_owned_processes']==0 for x in records):
    generated = [FIXTURES] + [SCOPE/key.lower() for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR')]
    for root in generated:
        if not root.exists(): continue
        assert root.parent == SCOPE and physical_e(root).is_relative_to(SCOPE)
        for directory, dirs, names in os.walk(root, followlinks=False):
            for name in dirs + names: no_links(Path(directory)/name)
        shutil.rmtree(root)
    manifest['runtime_consumed'] = all(not p.exists() for p in generated)
    (EVIDENCE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(stdout); print(stderr)
print(json.dumps({'passed':manifest['passed'],'errors':errors,'checks':tested['analysis'].get('result',{}),'active_owned_processes':[x['active_owned_processes'] for x in records],'source_unchanged':unchanged},ensure_ascii=False))
print('EVIDENCE',EVIDENCE)
raise SystemExit(0 if manifest['passed'] else 1)
