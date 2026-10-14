"""Move only RegularPlay's three script mappings into AllOperations.
Reuse a verified prior frozen dependency allowlist, never the live hot files.
Run both source-pair variants in one owned E-drive tree; retain raw evidence.
"""
from pathlib import Path
import argparse
import difflib
import hashlib
import importlib.util
import json
import os
import re
import shutil
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('compare_runner', ROOT / 'newtools/run_regular_play_existing_ops_compare.py')
compare_runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compare_runner)
runner = compare_runner.runner
PAIR = ['scripts/system/regular_play.gd', 'scripts/system/global/all_operations.gd']
QUERY = 'newtests/regular_play_registry_query_test.tscn'
QUERY_FILES = [QUERY, 'newtests/regular_play_registry_query_test.gd']
EXPECTED = [75, 54, 219, 9, 18, 25, 22, 45]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resume_query(owner, base, seed_owner, before):
    """Resume only the label-corrected query; preserve all prior raw logs and gates."""
    manifest_path = owner / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    generated = runner.contained(Path(manifest['generated']), owner)
    target = generated / 'project'
    evidence = owner / 'evidence'
    if any(p.get('exited') is not True or p.get('active_owned_processes') != 0 for p in manifest['processes']):
        raise RuntimeError('previous owned Job not empty')
    if len(manifest['stages']) != 2 or any(len(s['suites']) != 8 for s in manifest['stages']):
        raise RuntimeError('expected both complete eight-suite variants')
    for stage in manifest['stages']:
        if [r['CHECK'] for r in stage['suites']] != EXPECTED or not all(r['passed'] for r in stage['suites']):
            raise RuntimeError('prior eight-suite gate failed')
    for rel,h in manifest['frozen_hashes'].items():
        expected = manifest['source_pair'][rel]['after'] if rel in PAIR else h
        if sha(target / rel) != expected:
            raise RuntimeError('resume frozen drift: ' + rel)
    for rel in PAIR:
        if sha(ROOT / rel) != manifest['source_pair'][rel]['after']:
            raise RuntimeError('live source pair changed: ' + rel)
    old_log = (evidence / 'registry-regular_play_registry_query_test.stdout.log').read_text(encoding='utf-8')
    old_err = (evidence / 'registry-regular_play_registry_query_test.stderr.log').read_text(encoding='utf-8')
    manifest['prior_query_parser_rejection'] = runner.analyze(old_log, old_err, 0)
    rel = QUERY_FILES[1]
    old_source = (target / rel).read_text(encoding='utf-8')
    new_source = (ROOT / rel).read_text(encoding='utf-8')
    if old_source.replace('"remove returns true"', '"remove returns true value"').replace('"missing remove returns false"', '"missing remove returns false value"') != new_source:
        raise RuntimeError('resume only permits the two label changes')
    (evidence / 'query-before-label-fix.gd').write_text(old_source, encoding='utf-8')
    shutil.copyfile(ROOT / rel, target / rel)
    manifest['frozen_hashes'][rel] = sha(target / rel)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    cmd = [str(generated / 'Godot.exe'), '--headless','--fixed-fps','60','--path',str(target),'--scene','res://' + QUERY]
    out, err, code = runner.execute(cmd, compare_runner.environment(generated), generated, evidence,
                                    'registry-query-label-fixed', manifest['budgets'], manifest['processes'])
    analysis = runner.analyze(out, err, code)
    result = {'scene':QUERY, 'argv':cmd, 'exit':code, 'analysis':analysis,
              'CHECK':len(re.findall(r'^CHECK\b', out, re.M)), 'expected_CHECK':29,
              'ERROR':[x for x in (out + '\n' + err).splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:', x)],
              'Job0':manifest['processes'][-1]['active_owned_processes'] == 0}
    result['passed'] = analysis['passed'] and result['CHECK'] == 29 and result['Job0']
    manifest['stages'][-1]['suites'].append(result)
    manifest['stages'][-1]['pair_hashes'] = {rel:sha(target / rel) for rel in PAIR}
    b = (evidence / 'baseline-compare.json').read_bytes()
    a = (evidence / 'registry-compare.json').read_bytes()
    manifest['compare'] = {'byte_equal':b == a, 'cases':len(json.loads(a)),
                           'before_sha256':sha(evidence / 'baseline-compare.json'),
                           'after_sha256':sha(evidence / 'registry-compare.json')}
    seed = json.loads((seed_owner / 'manifest.json').read_text(encoding='utf-8'))
    manifest['live_dependency_drift'] = [rel for rel,h in seed['source_hashes'].items() if rel not in PAIR and sha(ROOT / rel) != h]
    manifest['live_pair_unchanged_since_snapshot'] = all(sha(ROOT / rel) == manifest['source_pair'][rel]['after'] for rel in PAIR)
    diff = ''.join(''.join(difflib.unified_diff((before / Path(rel).name).read_text(encoding='utf-8').splitlines(True), (ROOT / rel).read_text(encoding='utf-8').splitlines(True), fromfile='before/' + rel, tofile='after/' + rel)) for rel in PAIR)
    (evidence / 'minimal.diff').write_text(diff, encoding='utf-8')
    manifest['passed'] = result['passed'] and manifest['compare']['byte_equal'] and manifest['compare']['cases'] == 25 and manifest['live_pair_unchanged_since_snapshot']
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    (base / 'owner.txt').write_text(str(owner), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False), flush=True)
    print('COMPARE', json.dumps(manifest['compare']), flush=True)
    print('MANIFEST', manifest_path, flush=True)
    return 0 if manifest['passed'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--seed-owner', required=True)
    parser.add_argument('--before', required=True)
    parser.add_argument('--resume-owner')
    args = parser.parse_args()
    base = runner.physical_e(Path(args.base))
    seed_owner = runner.physical_e(Path(args.seed_owner))
    seed = json.loads((seed_owner / 'manifest.json').read_text(encoding='utf-8'))
    seed_generated = runner.contained(Path(seed['generated']), seed_owner)
    seed_project = seed_generated / 'project'
    before = runner.physical_e(Path(args.before))
    if args.resume_owner:
        return resume_query(runner.contained(Path(args.resume_owner), base), base, seed_owner, before)
    token = uuid.uuid4().hex
    owner = base / ('isolated-' + token)
    generated = owner / 'generated'
    target = generated / 'project'
    evidence = owner / 'evidence'
    for path in (generated, target, evidence):
        path.mkdir(parents=True, exist_ok=True)
    budgets = {'seconds':600, 'bytes':2147483648, 'min_free':1073741824}
    manifest = {'run_id':token, 'generated':str(generated), 'processes':[], 'budgets':budgets,
                'seed_owner':str(seed_owner), 'variant_files':PAIR, 'stages':[],
                'frozen_hashes':{}, 'source_pair':{}, 'scope':'prior frozen dependencies, not current hot tree'}

    def save():
        (owner / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')

    for rel, expected in seed['frozen_hashes'].items():
        src = runner.contained(seed_project / rel, seed_project)
        if rel == PAIR[0]:
            expected = seed['stages'][-1]['sha256']
        if sha(src) != expected:
            raise RuntimeError('seed frozen drift: ' + rel)
        dst = target / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        if sha(dst) != expected or sha(src) != expected:
            raise RuntimeError('seed changed while copied: ' + rel)
        manifest['frozen_hashes'][rel] = expected
    for rel in PAIR:
        old = before / Path(rel).name
        if sha(old) != manifest['frozen_hashes'][rel]:
            raise RuntimeError('live pre-edit pair does not match seed final pair: ' + rel)
        manifest['source_pair'][rel] = {'before':sha(old), 'after':sha(ROOT / rel)}
        (evidence / ('before-' + Path(rel).name)).write_bytes(old.read_bytes())
        (evidence / ('after-' + Path(rel).name)).write_bytes((ROOT / rel).read_bytes())
    exe = generated / 'Godot.exe'
    shutil.copyfile(seed_generated / 'Godot.exe', exe)
    if sha(exe) != seed['engine_sha256']:
        raise RuntimeError('engine SHA mismatch')
    manifest['engine_sha256'] = sha(exe)
    env = compare_runner.environment(generated)
    application = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)', (target / 'project.godot').read_text(encoding='utf-8-sig'), re.M | re.S).group(1)
    threading = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)', (target / 'project.godot').read_text(encoding='utf-8-sig'), re.M | re.S)
    probe = generated / 'probe'
    probe.mkdir()
    (probe / 'project.godot').write_text('[application]\n' + re.sub(r'^run/main_scene=.*\n', '', application, flags=re.M) + ('[threading]\n' + threading.group(1) if threading else ''), encoding='utf-8')
    probe_script = runner.PROBE_SCRIPT.replace('["--headless", "--path",', '["--headless", "--fixed-fps", "60", "--path",').replace('> 15000', '> 600000')
    (probe / 'probe.gd').write_text(probe_script, encoding='utf-8')
    save()

    def execute(label, suffix, expected_checks=None):
        cmd = [str(exe), '--headless', '--fixed-fps', '60', *suffix]
        out, err, code = runner.execute(cmd, env, generated, evidence, label, budgets, manifest['processes'])
        receipt = {'label':label, 'argv':cmd, 'exit':code, 'Job0':manifest['processes'][-1]['active_owned_processes'] == 0,
                   'ERROR':[x for x in (out + '\n' + err).splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:', x)],
                   'CHECK':len(re.findall(r'^CHECK\b', out, re.M))}
        if expected_checks is not None:
            receipt['analysis'] = runner.analyze(out, err, code)
            receipt['expected_CHECK'] = expected_checks
            receipt['passed'] = receipt['analysis']['passed'] and receipt['CHECK'] == expected_checks and receipt['Job0']
        else:
            receipt['passed'] = code == 0 and not receipt['ERROR'] and receipt['Job0']
        save()
        print(json.dumps(receipt, ensure_ascii=False), flush=True)
        if not receipt['passed']:
            raise RuntimeError('stage failed: ' + label)
        return out, receipt

    out, receipt = execute('probe', ['--path',str(probe),'--script','res://probe.gd','--',token,'main',str(generated)])
    manifest['physical_probes'] = runner.verify_probe(out, generated, token)
    manifest['probe'] = receipt
    _, manifest['baseline_import'] = execute('baseline-import', ['--editor','--import','--path',str(target)])
    save()
    scenes = compare_runner.SCENES + compare_runner.EXTRA
    for stage_name in ['baseline', 'registry']:
        if stage_name == 'registry':
            # Only these two authorized variant files may change. Every other frozen input stays strict.
            for rel in PAIR:
                if sha(target / rel) != manifest['source_pair'][rel]['before']:
                    raise RuntimeError('unexpected baseline pair drift: ' + rel)
                shutil.copyfile(evidence / ('after-' + Path(rel).name), target / rel)
            for rel in QUERY_FILES:
                dst = target / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / rel, dst)
                manifest['frozen_hashes'][rel] = sha(dst)
            _, manifest['registry_import'] = execute('registry-import', ['--editor','--import','--path',str(target)])
        stage = {'label':stage_name, 'suites':[]}
        manifest['stages'].append(stage)
        for scene, expected in zip(scenes + ([QUERY] if stage_name == 'registry' else []), EXPECTED + ([29] if stage_name == 'registry' else [])):
            compare_path = evidence / (stage_name + '-compare.json')
            suffix = ['--path',str(target),'--scene','res://' + scene]
            if scene == scenes[0]:
                suffix += ['--', str(compare_path)]
            _, result = execute(stage_name + '-' + Path(scene).stem, suffix, expected)
            result['scene'] = scene
            stage['suites'].append(result)
            save()
        drift = [rel for rel,h in manifest['frozen_hashes'].items() if rel not in PAIR and sha(target / rel) != h]
        if drift:
            raise RuntimeError('unchanged dependency drift: ' + repr(drift))
        stage['pair_hashes'] = {rel:sha(target / rel) for rel in PAIR}
        save()
    baseline_bytes = (evidence / 'baseline-compare.json').read_bytes()
    after_bytes = (evidence / 'registry-compare.json').read_bytes()
    manifest['compare'] = {'byte_equal':baseline_bytes == after_bytes,
                           'cases':len(json.loads(after_bytes)),
                           'before_sha256':sha(evidence / 'baseline-compare.json'),
                           'after_sha256':sha(evidence / 'registry-compare.json')}
    manifest['live_pair_unchanged_since_snapshot'] = all(sha(ROOT / rel) == manifest['source_pair'][rel]['after'] for rel in PAIR)
    manifest['live_dependency_drift'] = [rel for rel,h in seed['source_hashes'].items() if rel not in PAIR and sha(ROOT / rel) != h]
    diff = ''.join(''.join(difflib.unified_diff((before / Path(rel).name).read_text(encoding='utf-8').splitlines(True), (ROOT / rel).read_text(encoding='utf-8').splitlines(True), fromfile='before/' + rel, tofile='after/' + rel)) for rel in PAIR)
    (evidence / 'minimal.diff').write_text(diff, encoding='utf-8')
    manifest['passed'] = manifest['compare']['byte_equal'] and manifest['compare']['cases'] == 25 and manifest['live_pair_unchanged_since_snapshot']
    save()
    (base / 'owner.txt').write_text(str(owner), encoding='utf-8')
    print('MANIFEST', owner / 'manifest.json', flush=True)
    return 0 if manifest['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
