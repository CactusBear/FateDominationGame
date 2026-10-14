"""Owned six-scene fixture migration receipts. Production/old runners read-only."""
import sys
sys.dont_write_bytecode = True
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import time
import uuid

PROJECT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('round60_readonly_evidence', PROJECT / 'tools/tests/test_round29_integrated_evidence.py')
evidence_api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence_api)
r = evidence_api.runner
NAMES = ['battle_board_end_command_test', 'round28-command-migration_test',
         'battle_board_activation_command_test', 'active_choice_source_command_test',
         'location_choice_source_command_test', 'player_choice_source_command_test']
OLD = Path('E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50')
ENGINE = Path('E:/scratch/round51-engine/Godot_v4.7.2-stable_win64.exe')
ROOT = Path('E:/scratch')

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def hashes(paths):
    return {x: evidence_api.digest(PROJECT / x) for x in sorted(paths)}

def dependencies(old):
    # Reuse the explicit approved production allowlist, not the old whole test set.
    paths = {x for x in old['freeze_before'] if not x.startswith('tests/')}
    # Current source additions must join this freeze; never silently use old deps.
    paths.update(x.relative_to(PROJECT).as_posix() for x in (PROJECT / 'scripts').rglob('*')
                 if x.is_file() and x.suffix in {'.gd', '.uid'})
    pending = ['tests/' + n + ext for n in NAMES for ext in ('.gd', '.tscn')]
    seen = set()
    while pending:
        name = pending.pop()
        if name in seen:
            continue
        seen.add(name)
        r.contained(PROJECT / name, PROJECT)
        paths.add(name)
        if Path(name).suffix in {'.gd', '.tscn'}:
            text = (PROJECT / name).read_text(encoding='utf-8-sig')
            pending.extend(x[6:] for x in re.findall(r'res://tests/[^"\s)]+', text))
    return paths

def execute(command, env, generated, evidence, label, manifest):
    return r.execute(command, env, generated, evidence, label,
                     {'seconds':180, 'bytes':8589934592, 'min_free':1073741824}, manifest['processes'])

def clean_generated(owner, m):
    # This runner owns a different UUID namespace; never change the old cleaner.
    owner = r.contained(owner, r.physical_e(ROOT))
    if not re.fullmatch(r'round60-fixture-[a-f0-9]{32}', owner.name):
        raise r.SafetyError('round60 ownership name mismatch')
    receipt = evidence_api.load(r.no_links(owner / 'owner.json'))
    generated = r.contained(owner / 'generated', owner)
    if receipt != {'token':owner.name, 'generated':str(generated)} or m.get('owner') != str(owner):
        raise r.SafetyError('round60 ownership receipt mismatch')
    if not m['processes'] or any(not x.get('exited') or x.get('active_owned_processes') != 0 or not x.get('log_handles_released') for x in m['processes']):
        raise r.SafetyError('round60 owned exit/handles unproven')
    for log in m['logs']:
        if evidence_api.digest(r.contained(owner / 'evidence' / log['path'], owner / 'evidence')) != log['sha256']:
            raise r.SafetyError('round60 archive drift')
    r.tree_bytes(generated)  # rejects every internal reparse point before deletion
    shutil.rmtree(generated)
    if generated.exists(): raise r.SafetyError('round60 generated removal unproven')
    m['cleanup'] = 'generated_removed'
    m['generated_exists_after_cleanup'] = False

