"""Single scoreboard headless closure; compare real pre/post renderer traces."""
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

REPO = Path(__file__).resolve().parents[1]
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
r = load('r74_isolation', REPO / 'tools/run_isolated_godot_test.py')
e = load('r74_transform', REPO / 'tools/tests/test_round29_integrated_evidence.py')
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--label', required=True)
    ap.add_argument('--compare', help='RED manifest whose renderer traces must match')
    args = ap.parse_args()
    if not re.fullmatch('[a-z0-9-]+', args.label): raise ValueError('bad label')
    parent = r.physical_e('E:/scratch') / ('round74-scoreboard-' + args.label)
    parent.mkdir(exist_ok=True)
    token = uuid.uuid4().hex
    root = parent / ('isolated-' + token)
    root.mkdir()
    gen = root / 'generated'; gen.mkdir()
    target = gen / 'project'; target.mkdir()
    evidence = root / 'evidence'; evidence.mkdir()
    env = os.environ.copy()
    for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR'):
        folder = gen / key.lower(); folder.mkdir(); env[key] = str(folder)
    fixtures = gen / 'fixtures'; fixtures.mkdir()
    env['FATE_TEST_SCRATCH_ROOT'] = str(fixtures)
    env.pop('HERMES_RECOVERY_VALIDATION_ROOT', None)
    m = {'root': str(root), 'run_id': token, 'generated': str(gen), 'suites': [], 'processes': [], 'passed': False,
         'boundary': 'headless logic only; no GUI, ENet, or performance claim', 'isolated_environment': {k:env[k] for k in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR')}}
    (root / 'manifest.json').write_text(json.dumps(m), encoding='utf-8')
    budgets = {'seconds': 180, 'bytes': 8589934592, 'min_free': 1073741824}
    files = []
    try:
        includes = ['project.godot', 'scripts', 'assets', 'data', 'game_data', 'addons', 'json_maker', 'icon.svg',
                    'newtests/round74_scoreboard_toggle_test.tscn', 'newtests/round74_scoreboard_toggle_test.gd']
        files = [p for p in r.source_files(REPO, includes) if not (p.suffix == '.dll' and p.name.startswith('~'))]
        before = {p.as_posix():sha(REPO / p) for p in files}
        for p in files:
            dest = target / p; dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / p, dest)
            if sha(dest) != before[p.as_posix()]: raise ValueError('freeze drift: ' + str(p))
        m['source_hashes'] = before
        config, transform = e.transform_isolated_editor_vcs((target / 'project.godot').read_text(encoding='utf-8-sig'))
        (target / 'project.godot').write_text(config, encoding='utf-8')
        m['editor_transform'] = transform
        frozen = {p.as_posix():sha(target / p) for p in files}
        engine_source = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
        engine = gen / 'Godot.exe'; shutil.copyfile(engine_source, engine)
        m['engine_sha256'] = sha(engine)
        probe = gen / 'probe'; probe.mkdir()
        app = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)', config, re.M | re.S)[1]
        threads = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)', config, re.M | re.S)[1]
        (probe / 'project.godot').write_text('config_version=5\n[application]\n'+app+'\n[threading]\n'+threads, encoding='utf-8')
        (probe / 'probe.gd').write_text(r.PROBE_SCRIPT, encoding='utf-8')
        out, err, code = r.execute([str(engine),'--headless','--path',str(probe),'--script','res://probe.gd','--',token,'main',str(gen)],env,gen,evidence,'probe',budgets,m['processes'])
        if code or re.search(r'SCRIPT ERROR|ERROR:',out+err): raise ValueError('probe failed')
        m['physical_probes'] = r.verify_probe(out,gen,token)
        out, err, code = r.execute([str(engine),'--headless','--editor','--import','--path',str(target)],env,gen,evidence,'import',budgets,m['processes'])
        if code or re.search(r'SCRIPT ERROR|ERROR:',out+err): raise ValueError('import failed')
        (target / 'tests/runtime_reports').mkdir(parents=True,exist_ok=True)
        scenes = ['newtests/round74_scoreboard_toggle_test.tscn']
        for scene in scenes:
            command = [str(engine),'--headless','--fixed-fps','60','--path',str(target),'--scene','res://'+scene]
            out, err, code = r.execute(command,env,gen,evidence,Path(scene).stem,budgets,m['processes'])
            record = {'scene':scene,'command':command,'exit_code':code,'analysis':r.analyze(out,err,code)}
            m['suites'].append(record)
            trace_lines = [line[6:] for line in out.splitlines() if line.startswith('TRACE ')]
            m['traces'] = json.loads(trace_lines[0]) if len(trace_lines) == 1 else None
            print(json.dumps(record,ensure_ascii=False),flush=True)
        if args.compare:
            baseline = Path(args.compare)
            previous = json.loads(baseline.read_text(encoding='utf-8'))
            m['comparison'] = {'baseline':str(baseline),'sha256':sha(baseline),
                               'matched':m['traces'] is not None and previous.get('traces') == m['traces'],
                               'trace_count':len(m['traces'] or [])}
        m['source_drift'] = {p.as_posix():[before[p.as_posix()],sha(REPO / p)] for p in files if sha(REPO / p) != before[p.as_posix()]}
        m['freeze_drift'] = {p.as_posix():[frozen[p.as_posix()],sha(target / p)] for p in files if sha(target / p) != frozen[p.as_posix()]}
        m['passed'] = all(x['analysis']['passed'] for x in m['suites']) and len(m['suites']) == len(scenes) and m.get('comparison',{'matched':True})['matched'] and not m['source_drift'] and not m['freeze_drift']
    except Exception as exc:
        m['error'] = repr(exc)
    finally:
        images = target / 'tests/runtime_reports'
        if images.exists(): shutil.copytree(images, evidence / 'screenshots')
        archive = evidence / 'frozen-inputs'; archive.mkdir()
        for p in files:
            if p.suffix in {'.gd','.tscn','.godot','.gdextension'}:
                dest = archive / p; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(target / p,dest)
        logs = gen / 'appdata/FateDomination/logs'
        if logs.exists(): shutil.copytree(logs,evidence / 'engine-logs')
        m['log_diagnostics'] = [{'path':p.relative_to(evidence).as_posix(),
            'errors':len(re.findall(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',p.read_text(encoding='utf-8'),re.M)),
            'warnings':len(re.findall(r'^\s*WARNING:',p.read_text(encoding='utf-8'),re.M))} for p in evidence.rglob('*.log')]
        m['clean_error_warning_gate'] = all(x['errors']==0 and x['warnings']==0 for x in m['log_diagnostics'])
        m['passed'] = m['passed'] and m['clean_error_warning_gate']
        m['artifacts'] = [{'path':p.relative_to(evidence).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size} for p in evidence.rglob('*') if p.is_file()]
        m['artifact_readback'] = all(sha(evidence / x['path'])==x['sha256'] for x in m['artifacts'])
        (root / 'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
        if all(x.get('exited') and x.get('active_owned_processes')==0 for x in m['processes']) and m['artifact_readback']:
            r.delete_owned(gen,root); m['cleanup'] = 'generated_removed'
        (root / 'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps({'manifest':str(root / 'manifest.json'),'passed':m['passed'],'error':m.get('error'),'cleanup':m.get('cleanup')},ensure_ascii=False),flush=True)
    return 0 if m['passed'] else 1
if __name__ == '__main__': raise SystemExit(main())
