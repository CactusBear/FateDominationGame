"""Isolated real Godot + WinAPI fixtures; no production writes or recovery reads."""
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import uuid

REPO = Path(__file__).resolve().parents[1]
ENGINE_DIR = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe')
ENGINE = ENGINE_DIR if ENGINE_DIR.is_file() else ENGINE_DIR / 'Godot_v4.7.2-stable_win64_console.exe'
if not ENGINE.is_file():
    candidates = sorted(ENGINE_DIR.glob('*.exe'))
    ENGINE = next((p for p in candidates if 'console' in p.name), candidates[0] if candidates else ENGINE)
if not ENGINE.is_file():
    raise FileNotFoundError('Actual Godot executable not found')
READ_ONLY = ['scripts/net/session/lobby_session.gd', 'scripts/io/atomic_file_replace.gd', 'scripts/io/validated_file_content.gd', 'scripts/net/server/server_console_channel.gd', 'scripts/net/server/server_room_manager.gd', 'addons/fate_server_signals/src/atomic_file_replace_binding.cpp', 'addons/fate_server_signals/src/atomic_file_replace_core.cpp']
read_only_hashes = {name:hashlib.sha256((REPO/name).read_bytes()).hexdigest() for name in READ_ONLY}
SCOPE = Path('E:/scratch') / ('round64-save-diagnostic-' + uuid.uuid4().hex)
SCOPE.mkdir(parents=True, exist_ok=False)
if SCOPE.resolve().drive.lower() != 'e:':
    raise RuntimeError('Scratch resolved outside E drive')
PROJECT = SCOPE / 'project'
EVIDENCE = SCOPE / 'evidence'
PROJECT.mkdir()
EVIDENCE.mkdir()
files = [
    'newtests/recovery_save_diagnostic_test.gd',
    'scripts/io/atomic_file_replace.gd',
    'scripts/net/server/recovery_path_safety.gd',
    'scripts/net/server/recovery_save_diagnostic.gd',
    'addons/fate_server_signals/fate_server_signals.gdextension',
    'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll',
]
hashes = {}
for name in files:
    source = REPO / name
    if not source.is_file():
        continue
    destination = PROJECT / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    hashes[name] = hashlib.sha256(source.read_bytes()).hexdigest()
(PROJECT / 'project.godot').write_text('[application]\nconfig/name="Round64SaveDiagnostic"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n[threading]\nworker_pool/max_threads=2\n', encoding='utf-8')
fixtures = SCOPE / 'fixtures'
fixtures.mkdir()
for name, data in {'success.old':b'old ordinary bytes','success.tmp':b'new ordinary bytes','locked.old':b'old locked ordinary bytes','locked.tmp':b'new locked ordinary bytes','directory.tmp':b'directory conflict ordinary bytes'}.items():
    (fixtures/name).write_bytes(data)
(fixtures/'directory.old').mkdir()
before = {p.name:p.read_bytes() for p in fixtures.iterdir() if p.is_file()}
kernel = ctypes.WinDLL('kernel32', use_last_error=True)
kernel.CreateFileW.argtypes = [wintypes.LPCWSTR,wintypes.DWORD,wintypes.DWORD,ctypes.c_void_p,wintypes.DWORD,wintypes.DWORD,wintypes.HANDLE]
kernel.CreateFileW.restype = wintypes.HANDLE
kernel.CloseHandle.argtypes = [wintypes.HANDLE]
kernel.CloseHandle.restype = wintypes.BOOL
# Existing ordinary target reader explicitly denies FILE_SHARE_DELETE.
handle = kernel.CreateFileW(str(fixtures/'locked.old'), 0x80000000, 1, None, 3, 0x80, None)
if handle == ctypes.c_void_p(-1).value:
    raise OSError(ctypes.get_last_error(), 'controlled lock fixture creation failed')
winapi_controls = []
# Exact immediate failure-code capture on new ordinary fixtures, not inferred errno.
for name, access in [('directory.old', 0x80), ('locked.old', 0x00010000)]:
    ctypes.set_last_error(0)
    control_handle = kernel.CreateFileW(str(fixtures/name), access, 1 | 4, None, 3, 0x00200000, None)
    observed_error = ctypes.get_last_error() if control_handle == ctypes.c_void_p(-1).value else None
    if control_handle != ctypes.c_void_p(-1).value:
        kernel.CloseHandle(control_handle)
    winapi_controls.append({'fixture':name,'api':'CreateFileW','access':access,'failed':observed_error is not None,'native_error':observed_error})
