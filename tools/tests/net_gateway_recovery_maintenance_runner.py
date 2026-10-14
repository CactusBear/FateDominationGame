"""Only the maintenance regression: one RED, one GREEN, same frozen dependencies.
Reuses the existing owned Job executor and strict ERROR parser; no observers.
"""
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
import uuid

REPO = Path(__file__).resolve().parents[2]
TEST = 'tests/net_gateway_recovery_maintenance_test.gd'
SCENE = 'res://tests/net_gateway_recovery_maintenance_test.tscn'

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

r = load('maintenance_owned', REPO / 'tools/run_isolated_godot_test.py')
e = load('maintenance_config', REPO / 'tools/tests/test_round29_integrated_evidence.py')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def analyze_maintenance(stdout, stderr, exit_code):
    # This suite's check() prints bool-last. Labels may literally start with false.
    # Prefix only the parser input, never the retained stdout; ERROR checks stay strict.
    lines = stdout.splitlines()
    if any(not re.fullmatch(r'CHECK .+ (true|false)', line) for line in lines if line.startswith('CHECK ')):
        raise ValueError('unexpected maintenance CHECK producer format')
    normalized = '\n'.join('CHECK maintenance: ' + line[6:] if line.startswith('CHECK ') else line for line in lines)
    return r.analyze(normalized, stderr, exit_code)