def run():
    r.physical_e(ROOT)
    r.physical_e(ENGINE)
    old = evidence_api.load(OLD / 'manifest.json')
    if evidence_api.digest(ENGINE) != old['engine_sha256']:
        raise r.SafetyError('original engine mismatch')
    owner = ROOT / ('round60-fixture-' + uuid.uuid4().hex)
    owner.mkdir()
    generated, evidence = owner / 'generated', owner / 'evidence'
    generated.mkdir(); evidence.mkdir()
    m = {'selected':NAMES, 'suites':[], 'processes':[], 'passed':False,
         'owner':str(owner), 'old_manifest':str(OLD / 'manifest.json'),
         'old_manifest_sha256':evidence_api.digest(OLD / 'manifest.json'),
         'old_source_fingerprint':old['parent_source_fingerprint'],
         'engine_source':str(ENGINE), 'engine_sha256':evidence_api.digest(ENGINE),
         'cleanup':'not_started', 'timeout_seconds':180, 'fixed_fps':60}
    save(owner / 'owner.json', {'token':owner.name, 'generated':str(generated)})
    try:
        paths = dependencies(old)
        before = hashes(paths)
        m['source_hashes'] = before
        m['source_fingerprint'] = evidence_api.round50_source_fingerprint(before)
        m['old_new_test_hashes'] = {n:{'old':old['freeze_before']['tests/'+n+'.gd'],
                                   'new':before['tests/'+n+'.gd']} for n in NAMES}
        archived = evidence / 'inputs'
        for name in paths:
            src = r.contained(PROJECT / name, PROJECT)
            dst = generated / 'project' / name
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
            if evidence_api.digest(dst) != before[name]:
                raise r.SafetyError('copy drift: ' + name)
            if src.suffix in {'.gd', '.tscn', '.godot', '.gdextension'}:
                archive = archived / name
                archive.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src, archive)
        m['old_red'] = []
        for name in NAMES:
            old_row = next(x for x in old['suites'] if x['suite'] == name)
            logs = {}
            for suffix in ('stdout.log', 'stderr.log'):
                path = OLD / 'evidence' / ('complete-' + name + '.' + suffix)
                logs[suffix] = {'path':str(path), 'sha256':evidence_api.digest(path)}
            m['old_red'].append({'suite':name,'exit':old_row['exit'],
                                 'firsterror':old_row['errors'][0], 'logs':logs})
        target = generated / 'project'
        config = (target / 'project.godot').read_text(encoding='utf-8-sig')
        if (PROJECT / 'override.cfg').exists() or 'config/project_settings_override=' in config:
            raise r.SafetyError('override unprobed')
        transformed, m['editor_transform'] = evidence_api.transform_isolated_editor_vcs(config)
        (target / 'project.godot').write_text(transformed, encoding='utf-8')
        m['frozen_hashes'] = {name:evidence_api.digest(target / name) for name in sorted(paths)}
        engine = generated / 'Godot.exe'
        shutil.copyfile(ENGINE, engine)
        if evidence_api.digest(engine) != m['engine_sha256']:
            raise r.SafetyError('engine copy mismatch')
        env = os.environ.copy()
        env['APPDATA'] = str(generated / 'appdata')
        env['LOCALAPPDATA'] = str(generated / 'localappdata')
        Path(env['APPDATA']).mkdir(); Path(env['LOCALAPPDATA']).mkdir()
        probe = generated / 'probe'; probe.mkdir()
        app = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)
        thread = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)
        probe_config = 'config_version=5\n[application]\n' + app[1]
        probe_config = re.sub(r'^run/main_scene=.*\n', '', probe_config, flags=re.M)
        if thread: probe_config += '\n[threading]\n' + thread[1]
        (probe / 'project.godot').write_text(probe_config,encoding='utf-8')
        (probe / 'probe.gd').write_text(r.PROBE_SCRIPT,encoding='utf-8')
        out, err, code = execute([str(engine),'--headless','--path',str(probe),'--script','res://probe.gd','--',owner.name,'main',str(generated)],env,generated,evidence,'probe',m)
        if code or re.search(r'SCRIPT ERROR|ERROR:',out+err): raise r.SafetyError('probe failed')
        m['user_probes'] = r.verify_probe(out,generated,owner.name)
        out,err,code = execute([str(engine),'--headless','--editor','--import','--path',str(target)],env,generated,evidence,'import',m)
        m['import'] = {'exit':code,'errors':[x for x in (out+err).splitlines() if re.search(r'SCRIPT ERROR|ERROR:',x)]}
        if code or m['import']['errors']: raise r.SafetyError('import failed')
        # Explicit instantiate loader: import exit0 alone is not a parser proof.
        loader = 'extends SceneTree\nfunc _initialize():\n'
        for name in NAMES:
            loader += '\tvar s_%d = load("res://tests/%s.gd")\n' % (NAMES.index(name),name)
            loader += '\tif s_%d == null or not s_%d.can_instantiate(): quit(1); return\n' % (NAMES.index(name),NAMES.index(name))
        loader += '\tprint("PARSER_LOADER actual6=true")\n\tquit(0)\n'
        (target / 'round60_loader.gd').write_text(loader,encoding='utf-8')
        out,err,code = execute([str(engine),'--headless','--path',str(target),'--script','res://round60_loader.gd'],env,generated,evidence,'parser',m)
        m['parser'] = {'exit':code,'errors':[x for x in (out+err).splitlines() if re.search(r'SCRIPT ERROR|ERROR:',x)]}
        if code or m['parser']['errors']: raise r.SafetyError('parser failed')
        for name in NAMES:
            current = hashes(paths)
            if current != before: raise r.SafetyError('current freeze drift before ' + name)
            fixture = generated / 'f' / name; fixture.mkdir(parents=True)
            scene_env = env.copy()
            scene_env['APPDATA'] = str(fixture / 'appdata')
            scene_env['LOCALAPPDATA'] = str(fixture / 'localappdata')
            scene_env['FATE_TEST_SCRATCH_ROOT'] = str(fixture)
            Path(scene_env['APPDATA']).mkdir(); Path(scene_env['LOCALAPPDATA']).mkdir()
            command = [str(engine),'--headless','--fixed-fps','60','--path',str(target),'--scene','res://tests/'+name+'.tscn']
            row = {'suite':name,'command':command,'fixture':str(fixture),'source_fingerprint':m['source_fingerprint']}
            try:
                out,err,code = execute(command,scene_env,generated,evidence,name,m)
            except Exception as exc:
                out = (evidence / (name+'.stdout.log')).read_text(encoding='utf-8')
                err = (evidence / (name+'.stderr.log')).read_text(encoding='utf-8')
                code = m['processes'][-1].get('exit_code')
                row['execution_error'] = str(exc)
            row.update(evidence_api.analyze(out,err,code))
            row['firsterror'] = next((x for x in (out+err).splitlines() if re.search(r'SCRIPT ERROR|ERROR:|^FAIL|^CHECK.* false$',x)),None)
            worker_errors = []
            for log in fixture.rglob('*.log'):
                contents = log.read_text(encoding='utf-8',errors='replace')
                matches = [x for x in contents.splitlines() if re.search(r'SCRIPT ERROR|ERROR:',x)]
                if matches: worker_errors.append({'path':str(log.relative_to(generated)), 'errors':matches})
                dest = evidence / 'worker' / log.relative_to(generated)
                dest.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(log,dest)
            row['worker_errors'] = worker_errors
            if worker_errors or row.get('execution_error'): row['passed'] = False
            m['suites'].append(row)
            save(owner / 'manifest.json',m)
            print(json.dumps({'suite':name,'passed':row['passed'],'checks':(row.get('result') or {}).get('checks'),'firsterror':row['firsterror']},ensure_ascii=False),flush=True)
        m['final_drift'] = [x for x,v in hashes(paths).items() if before.get(x) != v]
        m['frozen_drift'] = [x for x,v in m['frozen_hashes'].items() if evidence_api.digest(target/x) != v]
        m['engine_unchanged'] = evidence_api.digest(ENGINE) == m['engine_sha256'] == evidence_api.digest(engine)
        m['actual'] = len(m['suites']); m['unique'] = len({x['suite'] for x in m['suites']})
        m['passed'] = m['actual'] == m['unique'] == 6 and all(x['passed'] for x in m['suites']) and not m['final_drift'] and not m['frozen_drift'] and m['engine_unchanged']
    except Exception as exc:
        m['error'] = type(exc).__name__ + ': ' + str(exc)
    finally:
        m['logs'] = [{'path':str(x.relative_to(evidence)), 'sha256':evidence_api.digest(x)} for x in evidence.rglob('*.log')]
        save(owner / 'manifest.json',m)
        if all(x.get('exited') and x.get('active_owned_processes') == 0 and x.get('log_handles_released') for x in m['processes']):
            clean_generated(owner,m)
        else:
            m['cleanup'] = 'retained_process_exit_unproven'; m['passed'] = False
        m['old_logs_unchanged'] = all(evidence_api.digest(Path(log['path'])) == log['sha256'] for row in m.get('old_red',[]) for log in row['logs'].values())
        save(owner / 'manifest.json',m)
        print(json.dumps({'passed':m['passed'],'manifest':str(owner/'manifest.json'),'error':m.get('error'),'cleanup':m['cleanup']},ensure_ascii=False),flush=True)
    return 0 if m['passed'] else 1

