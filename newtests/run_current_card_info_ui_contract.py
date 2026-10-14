"""Owned headless freeze for declared card backs; never runs GUI scenes."""
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
SCENES = ['current_card_info_ui_contract_test', 'round70_declared_card_backs_test', 'shared_spell_view_contract_test']
OWNED = ['scripts/match/view_builder.gd', 'scripts/match/view_mirror.gd',
         'scripts/ui/text/card_desc_text.gd', 'scripts/game_scene/battle_board_v2.gd',
         'newtests/current_card_info_ui_contract_test.gd', 'newtests/current_card_info_ui_contract_test.tscn']
def scene_path(scene, suffix):
    return ('newtests/' if scene == 'current_card_info_ui_contract_test' else 'tests/') + scene + suffix

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    obj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj

r = module('round70_isolated', REPO / 'tools/run_isolated_godot_test.py')
e = module('round70_evidence', REPO / 'tools/tests/test_round29_integrated_evidence.py')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def dependency_files(scenes):
    # Follow declared script classes and explicit load/preload/extends resources;
    # dynamic rule operations are the one explicit directory-level dependency.
    sources = r.source_files(REPO, ['scripts','addons','json_maker'])
    texts = {p:(REPO/p).read_text(encoding='utf-8-sig') for p in sources if p.suffix=='.gd'}
    classes = {}
    for p,text in texts.items():
        match = re.search(r'(?m)^class_name\s+(\w+)',text)
        if match: classes[match[1]] = p
    config = (REPO/'project.godot').read_text(encoding='utf-8-sig')
    auto = re.search(r'^\[autoload\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)[1]
    todo = [Path(x) for x in re.findall(r'res://([^"\n]+)',auto)]
    for scene in scenes: todo += [Path(scene_path(scene,'.gd')),Path(scene_path(scene,'.tscn'))]
    todo += [p for p in sources if p.as_posix().startswith('scripts/system/operations/')]
    selected = set()
    while todo:
        p = todo.pop()
        if p in selected: continue
        if not (REPO/p).is_file(): raise ValueError('missing explicit dependency: '+str(p))
        selected.add(p)
        if p.suffix not in ['.gd','.tscn','.tres']: continue
        text = texts.get(p)
        if text is None: text = (REPO/p).read_text(encoding='utf-8-sig')
        if p.suffix == '.gd':
            todo += [classes[x] for x in set(re.findall(r'\b[A-Za-z_]\w*\b',text)) & classes.keys()]
            resources = re.findall(r'(?:preload\s*\(|load\s*\(|extends\s+)["\']res://([^"\']+)',text)
        else:
            resources = re.findall(r'path="res://([^"\n]+)"',text)
        todo += [Path(x) for x in resources]
    selected.update(r.source_files(REPO,['project.godot','assets/config','data','game_data',
                                          'addons','icon.svg','tests/network_test_port_fixture.gd']))
    for p in list(selected):
        for suffix in ['.import','.uid']:
            companion = Path(p.as_posix()+suffix)
            if (REPO/companion).is_file(): selected.add(companion)
    return sorted((p for p in selected if not (p.suffix=='.dll' and p.name.startswith('~'))),key=lambda p:p.as_posix())

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--label', required=True)
    parser.add_argument('--scenes', nargs='+', choices=SCENES, default=SCENES)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9-]+', args.label): raise ValueError('invalid label')
    parent = r.physical_e('E:/scratch') / ('current-card-info-' + args.label)
    parent.mkdir(exist_ok=True)
    token = uuid.uuid4().hex
    root = parent / ('isolated-' + token); root.mkdir()
    gen = root / 'generated'; gen.mkdir()
    evidence = root / 'evidence'; evidence.mkdir()
    target = gen / 'project'; target.mkdir()
    m = {'root':str(root), 'generated':str(gen), 'run_id':token, 'processes':[], 'suites':[], 'passed':False,
         'cleanup':'not_started', 'historical_probe_restored_from_message':165515, 'current_source_rerun':True, 'headless_only':True, 'no_user_pid_28100':True}
    budgets = {'seconds':600, 'bytes':8589934592, 'min_free':1073741824}
    env = os.environ.copy()
    for key in ['APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR']:
        folder = gen / key.lower(); folder.mkdir(); env[key] = str(folder)
    fixture = gen / 'fixtures'; fixture.mkdir()
    env['FATE_TEST_SCRATCH_ROOT'] = fixture.as_posix()
    env.pop('HERMES_RECOVERY_VALIDATION_ROOT', None)
    m['environment'] = {key:env[key] for key in ['APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR']}
    files = []
    try:
        files = dependency_files(args.scenes)
        before = {p.as_posix():sha(REPO/p) for p in files}
        for p in files:
            dest = target/p; dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(REPO/p,dest)
            if sha(dest) != before[p.as_posix()]: raise ValueError('freeze copy drift: '+p.as_posix())
        m['source_hashes'] = before
        m['owned_hashes'] = {p:sha(REPO/p) for p in OWNED}
        m['runner_hashes'] = {p.relative_to(REPO).as_posix():sha(p) for p in [Path(__file__),REPO/'tools/run_isolated_godot_test.py',REPO/'tools/tests/test_round29_integrated_evidence.py']}
        config, transform = e.transform_isolated_editor_vcs((target/'project.godot').read_text(encoding='utf-8-sig'))
        config = re.sub(r'(?m)^run/main_scene(?:\.fate_server)?=.*\n?', '', config)
        (target/'project.godot').write_text(config,encoding='utf-8')
        m['editor_transform'] = transform
        m['test_entry_transform'] = 'remove non-included main scenes; every run supplies explicit --scene'
        if 'worker_pool/max_threads=20' not in config: raise ValueError('pool20 required')
        cfg = (target/'assets/config/server.cfg').read_text(encoding='utf-8-sig')
        if not re.search(r'(?m)^random_sim_budget_sec\s*=\s*15(?:\.0)?\s*$', cfg): raise ValueError('budget15 required')
        frozen = {p.as_posix():sha(target/p) for p in files}
        engine_source = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
        engine = gen/'Godot.exe'; shutil.copyfile(engine_source,engine)
        m['engine_sha256'] = sha(engine)
        if sha(engine_source) != m['engine_sha256']: raise ValueError('engine copy drift')
        probe = gen/'probe'; probe.mkdir()
        app = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)[1]
        threads = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)[1]
        (probe/'project.godot').write_text('config_version=5\n[application]\n'+app+'\n[threading]\n'+threads,encoding='utf-8')
        (probe/'probe.gd').write_text(r.PROBE_SCRIPT,encoding='utf-8')
        out,err,code = r.execute([str(engine),'--headless','--path',str(probe),'--script','res://probe.gd','--',token,'main',str(gen)],env,gen,evidence,'probe',budgets,m['processes'])
        if code or re.search(r'SCRIPT ERROR|ERROR:',out+err): raise ValueError('physical E probe failed')
        m['physical_probes'] = r.verify_probe(out,gen,token)
        out,err,code = r.execute([str(engine),'--headless','--editor','--import','--path',str(target)],env,gen,evidence,'import',budgets,m['processes'])
        if code or re.search(r'SCRIPT ERROR|ERROR:',out+err): raise ValueError('import failed')
        for scene in args.scenes:
            cmd = [str(engine),'--headless','--fixed-fps','60','--path',str(target),'--scene','res://'+scene_path(scene,'.tscn')]
            out,err,code = r.execute(cmd,env,gen,evidence,scene,budgets,m['processes'])
            item = {'scene':scene,'command':cmd,'exit_code':code,'analysis':r.analyze(out,err,code)}
            m['suites'].append(item)
            samples = [json.loads(line.split('DECLARED_BACK_SAMPLES ',1)[1]) for line in out.splitlines() if line.startswith('DECLARED_BACK_SAMPLES ')]
            if samples: m['samples'] = samples[0]
            for key in ['CARD_INFO_INVENTORY','CARD_INFO_GAPS']:
                rows = [json.loads(line.split(key+' ',1)[1]) for line in out.splitlines() if line.startswith(key+' ')]
                if rows:
                    m[key.lower()] = rows[0]
                    (evidence/(key.lower()+'.json')).write_text(json.dumps(rows[0],ensure_ascii=False,indent=2),encoding='utf-8')
            print(json.dumps(item,ensure_ascii=False),flush=True)
        m['owned_source_drift'] = {p:[value,sha(REPO/p)] for p,value in m['owned_hashes'].items() if sha(REPO/p)!=value}
        m['source_drift'] = {p:[value,sha(REPO/p)] for p,value in before.items() if sha(REPO/p)!=value}
        m['freeze_drift'] = {p:[value,sha(target/p)] for p,value in frozen.items() if sha(target/p)!=value and p != 'data/tag_list.json'}
        m['passed'] = len(m['suites'])==len(args.scenes) and all(x['analysis']['passed'] for x in m['suites']) and not m['owned_source_drift'] and not m['freeze_drift'] and not m['source_drift']
    except Exception as exc:
        m['error'] = repr(exc)
    finally:
        archive = evidence/'owned-inputs'; archive.mkdir()
        for p in OWNED:
            if (target/p).exists():
                dest=archive/p;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(target/p,dest)
        logs = gen/'appdata/FateDomination/logs'
        if logs.exists(): shutil.copytree(logs,evidence/'engine-logs')
        m['log_diagnostics'] = [{'path':p.relative_to(evidence).as_posix(),'errors':len(re.findall(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',p.read_text(encoding='utf-8'),re.M)),'warnings':len(re.findall(r'^\s*WARNING:',p.read_text(encoding='utf-8'),re.M))} for p in evidence.rglob('*.log')]
        m['clean_error_warning_gate'] = all(x['errors']==0 and x['warnings']==0 for x in m['log_diagnostics'])
        m['passed'] = m['passed'] and m['clean_error_warning_gate']
        m['artifacts'] = [{'path':p.relative_to(evidence).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size} for p in evidence.rglob('*') if p.is_file()]
        m['artifact_readback'] = all(sha(evidence/x['path'])==x['sha256'] for x in m['artifacts'])
        (root/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
        if all(x.get('exited') and x.get('active_owned_processes')==0 for x in m['processes']) and m['artifact_readback']:
            r.delete_owned(gen,root);m['cleanup']='generated_removed'
        (root/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps({'manifest':str(root/'manifest.json'),'passed':m['passed'],'error':m.get('error'),'cleanup':m['cleanup'],'artifact_readback':m['artifact_readback']},ensure_ascii=False),flush=True)
    return 0 if m['passed'] else 1

if __name__ == '__main__': raise SystemExit(main())