assert winapi_controls[0]['native_error'] == 5
assert winapi_controls[1]['native_error'] == 32
env = os.environ.copy()
for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR'):
    folder = SCOPE / key.lower()
    folder.mkdir()
    env[key] = str(folder)
env['ROUND64_FIXTURES'] = fixtures.as_posix()
argv = [str(ENGINE),'--headless','--fixed-fps','60','--path',str(PROJECT),'--script','res://newtests/recovery_save_diagnostic_test.gd']
timed_out = False
try:
    # Test does not spawn child processes; terminate only this owned PID on timeout.
    with (EVIDENCE/'stdout.log').open('wb') as out, (EVIDENCE/'stderr.log').open('wb') as err:
        proc = subprocess.Popen(argv, env=env, stdout=out, stderr=err)
        try:
            code = proc.wait(timeout=180)
        except subprocess.TimeoutExpired:
            timed_out = True
            proc.kill()
            code = proc.wait(timeout=15)
finally:
    if not kernel.CloseHandle(handle):
        raise OSError(ctypes.get_last_error(), 'controlled lock close failed')
stdout = (EVIDENCE/'stdout.log').read_text(encoding='utf-8', errors='replace')
stderr = (EVIDENCE/'stderr.log').read_text(encoding='utf-8', errors='replace')
assert (fixtures/'locked.old').read_bytes() == before['locked.old']
assert (fixtures/'locked.tmp').read_bytes() == before['locked.tmp']
assert (fixtures/'directory.tmp').read_bytes() == before['directory.tmp']
assert (fixtures/'directory.old').is_dir()
results = re.findall(r'^RESULT checks=(\d+) failures=(.*)$', stdout, re.M)
error_lines = [line for line in (stdout+'\n'+stderr).splitlines() if re.search(r'SCRIPT ERROR|^ERROR:|SHADER ERROR', line)]
passed = code == 0 and not timed_out and len(results) == 1 and json.loads(results[0][1]) == [] and not error_lines
manifest = {'scope':str(SCOPE),'argv':argv,'pid':proc.pid,'exit_code':code,'timed_out':timed_out,'source_sha256':hashes,'source_unchanged':all(hashlib.sha256((REPO/name).read_bytes()).hexdigest()==digest for name,digest in hashes.items()),'checks':int(results[0][0]) if len(results)==1 else None,'error_lines':error_lines,'passed':passed,'fixture_lock':'CreateFileW GENERIC_READ FILE_SHARE_READ; no share delete','environment':{key:env[key] for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR')},'engine_sha256':hashlib.sha256(ENGINE.read_bytes()).hexdigest(),'readback':{'lock_old_unchanged':True,'lock_temp_unchanged':True,'directory_temp_unchanged':True,'directory_target_preserved':True}}
read_only_unchanged = all(hashlib.sha256((REPO/name).read_bytes()).hexdigest()==digest for name,digest in read_only_hashes.items())
check_rows = re.findall(r'^CHECK (.*) (true|false)$', stdout, re.M)
counts_valid = len(results)==1 and len(check_rows)==int(results[0][0]) and all(value=='true' for _,value in check_rows)
manifest['passed'] = passed and counts_valid and read_only_unchanged
manifest['winapi_controls'] = winapi_controls
manifest['read_only_sha256'] = read_only_hashes
manifest['read_only_unchanged'] = read_only_unchanged
manifest['check_rows_match_result'] = counts_valid
manifest['runner_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
manifest['log_sha256'] = {name:hashlib.sha256((EVIDENCE/name).read_bytes()).hexdigest() for name in ['stdout.log','stderr.log']}
(EVIDENCE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(stdout)
print(stderr)
print(json.dumps(manifest,ensure_ascii=False,indent=2))
print('EVIDENCE', EVIDENCE)
raise SystemExit(0 if manifest['passed'] and manifest['source_unchanged'] else 1)