def finalize_owned(manifest_path):
    path = r.contained(Path(manifest_path), r.physical_e(ROOT))
    owner = path.parent
    m = evidence_api.load(path)
    if path.name != 'manifest.json' or (owner / 'pre-cleanup-manifest.json').exists():
        raise r.SafetyError('finalize requires original unfinalized manifest')
    shutil.copyfile(path, owner / 'pre-cleanup-manifest.json')
    m['initial_runner_issue'] = 'exit1: old delete_owned rejected round60 ownership namespace; all six scenes had already run'
    before = m['source_hashes']
    current = hashes(before)
    m['finalize_current_drift'] = [x for x,v in current.items() if before[x] != v]
    if m['finalize_current_drift']: raise r.SafetyError('finalize current source drift')
    m['old_logs_unchanged'] = all(evidence_api.digest(Path(log['path'])) == log['sha256'] for row in m['old_red'] for log in row['logs'].values())
    if not m['old_logs_unchanged']: raise r.SafetyError('old logs changed')
    clean_generated(owner,m)
    m['finalization_only_no_scene_rerun'] = True
    save(path,m)
    print(json.dumps({'passed':m['passed'],'actual':m['actual'],'unique':m['unique'],'cleanup':m['cleanup'],'old_logs_unchanged':m['old_logs_unchanged'],'manifest':str(path)},ensure_ascii=False))
    return 0 if m['passed'] else 1

if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--finalize-owned':
        raise SystemExit(finalize_owned(sys.argv[2]))
    if len(sys.argv) != 1: raise SystemExit('Only --finalize-owned <exact manifest> is supported')
    raise SystemExit(run())
