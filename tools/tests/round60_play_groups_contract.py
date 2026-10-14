"""Single owned scene freeze; preserve each RED independently on physical E."""
import sys
sys.dont_write_bytecode = True
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import uuid

REPO = Path(__file__).resolve().parents[2]
def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
r = load_module('round60_isolated', REPO / 'tools/run_isolated_godot_test.py')
e = load_module('round60_integrated', REPO / 'tools/tests/test_round29_integrated_evidence.py')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def recover_first():
    """Finalize only the known failed namespace; never rerun a scene."""
    root = r.physical_e('E:/scratch/round60-play-groups-red-first-dd2832071f644e348e30532a16138752')
    generated = r.contained(root / 'generated', root)
    query = "$ErrorActionPreference='Stop'; @(Get-CimInstance Win32_Process | Where-Object {$_.ExecutablePath -like '" + str(generated) + "\\*'} | Select-Object ProcessId,ExecutablePath) | ConvertTo-Json -Compress"
    p = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', query], capture_output=True, text=True, check=True)
    active = json.loads(p.stdout or '[]')
    if active: raise ValueError('owned executable still active: ' + str(active))
    evidence = root / 'evidence'
    artifacts = [{'path': f.relative_to(evidence).as_posix(), 'sha256': sha(f)} for f in evidence.rglob('*') if f.is_file()]
    record = {'root': str(root), 'historical_job_accounting': 'not_serialized_before_cleanup_exception', 'currently_active_owned_executables': active, 'artifacts': artifacts, 'artifact_readback': all(sha(evidence / x['path']) == x['sha256'] for x in artifacts), 'cleanup': 'not_started', 'scene_rerun': False}
    (root / 'recovery.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
    r.tree_bytes(generated)
    shutil.rmtree(generated)
    if generated.exists(): raise ValueError('failed cleanup')
    record['cleanup'] = 'generated_removed'
    (root / 'recovery.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k:v for k,v in record.items() if k != 'artifacts'}, ensure_ascii=False))
    return 0
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--label', required=True)
    ap.add_argument('--window', action='store_true')
    args = ap.parse_args()
    if not re.fullmatch(r'[a-z0-9-]+', args.label): raise ValueError('invalid label')
    parent = r.physical_e('E:/scratch') / ('round60-play-groups-' + args.label)
    parent.mkdir(exist_ok=True)
    token = uuid.uuid4().hex
    root = parent / ('isolated-' + token)
    root.mkdir()
    gen = root / 'generated'; gen.mkdir()
    evidence = root / 'evidence'; evidence.mkdir()
    target = gen / 'project'; target.mkdir()
    m = {'root': str(root), 'run_id': token, 'generated': str(gen), 'processes': [], 'suites': [], 'cleanup': 'not_started', 'passed': False}
    budgets = {'seconds': 180, 'bytes': 8589934592, 'min_free': 1073741824}
    env = os.environ.copy()
    for key in ('APPDATA', 'LOCALAPPDATA'):
        folder = gen / key.lower(); folder.mkdir(); env[key] = str(folder)
    fixture = gen / 'fixtures'; fixture.mkdir()
    env['FATE_TEST_SCRATCH_ROOT'] = fixture.as_posix()
    env.pop('HERMES_RECOVERY_VALIDATION_ROOT', None)
    files = []
    try:
        includes = ['project.godot', 'scripts', 'assets', 'data', 'game_data', 'addons', 'json_maker', 'icon.svg',
                    'tests/battle_play_groups_test.gd', 'tests/battle_play_groups_test.tscn']
        files = [p for p in r.source_files(REPO, includes) if not (p.suffix == '.dll' and p.name.startswith('~'))]
        before = {p.as_posix(): sha(REPO / p) for p in files}
        for p in files:
            dest = target / p; dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / p, dest)
            if sha(dest) != before[p.as_posix()]: raise ValueError('freeze drift: ' + str(p))
        m['source_hashes'] = before
        config, transform = e.transform_isolated_editor_vcs((target / 'project.godot').read_text(encoding='utf-8-sig'))
        (target / 'project.godot').write_text(config, encoding='utf-8')
        m['editor_transform'] = transform
        frozen = {p.as_posix(): sha(target / p) for p in files}
        engine_source = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
        engine = gen / 'Godot.exe'; shutil.copyfile(engine_source, engine)
        m['engine_sha256'] = sha(engine)
        if m['engine_sha256'] != sha(engine_source): raise ValueError('engine drift')
        probe = gen / 'probe'; probe.mkdir()
        app = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)', config, re.M | re.S)[1]
        threads = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)', config, re.M | re.S)[1]
        (probe / 'project.godot').write_text('config_version=5\n[application]\n'+app+'\n[threading]\n'+threads, encoding='utf-8')
        (probe / 'probe.gd').write_text(r.PROBE_SCRIPT, encoding='utf-8')
        out, err, code = r.execute([str(engine), '--headless', '--path', str(probe), '--script', 'res://probe.gd', '--', token, 'main', str(gen)], env, gen, evidence, 'probe', budgets, m['processes'])
        if code or re.search(r'SCRIPT ERROR|ERROR:', out + err): raise ValueError('physical probe failed')
        m['physical_probes'] = r.verify_probe(out, gen, token)
        out, err, code = r.execute([str(engine), '--headless', '--editor', '--import', '--path', str(target)], env, gen, evidence, 'import', budgets, m['processes'])
        if code or re.search(r'SCRIPT ERROR|ERROR:', out + err): raise ValueError('import failed')
        (target / 'tests/runtime_reports').mkdir(parents=True, exist_ok=True)
        for mode in ['headless'] + (['window'] if args.window else []):
            command = [str(engine)] + (['--headless'] if mode == 'headless' else []) + ['--fixed-fps', '60', '--path', str(target), '--scene', 'res://tests/battle_play_groups_test.tscn']
            out, err, code = r.execute(command, env, gen, evidence, mode, budgets, m['processes'])
            m['suites'].append({'mode': mode, 'command': command, 'exit_code': code, 'analysis': r.analyze(out, err, code)})
            print(json.dumps(m['suites'][-1], ensure_ascii=False), flush=True)
            if not m['suites'][-1]['analysis']['passed']: break
        m['source_drift'] = {p.as_posix(): [before[p.as_posix()], sha(REPO / p)] for p in files if sha(REPO / p) != before[p.as_posix()]}
        m['freeze_drift'] = {p.as_posix(): [frozen[p.as_posix()], sha(target / p)] for p in files if sha(target / p) != frozen[p.as_posix()]}
        m['passed'] = len(m['suites']) == (2 if args.window else 1) and all(x['analysis']['passed'] for x in m['suites']) and not m['source_drift'] and not m['freeze_drift']
    except Exception as exc:
        m['error'] = repr(exc)
    finally:
        archive = evidence / 'frozen-inputs'; archive.mkdir()
        for p in files:
            if p.suffix in {'.gd', '.tscn', '.godot', '.gdextension'}:
                dest = archive / p; dest.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(target / p, dest)
        for p in target.glob('tests/runtime_reports/*.png'): shutil.copyfile(p, evidence / p.name)
        logs = gen / 'appdata/FateDomination/logs'
        if logs.exists(): shutil.copytree(logs, evidence / 'engine-logs')
        m['artifacts'] = [{'path': p.relative_to(evidence).as_posix(), 'sha256': sha(p), 'bytes': p.stat().st_size} for p in evidence.rglob('*') if p.is_file()]
        m['artifact_readback'] = all(sha(evidence / x['path']) == x['sha256'] for x in m['artifacts'])
        (root / 'manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent=2), encoding='utf-8')
        if all(x.get('exited') and x.get('active_owned_processes') == 0 for x in m['processes']) and m['artifact_readback']:
            r.delete_owned(gen, root); m['cleanup'] = 'generated_removed'
        (root / 'manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps({'manifest': str(root / 'manifest.json'), 'passed': m['passed'], 'error': m.get('error'), 'cleanup': m['cleanup'], 'artifact_readback': m['artifact_readback']}, ensure_ascii=False), flush=True)
    return 0 if m['passed'] else 1
if __name__ == '__main__': raise SystemExit(recover_first() if sys.argv[1:] == ['--recover-first'] else main())
