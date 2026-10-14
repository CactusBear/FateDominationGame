"""B31 rules-only evidence runner. Source writes: none; mutations: owned E copy only.
Usage: python -B newtests/run_b31_change_order_probe.py init|baseline|mutations|restore|cleanup
Each invocation uses E TEMP/TMP/TMPDIR; production native call is never migrated.
"""
import argparse
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

SRC = Path(__file__).resolve().parents[1]
ROOT = Path('E:/scratch/registry-b31-changeorder-probe')
FILE = 'scripts/system/global/game_progress.gd'
ROUTER = 'scripts/system/operation_router.gd'
SCENE = 'res://newtests/b31_round_tail_change_order_probe.tscn'
TARGETS = [FILE, ROUTER, 'scripts/system/global/all_operations.gd',
           'scripts/system/operations/ChangePlOrder.gd', 'project.godot']
NATIVE = b'ChangePlOrder.new().exec(null, BaseNumber.new(-1))'
UNKNOWN = b'preload("res://scripts/system/operation_router.gd").exec_registered("__b31_probe_unknown_order__", [null, BaseNumber.new(-1)])'
spec = importlib.util.spec_from_file_location('b31_isolation', SRC / 'tools/run_isolated_godot_test.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def sha(value):
    return hashlib.sha256(value).hexdigest()

def persist():
    (ROOT / 'receipt.json').write_text(json.dumps(M, ensure_ascii=False, indent=2), encoding='utf-8')
    (OWN / 'manifest.json').write_text(json.dumps(M, ensure_ascii=False, indent=2), encoding='utf-8')

def run(label, command, timeout=240, cwd=None, scene=False):
    out = ROOT / 'logs' / (label + '.stdout.log')
    err = ROOT / 'logs' / (label + '.stderr.log')
    rec = {'label': label, 'command': command, 'stdout': str(out), 'stderr': str(err), 'timeout': False}
    M['processes'].append(rec)
    persist()
    begin = time.monotonic()
    job = mod.OwnedJob()
    with out.open('wb') as a, err.open('wb') as b:
        proc = subprocess.Popen(command, cwd=cwd or COPY, env=ENV, stdout=a, stderr=b, creationflags=4)
        rec['pid'] = proc.pid
        persist()
        try:
            job.attach_resume(proc)
            while proc.poll() is None or job.active():
                if time.monotonic() - begin > timeout:
                    rec['timeout'] = True
                    job.stop()
                    break
                time.sleep(0.05)
            rec['exit'] = proc.wait(timeout=15)
            rec['active_owned_processes'] = job.active()
            rec['Job0'] = rec['active_owned_processes'] == 0
            rec['exited'] = True
        finally:
            if job.active():
                job.stop()
            job.close()
    job.wait_log_release([out, err])
    rec['log_handles_released'] = True
    rec['duration_seconds'] = round(time.monotonic() - begin, 3)
    stdout = out.read_text(encoding='utf-8', errors='replace')
    stderr = err.read_text(encoding='utf-8', errors='replace')
    lines = (stdout + '\n' + stderr).splitlines()
    rec['CHECK'] = sum(x.startswith('CHECK ') for x in lines)
    rec['CHECK_false'] = [x for x in lines if x.startswith('CHECK ') and x.endswith(' false')]
    rec['RESULT'] = [x for x in lines if x.startswith('RESULT')]
    rec['ERROR'] = [x for x in lines if re.search(r'(^|\s)(SCRIPT ERROR:|ERROR:)', x)]
    rec['TRACE'] = [x for x in lines if x.startswith(('ORDER_TRACE ', 'ACTOR_TRACE ', 'COUNT_TRACE ', 'DIAGNOSTIC_USER_PATH '))]
    if scene:
        rec['analysis'] = mod.analyze(stdout, stderr, rec['exit'])
    persist()
    print(label, 'CHECK=', rec['CHECK'], 'failures=', len(rec['CHECK_false']),
          'exit=', rec['exit'], 'ERROR=', len(rec['ERROR']), 'Job0=', rec['Job0'], flush=True)
    for line in rec['RESULT']:
        print(line, flush=True)
    return rec

def suite(label):
    return run(label, [str(EXE), '--headless', '--fixed-fps', '60', '--path', str(COPY),
                       '--scene', SCENE], timeout=180, scene=True)

def guard(allowed=()):
    changes = [n for n, value in M['frozen_hashes'].items() if sha((COPY/n).read_bytes()) != value]
    assert not set(changes) - set(allowed), changes
    return changes

parser = argparse.ArgumentParser()
parser.add_argument('stage', choices=['init', 'baseline', 'mutations', 'restore', 'cleanup'])
args = parser.parse_args()
ROOT.mkdir(parents=True, exist_ok=True)
(ROOT / 'logs').mkdir(exist_ok=True)
if args.stage == 'init':
    assert not (ROOT/'receipt.json').exists(), 'receipt already exists'
    token = uuid.uuid4().hex
    OWN = ROOT / ('isolated-' + token)
    GEN = OWN / 'generated'
    COPY = GEN / 'project'
    COPY.mkdir(parents=True)
    M = {'run_id': token, 'source': str(SRC), 'generated': str(GEN), 'copy': str(COPY),
         'owner': str(OWN), 'processes': [], 'started_at': time.strftime('%Y-%m-%dT%H:%M:%S%z')}
    persist()
    assert shutil.disk_usage(ROOT).free > 12 * 1024**3
    includes = ['scripts', 'data', 'assets', 'addons', 'project.godot', 'icon.svg',
                'newtests/b31_order_number_observer.gd',
                'newtests/b31_round_tail_change_order_probe.gd',
                'newtests/b31_round_tail_change_order_probe.tscn']
    selected = mod.source_files(SRC, includes)
    frozen = {}
    for rel in selected:
        if rel.name.startswith('~') and rel.suffix.lower() == '.dll':
            continue
        source = SRC / rel
        target = COPY / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        original = source.read_bytes()
        target.write_bytes(original)  # independent files; never hard links
        assert sha(target.read_bytes()) == sha(source.read_bytes()), str(rel)
        if rel.suffix in {'.gd', '.tscn', '.json', '.gdextension', '.dll', '.godot', '.gdshader'}:
            frozen[rel.as_posix()] = sha(original)
    M['frozen_hashes'] = frozen
    M['source_at_freeze_hashes'] = {n: sha((SRC/n).read_bytes()) for n in frozen}
    assert M['source_at_freeze_hashes'] == frozen, 'source drift at freeze'
    for name in ['docs', 'reports', 'newtests/join_shape_session_wiring_evidence']:
        folder = COPY / name
        folder.mkdir(parents=True, exist_ok=True)
        (folder / '.gdignore').write_bytes(b'')
    M['gdignore_before_import'] = ['docs/.gdignore', 'reports/.gdignore',
                                   'newtests/join_shape_session_wiring_evidence/.gdignore']
    M['original_sha'] = {n: sha((COPY/n).read_bytes()) for n in TARGETS}
    for name in TARGETS:
        (ROOT/(Path(name).name+'.original.txt')).write_bytes((COPY/name).read_bytes())
    engine = GEN / 'engine'
    engine.mkdir()
    for f in Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe').glob('*.exe'):
        shutil.copy2(f, engine/f.name)
    M['engine'] = str(engine/'Godot_v4.7.2-stable_win64_console.exe')
    M['engine_sha'] = sha(Path(M['engine']).read_bytes())
    M['env'] = {}
    for key in ['APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR']:
        folder = GEN / 'env' / key
        folder.mkdir(parents=True)
        M['env'][key] = str(folder)
    persist()
else:
    M = json.loads((ROOT/'receipt.json').read_text(encoding='utf-8'))
    OWN = Path(M['owner'])
    GEN = Path(M['generated'])
    COPY = Path(M['copy'])
ENV = os.environ.copy()
ENV.update(M['env'])
ENV['PYTHONDONTWRITEBYTECODE'] = '1'
EXE = Path(M['engine'])
if args.stage == 'init':
    result = run('import', [str(EXE), '--headless', '--path', str(COPY), '--import'], timeout=600)
    assert result['exit'] == 0
    cache = (COPY/'.godot/global_script_class_cache.cfg').read_text(encoding='utf-8')
    blocks = re.findall(r'\{[^{}]*\}', cache, re.S)
    paths = {re.search(r'"class": &"([^"]+)"', b)[1]: re.search(r'"path": "([^"]+)"', b)[1]
             for b in blocks if '"class"' in b and '"path"' in b}
    M['class_cache'] = {'AreaActionRules': paths.get('AreaActionRules'),
                        'MatchLobbySession': paths.get('MatchLobbySession'),
                        'archive_paths': [p for p in paths.values() if p.startswith(('res://docs/', 'res://reports/'))],
                        'count': len(paths)}
    assert paths.get('AreaActionRules') == 'res://scripts/system/area_action_rules.gd'
    assert paths.get('MatchLobbySession') == 'res://scripts/net/session/lobby_session.gd'
    assert not M['class_cache']['archive_paths']
    guard()
    (COPY/'probe.gd').write_text(mod.PROBE_SCRIPT, encoding='utf-8')
    result = run('user_probe', [str(EXE), '--headless', '--path', str(COPY), '--script',
                              'res://probe.gd', '--', M['run_id'], 'main', str(GEN)], timeout=60)
    assert result['exit'] == 0 and not result['ERROR'] and result['Job0']
    M['user_probe'] = mod.verify_probe(Path(result['stdout']).read_text(encoding='utf-8'), GEN, M['run_id'])
    M['init_done'] = True
    persist()
elif args.stage == 'baseline':
    guard()
    result = suite('baseline')
    assert result['analysis']['passed'], result
    M['baseline_done'] = True
    persist()
elif args.stage == 'mutations':
    assert M.get('baseline_done')
    guard()
    original = (ROOT/'game_progress.gd.original.txt').read_bytes()
    router = (ROOT/'operation_router.gd.original.txt').read_bytes()
    assert original.count(NATIVE) == 1
    error_line = 'push_error("未注册的 operation：%s" % func_name)'.encode()
    assert router.count(error_line) == 1
    silent_router = router.replace(error_line, b'pass', 1)  # no entry log either
    mutant = original.replace(NATIVE, UNKNOWN, 1)
    M['mutation_sha'] = {'unknown_consumer': sha(mutant), 'silent_router': sha(silent_router)}
    try:
        (COPY/FILE).write_bytes(mutant)
        guard((FILE,))
        unknown = suite('unknown')
        (COPY/ROUTER).write_bytes(silent_router)
        guard((FILE, ROUTER))
        silent = suite('silent_unknown')
        assert unknown['CHECK_false'] == silent['CHECK_false'] and silent['CHECK_false']
        assert any('三独立玩家-1恰好轮转一位' in x for x in silent['CHECK_false'])
        assert silent['exit'] == 1 and silent['ERROR'] == [] and silent['Job0']
        (COPY/ROUTER).write_bytes(router)
        double = original.replace(NATIVE, NATIVE + b'\n\t' + NATIVE, 1)
        (COPY/FILE).write_bytes(double)
        M['mutation_sha']['double_consumer'] = sha(double)
        guard((FILE,))
        duplicate = suite('double_rotation')
        assert duplicate['exit'] == 1 and duplicate['CHECK_false'] and duplicate['ERROR'] == []
        # 四次与一次最终排列相同；必须由公开数字观察器识别隐藏的完整循环。
        four = original.replace(NATIVE, (b'\n\t').join([NATIVE] * 4), 1)
        (COPY/FILE).write_bytes(four)
        M['mutation_sha']['four_consumer'] = sha(four)
        guard((FILE,))
        hidden = suite('four_rotation_same_permutation')
        assert hidden['exit'] == 1 and hidden['CHECK_false'] and hidden['ERROR'] == []
        assert all('恰好一次真实-1运算' in x or '没有隐藏追加轮转' in x for x in hidden['CHECK_false'])
        M['mutations_done'] = True
    finally:
        (COPY/FILE).write_bytes(original)
        (COPY/ROUTER).write_bytes(router)
        guard()
        M['restored_sha'] = {n: sha((COPY/n).read_bytes()) for n in TARGETS}
        assert M['restored_sha'] == M['original_sha']
        persist()
elif args.stage == 'restore':
    assert M.get('mutations_done')
    guard()
    result = suite('restored')
    assert result['analysis']['passed']
    layer = run('layer_source', [sys.executable, '-B', 'tools/check_layer_deps.py'], cwd=SRC)
    assert layer['exit'] == 0
    M['source_current_sha'] = {n: sha((SRC/n).read_bytes()) for n in M['frozen_hashes']}
    M['source_drift'] = [n for n, h in M['frozen_hashes'].items() if M['source_current_sha'][n] != h]
    M['target_source_sha'] = {n: sha((SRC/n).read_bytes()) for n in TARGETS}
    assert M['target_source_sha'] == M['original_sha']
    M['restore_done'] = True
    persist()
elif args.stage == 'cleanup':
    assert M.get('restore_done')
    guard()
    assert all(p.get('Job0') and p.get('exited') for p in M['processes'])
    persist()
    mod.delete_owned(GEN, OWN)
    M['cleanup'] = {'generated_deleted': not GEN.exists(), 'copy_deleted': not COPY.exists(),
                    'at': time.strftime('%Y-%m-%dT%H:%M:%S%z')}
    persist()
    print('COPY_DELETED', M['cleanup'])
