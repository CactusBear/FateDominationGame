"""A7 step 1: one frozen dependency tree, serial single-site variants, real Godot evidence.
Uses existing owned-Job runner. Never restores or edits production files.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('owned_runner', ROOT / 'tools/run_isolated_godot_test.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
REL = 'scripts/system/regular_play.gd'
SCENES = ['newtests/regular_play_existing_ops_compare_test.tscn',
          'tests/regular_play_test.tscn', 'tests/magic_payment_contract_test.tscn',
          'tests/rule_guard_regular_group_test.tscn', 'tests/rule_guard_regular_add_test.tscn']
EXTRA = ['tests/battlefield_conceal_test.tscn', 'tests/extra_play_limit_test.tscn', 'tests/mana_spend_test.tscn']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(owner, manifest):
    (owner / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')


def environment(generated):
    env = os.environ.copy()
    for key, name in [('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata'),
                      ('TMPDIR', 'tmp'), ('TEMP', 'tmp'), ('TMP', 'tmp')]:
        path = generated / name
        path.mkdir(exist_ok=True)
        env[key] = str(path)
    return env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['init', 'stage'])
    parser.add_argument('--base', required=True)
    parser.add_argument('--seed-manifest')
    parser.add_argument('--godot')
    parser.add_argument('--owner')
    parser.add_argument('--label', default='baseline')
    parser.add_argument('--final', action='store_true')
    args = parser.parse_args()
    base = runner.physical_e(Path(args.base))
    budgets = {'seconds': 600, 'bytes': 2147483648, 'min_free': 1073741824}
    if args.action == 'init':
        seed = json.loads(Path(args.seed_manifest).read_text(encoding='utf-8'))
        token = uuid.uuid4().hex
        owner = base / ('isolated-' + token)
        generated = owner / 'generated'
        target = generated / 'project'
        evidence = owner / 'evidence'
        for path in (generated, target, evidence):
            path.mkdir(parents=True, exist_ok=True)
        manifest = {'run_id': token, 'generated': str(generated), 'processes': [],
                    'source_hashes': {}, 'stages': [], 'budgets': budgets}
        includes = [p for p in seed['source_hashes'] if not p.startswith(('tests/', 'newtests/'))]
        includes = [p for p in includes if not (Path(p).name.startswith('~') and p.endswith('.dll'))]
        includes += [p.relative_to(ROOT).as_posix() for p in (ROOT / 'scripts/system/operations').glob('*.gd')]
        includes += [p.relative_to(ROOT).as_posix() for p in (ROOT / 'scripts/system/effects').glob('*.gd')]
        includes += SCENES + EXTRA
        files = set(includes)
        pending = list(files)
        while pending:
            rel = pending.pop()
            if not rel.startswith(('tests/', 'newtests/')) or not rel.endswith(('.gd', '.tscn')):
                continue
            refs = re.findall(r'res://((?:tests|newtests)/[^"\n]+\.(?:gd|tscn))',
                              (ROOT / rel).read_text(encoding='utf-8-sig'))
            for ref in refs:
                if ref not in files:
                    files.add(ref)
                    pending.append(ref)
        for rel in sorted(files):
            src = runner.contained(ROOT / rel, ROOT)
            dst = target / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
            if sha(src) != sha(dst):
                raise RuntimeError('source changed during freeze ' + rel)
            manifest['source_hashes'][rel] = sha(dst)
        drift = [p for p,h in manifest['source_hashes'].items() if sha(ROOT / p) != h]
        if drift:
            raise RuntimeError('source drift at freeze: ' + repr(drift))
        exe = generated / 'Godot.exe'
        shutil.copyfile(runner.physical_e(Path(args.godot)), exe)
        manifest['engine_sha256'] = sha(exe)
        cfg = (target / 'project.godot').read_text(encoding='utf-8-sig')
        cfg = cfg.replace('version_control/plugin_name="GitPlugin"\n', '').replace(
            'version_control/autoload_on_startup=true', 'version_control/autoload_on_startup=false')
        (target / 'project.godot').write_text(cfg, encoding='utf-8')
        manifest['editor_transform'] = 'isolated copy only: VCS plugin removed; autoload false'
        manifest['frozen_project_sha256'] = sha(target / 'project.godot')
        manifest['frozen_hashes'] = {p: sha(target / p) for p in files}
        (evidence / 'baseline.gd').write_bytes((target / REL).read_bytes())
        application = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)', cfg, re.M | re.S).group(1)
        threading = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)', cfg, re.M | re.S)
        probe = generated / 'probe'
        probe.mkdir()
        (probe / 'project.godot').write_text('[application]\n' + re.sub(r'^run/main_scene=.*\n', '', application, flags=re.M)
            + (('[threading]\n' + threading.group(1)) if threading else ''), encoding='utf-8')
        (probe / 'probe.gd').write_text(runner.PROBE_SCRIPT, encoding='utf-8')
        save(owner, manifest)
        env = environment(generated)
        cmd = [str(exe), '--headless', '--fixed-fps', '60', '--path', str(probe), '--script',
               'res://probe.gd', '--', token, 'main', str(generated)]
        out, err, code = runner.execute(cmd, env, generated, evidence, 'probe', budgets, manifest['processes'])
        manifest['physical_probes'] = runner.verify_probe(out, generated, token)
        save(owner, manifest)
        cmd = [str(exe), '--headless', '--fixed-fps', '60', '--editor', '--import', '--path', str(target)]
        out, err, code = runner.execute(cmd, env, generated, evidence, 'import', budgets, manifest['processes'])
        errors = re.findall(r'(?:SCRIPT ERROR|^\s*ERROR:).*', out + '\n' + err, re.M)
        manifest['import_errors'] = errors
        save(owner, manifest)
        (base / 'owner.txt').write_text(str(owner), encoding='utf-8')
        print('OWNER', owner, flush=True)
        if code or errors:
            print('IMPORT_FAILED', errors, flush=True)
            return 1
    else:
        owner = runner.contained(Path(args.owner), base)
        manifest = json.loads((owner / 'manifest.json').read_text(encoding='utf-8'))
        generated = Path(manifest['generated'])
        target = generated / 'project'
        evidence = owner / 'evidence'
        exe = generated / 'Godot.exe'
        env = environment(generated)
    stage = {'label': args.label, 'suites': [], 'compare': None}
    frozen_drift = [p for p,h in manifest['frozen_hashes'].items()
                    if p != REL and sha(target / p) != h]
    if frozen_drift:
        raise RuntimeError('frozen dependency drift: ' + repr(frozen_drift))
    if args.action == 'stage':
        shutil.copyfile(ROOT / REL, target / REL)
    stage['sha256'] = sha(target / REL)
    stage['production_sha256'] = sha(ROOT / REL)
    (evidence / (args.label + '.gd')).write_bytes((target / REL).read_bytes())
    manifest['stages'].append(stage)
    save(owner, manifest)
    for scene in SCENES + (EXTRA if args.final else []):
        label = args.label + '-' + Path(scene).stem
        cmd = [str(exe), '--headless', '--fixed-fps', '60', '--path', str(target), '--scene', 'res://' + scene]
        compare_path = evidence / (args.label + '-compare.json')
        if scene == SCENES[0]:
            cmd += ['--', str(compare_path)]
        out, err, code = runner.execute(cmd, env, generated, evidence, label, budgets, manifest['processes'])
        analysis = runner.analyze(out, err, code)
        errors = [x for x in (out + '\n' + err).splitlines() if re.search(r'SCRIPT ERROR|^\s*ERROR:', x)]
        receipt = {'scene': scene, 'analysis': analysis, 'errors': errors, 'exit': code,
                   'CHECK_count': len(re.findall(r'^CHECK\b', out, re.M)),
                   'Job0': manifest['processes'][-1]['active_owned_processes'] == 0}
        stage['suites'].append(receipt)
        save(owner, manifest)
        print(args.label, scene, json.dumps(receipt, ensure_ascii=False), flush=True)
        if not analysis['passed'] or not receipt['Job0']:
            return 1
    if args.label != 'baseline':
        before = json.loads((evidence / 'baseline-compare.json').read_text(encoding='utf-8'))
        after = json.loads(compare_path.read_text(encoding='utf-8'))
        mismatch = [a['case'] for a,b in zip(before, after) if a != b]
        stage['compare'] = {'cases': len(after), 'same_count': len(before) == len(after),
            'baseline_equal': before == after, 'mismatches': mismatch,
            'baseline_sha256': sha(evidence / 'baseline-compare.json'), 'after_sha256': sha(compare_path)}
        if len(manifest['stages']) > 1:
            previous = manifest['stages'][-2]['label']
            old = json.loads((evidence / (previous + '-compare.json')).read_text(encoding='utf-8'))
            stage['compare']['previous_equal'] = old == after
        print('COMPARE', json.dumps(stage['compare'], ensure_ascii=False), flush=True)
    stage['passed'] = all(r['analysis']['passed'] and r['Job0'] for r in stage['suites']) and (
        stage['compare'] is None or stage['compare']['baseline_equal'])
    manifest['production_drift_observed'] = [p for p,h in manifest['source_hashes'].items()
        if p != REL and sha(ROOT / p) != h]
    manifest['passed'] = all(s.get('passed', False) for s in manifest['stages'])
    save(owner, manifest)
    print('MANIFEST', owner / 'manifest.json', flush=True)
    return 0 if stage['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