def reparse(parent, pointer):
    owner = r.contained(Path(json.loads(pointer.read_text())['owner']), parent)
    path = owner / 'manifest.json'
    m = json.loads(path.read_text(encoding='utf-8'))
    if m['cleanup'] != 'generated_removed' or not m.get('job0') or m.get('error'):
        raise ValueError('completed owned execution required for evidence-only reparse')
    if [s['mode'] for s in m['suites']] != ['red', 'green']:
        raise ValueError('exact RED/GREEN pair required')
    evidence = owner / 'evidence'
    for item in m['logs']:
        if sha(evidence / item['path']) != item['sha256']: raise ValueError('raw log hash mismatch')
    for suite in m['suites']:
        mode = suite['mode']
        if sha(evidence / (mode + '-target.gd')) != suite['source_sha256']:
            raise ValueError('executed target hash mismatch')
        suite.setdefault('analysis_before_bool_last_reparse', suite['analysis'])
        suite['analysis'] = analyze_maintenance((evidence / (mode + '.stdout.log')).read_text(encoding='utf-8'),
                                               (evidence / (mode + '.stderr.log')).read_text(encoding='utf-8'), suite['exit_code'])
    m['passed'] = m['suites'][1]['analysis']['passed'] and not m['frozen_drift']
    m['evidence_only_reparse'] = {'business_rerun': False, 'check_producer': 'bool-last', 'reparser_sha256': sha(Path(__file__))}
    save(path, m)
    print(json.dumps({'manifest': str(path), 'passed': m['passed'], 'job0': m['job0'], 'suites': m['suites'],
                      'business_rerun': False}, ensure_ascii=False))
    return 0 if m['passed'] else 1

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    ap.add_argument('--mode', choices=['red', 'green', 'finalize', 'reparse'], required=True)
    args = ap.parse_args()
    parent = r.physical_e(args.root)
    pointer = parent / 'current.json'
    if args.mode == 'reparse': return reparse(parent, pointer)
    if args.mode == 'red':
        if pointer.exists(): raise ValueError('RED already allocated; refusing another run')
        token = uuid.uuid4().hex
        owner = parent / ('isolated-' + token)
        owner.mkdir()
        gen = owner / 'generated'; gen.mkdir()
        evidence = owner / 'evidence'; evidence.mkdir()
        target = gen / 'project'; target.mkdir()
        m = {'run_id': token, 'generated': str(gen), 'processes': [], 'suites': [],
             'scope': ['project.godot', 'scripts', 'assets', 'data', 'game_data', 'addons',
                       'json_maker', 'icon.svg', TEST, SCENE.removeprefix('res://')],
             'budgets': {'seconds': 180, 'bytes': 2147483648, 'min_free': 1073741824},
             'passed': False, 'cleanup': 'retained_between_red_and_green'}
        save(pointer, {'owner': str(owner)})
        save(owner / 'manifest.json', m)
    else:
        owner = r.contained(Path(json.loads(pointer.read_text())['owner']), parent)
        m = json.loads((owner / 'manifest.json').read_text(encoding='utf-8'))
        gen = r.contained(Path(m['generated']), owner)
        evidence = owner / 'evidence'
        target = gen / 'project'
    try:
        env = os.environ.copy()
        for key in ['APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR', 'FATE_TEST_SCRATCH_ROOT']:
            folder = gen / key.lower(); folder.mkdir(exist_ok=True)
            env[key] = folder.as_posix()
        env.pop('HERMES_RECOVERY_VALIDATION_ROOT', None)
        m['environment'] = {k: env[k] for k in ['APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR', 'FATE_TEST_SCRATCH_ROOT']}
        if args.mode == 'red':
            files = [p for p in r.source_files(REPO, m['scope']) if not (p.suffix == '.dll' and p.name.startswith('~'))]
            m['source_hashes'] = {p.as_posix(): sha(REPO / p) for p in files}
            for rel in files:
                dest = target / rel; dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(REPO / rel, dest)
                if sha(dest) != m['source_hashes'][rel.as_posix()]:
                    raise ValueError('freeze drift during copy: ' + str(rel))
            cfg, transform = e.transform_isolated_editor_vcs((target / 'project.godot').read_text(encoding='utf-8-sig'))
            (target / 'project.godot').write_text(cfg, encoding='utf-8')
            m['editor_transform'] = transform
            m['frozen_hashes'] = {p.as_posix(): sha(target / p) for p in files}
            # Archive exact source inputs before runtime; no live publication tree scan.
            archive = evidence / 'frozen-source'
            for rel in files:
                if rel.suffix in {'.gd', '.tscn', '.godot', '.gdextension'}:
                    dest = archive / rel; dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(target / rel, dest)
            source_engine = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
            engine = gen / 'Godot.exe'; shutil.copyfile(source_engine, engine)
            m['engine_sha256'] = sha(engine)
            if m['engine_sha256'] != sha(source_engine): raise ValueError('engine copy drift')
            probe = gen / 'probe'; probe.mkdir()
            app = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)', cfg, re.M | re.S)[1]
            app = re.sub(r'(?m)^(?:run/main_scene(?:\.\w+)?|config/icon)=.*\n?', '', app)
            threads = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)', cfg, re.M | re.S)[1]
            (probe / 'project.godot').write_text('config_version=5\n[application]\n'+app+'\n[threading]\n'+threads, encoding='utf-8')
            (probe / 'probe.gd').write_text(r.PROBE_SCRIPT, encoding='utf-8')
            out, err, code = r.execute([str(engine), '--headless', '--path', str(probe), '--script', 'res://probe.gd', '--', m['run_id'], 'main', gen.as_posix()], env, gen, evidence, 'probe', m['budgets'], m['processes'])
            if code or re.search(r'SCRIPT ERROR|ERROR:', out+err): raise ValueError('physical probe failed')
            m['physical_probes'] = r.verify_probe(out, gen, m['run_id'])
            out, err, code = r.execute([str(engine), '--headless', '--editor', '--import', '--path', str(target)], env, gen, evidence, 'import', m['budgets'], m['processes'])
            if code or re.search(r'SCRIPT ERROR|ERROR:', out+err): raise ValueError('frozen import failed')
        if args.mode in {'red', 'green'}:
            if any(s['mode'] == args.mode for s in m['suites']): raise ValueError('mode already executed')
            drift = [p for p, h in m['frozen_hashes'].items() if sha(target / p) != h]
            if drift: raise ValueError('frozen dependency drift: ' + repr(drift))
            if args.mode == 'green':
                if len(m['suites']) != 1 or m['suites'][0]['mode'] != 'red': raise ValueError('current RED required')
                shutil.copyfile(REPO / TEST, target / TEST)
                m['frozen_hashes'][TEST] = sha(target / TEST)
            dest = evidence / (args.mode + '-target.gd')
            shutil.copyfile(target / TEST, dest)
            command = [str(gen / 'Godot.exe'), '--headless', '--fixed-fps', '60', '--path', str(target), '--scene', SCENE]
            out, err, code = r.execute(command, env, gen, evidence, args.mode, m['budgets'], m['processes'])
            suite = {'mode': args.mode, 'source_sha256': sha(dest), 'exit_code': code,
                     'analysis': analyze_maintenance(out, err, code)}
            m['suites'].append(suite)
            print(out, end=''); print(err, end='', file=sys.stderr)
            print(json.dumps(suite, ensure_ascii=False))
            m['frozen_drift'] = [p for p, h in m['frozen_hashes'].items() if sha(target / p) != h]
            if m['frozen_drift']: raise ValueError('frozen source mutated at runtime')
            m['passed'] = args.mode == 'green' and suite['analysis']['passed']
        if args.mode in {'green', 'finalize'}:
            m['logs'] = [{'path': p.relative_to(evidence).as_posix(), 'sha256': sha(p)} for p in evidence.rglob('*.log')]
            m['job0'] = bool(m['processes']) and all(p.get('exited') is True and p.get('active_owned_processes') == 0 for p in m['processes'])
            save(owner / 'manifest.json', m)
            if m['job0']:
                r.delete_owned(gen, owner)
                m['cleanup'] = 'generated_removed'
            else:
                m['passed'] = False
                m['cleanup'] = 'retained_exit_unproven'
    except Exception as exc:
        m['error'] = repr(exc)
        m['passed'] = False
        raise
    finally:
        save(owner / 'manifest.json', m)
        print(json.dumps({'manifest': str(owner / 'manifest.json'), 'passed': m['passed'], 'cleanup': m['cleanup'], 'error': m.get('error')}, ensure_ascii=False))
    return 0 if m['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
