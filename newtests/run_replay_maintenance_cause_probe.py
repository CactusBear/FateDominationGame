"""Exact-source Godot cancellation seam, not a complete match replay acceptance."""
import sys
sys.dont_write_bytecode = True
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import uuid

ROOT = Path(__file__).resolve().parents[1]
ENGINE_SOURCE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
SOURCES = ['scripts/match/match_replay.gd', 'scripts/match/match_journal.gd',
           'scripts/match/rule_random.gd', 'tests/match_replay_diagnostic_fixture.gd',
           'tests/match_replay_test.gd', 'tests/match_replay_profile_fixture.gd',
           'newtests/replay_maintenance_cause_probe.gd']

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def function(text, name):
    match = re.search(r'(?m)^func ' + re.escape(name) + r'\(', text)
    if match is None:
        raise ValueError('Missing function: ' + name)
    end = re.search(r'(?m)^func ', text[match.end():])
    finish = match.end() + end.start() if end else len(text)
    # Trim only blank lines/comments before the following function, not its body.
    lines = text[match.start():finish].splitlines(keepends=True)
    while lines and (not lines[-1].strip() or lines[-1].startswith('#')):
        lines.pop()
    body = ''.join(lines)
    return body + '\n', text[:match.start()].count('\n') + 1

def main():
    spec = importlib.util.spec_from_file_location('owned', ROOT/'tools/run_isolated_godot_test.py')
    owned = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(owned)
    token = uuid.uuid4().hex
    owner = owned.physical_e(Path('E:/scratch')) / ('isolated-' + token)
    generated = owner/'generated'
    project = generated/'project'
    evidence = owner/'evidence'
    project.mkdir(parents=True)
    evidence.mkdir()
    report = {'run_id':token, 'generated':str(generated), 'processes':[], 'passed':False,
              'protected_pids':[17120,28100], 'scope':'exact source cancellation seam only',
              'source_hashes':{name:sha(ROOT/name) for name in SOURCES}, 'slices':[]}
    manifest = owner/'manifest.json'
    def save():
        manifest.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    save()
    try:
        replay_text = (ROOT/SOURCES[0]).read_text(encoding='utf-8')
        header = '''extends RefCounted
const Journal = preload("res://scripts/match/match_journal.gd")
const RuleRandom = preload("res://scripts/match/rule_random.gd")
const EffectManager = preload("res://effect_manager_seam_stub.gd")
var error:String = ""
var error_index:int = -1
var _entropy = RandomNumberGenerator.new()
const MAINTENANCE_CHUNK_BYTES:int = 256 * 1024
'''
        bodies = []
        for name in ['_confirm_audit', '_checkpoint', '_maintenance_callback', '_tick', '_file_hash']:
            body, line = function(replay_text, name)
            bodies.append(body)
            report['slices'].append({'source':SOURCES[0], 'function':name, 'line':line,
                                     'sha256':hashlib.sha256(body.encode()).hexdigest()})
        (project/'replay_seam.gd').write_text(header + '\n'.join(bodies), encoding='utf-8')
        diagnostic_text = (ROOT/SOURCES[3]).read_text(encoding='utf-8')
        body, line = function(diagnostic_text, 'maintain')
        diagnostic = '''extends RefCounted
static var deadline:int = 0
var replay = null
var last_index:int = -2
func trace(stage:String) -> void:
\tprint("CAUSE_TRACE ", JSON.stringify({"stage":stage,"ms":Time.get_ticks_msec(),"deadline":deadline,"expired":Time.get_ticks_msec() >= deadline,"index":replay.error_index,"stack":get_stack()}))
'''
        (project/'diagnostic_seam.gd').write_text(diagnostic + body, encoding='utf-8')
        report['slices'].append({'source':SOURCES[3], 'function':'maintain', 'line':line,
                                 'sha256':hashlib.sha256(body.encode()).hexdigest()})
        (project/'effect_manager_seam_stub.gd').write_text('''extends RefCounted
static func runtime_guard_effect(): return null
static func mark_guard_audit_failed(_effect) -> void:
    push_error("UNEXPECTED_AUDIT_FAILURE_BRANCH")
''', encoding='utf-8')
        for name in [SOURCES[1], SOURCES[2], SOURCES[6]]:
            dest = project/name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT/name, dest)
        (project/'project.godot').write_text('''config_version=5
[application]
config/name="ReplayMaintenanceCauseProbe"
[rendering]
renderer/rendering_method="gl_compatibility"
[threading]
worker_pool/max_threads=2
''', encoding='utf-8')
        engine = generated/'Godot.exe'
        shutil.copyfile(owned.no_links(ENGINE_SOURCE), engine)
        owned.physical_e(engine)
        report['engine_sha256'] = sha(engine)
        if report['engine_sha256'] != sha(ENGINE_SOURCE):
            raise RuntimeError('Engine copy digest mismatch')
        env = os.environ.copy()
        for key in list(env):
            if key.startswith(('FATE_', 'FD_', 'ROUND', 'HERMES_ASSEMBLY_')) or key == 'HERMES_RECOVERY_VALIDATION_ROOT':
                env.pop(key, None)
        for key in ['APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR']:
            location = generated/key.lower()
            location.mkdir()
            env[key] = str(location)
        budgets = {'seconds':600,'bytes':2*1024**3,'min_free':2*1024**3}
        report['budgets'] = budgets
        report['generated_hashes'] = {p.relative_to(project).as_posix():sha(p) for p in project.rglob('*') if p.is_file()}
        # Verify actual user-data location with same application/threading config,
        # including a real owned child, before the cancellation scene.
        probe = generated/'user-probe'
        probe.mkdir()
        shutil.copyfile(project/'project.godot', probe/'project.godot')
        (probe/'probe.gd').write_text(owned.PROBE_SCRIPT.replace('["--headless", "--path"', '["--headless", "--fixed-fps", "60", "--path"'), encoding='utf-8')
        out, err, code = owned.execute([str(engine),'--headless','--fixed-fps','60','--path',str(probe),'--script','res://probe.gd','--',token,'main',str(generated)], env, generated, evidence, 'user-probe', budgets, report['processes'])
        report['user_probe_exit'] = code
        if code or re.search(r'SCRIPT ERROR|^\s*ERROR:',out+'\n'+err,re.M):
            raise RuntimeError('User path probe failed')
        report['user_probes'] = owned.verify_probe(out, generated, token)
        save()
        out, err, code = owned.execute([str(engine),'--headless','--fixed-fps','60','--editor','--import','--path',str(project)], env, generated, evidence, 'import', budgets, report['processes'])
        report['import_exit'] = code
        if code or re.search(r'SCRIPT ERROR|^\s*ERROR:',out+'\n'+err,re.M):
            raise RuntimeError('Minimal import failed')
        command = [str(engine),'--headless','--fixed-fps','60','--path',str(project),'--script','res://newtests/replay_maintenance_cause_probe.gd']
        report['command'] = command
        out, err, code = owned.execute(command, env, generated, evidence, 'cause', budgets, report['processes'])
        report['exit'] = code
        report['analysis'] = owned.analyze(out, err, code)
        report['source_unchanged'] = all(sha(ROOT/name) == digest for name,digest in report['source_hashes'].items())
        report['observed_checks'] = len(re.findall(r'^CHECK ',out,re.M))
        report['expected_checks'] = 10
        user_paths = [line.removeprefix('USER_DATA_PATH ') for line in out.splitlines() if line.startswith('USER_DATA_PATH ')]
        if len(user_paths) != 1:
            raise RuntimeError('Missing unique user data path')
        owned.contained(owned.physical_e(Path(user_paths[0])), generated)
        report['actual_user_data_path'] = user_paths[0]
        report['Job0'] = bool(report['processes']) and all(p.get('exited') and p.get('active_owned_processes') == 0 and p.get('log_handles_released') for p in report['processes'])
        report['passed'] = report['analysis']['passed'] and report['source_unchanged'] and report['Job0'] and report['observed_checks'] == 10
        print(out, end='')
        print(err, end='', file=sys.stderr)
    except Exception as exc:
        report['error'] = repr(exc)
    finally:
        report['Job0'] = bool(report['processes']) and all(p.get('exited') and p.get('active_owned_processes') == 0 and p.get('log_handles_released') for p in report['processes'])
        report['artifact_hashes'] = {p.name:sha(p) for p in evidence.glob('*.log')}
        save()
        if report['Job0']:
            try:
                owned.delete_owned(generated, owner)
                report['cleanup'] = 'generated_removed'
            except Exception as exc:
                report['cleanup_error'] = repr(exc)
                report['passed'] = False
        else:
            report['cleanup'] = 'retained_without_Job0'
            report['passed'] = False
        save()
    print(json.dumps({'manifest':str(manifest),'exit':report.get('exit'),'passed':report['passed'],'Job0':report['Job0'],'error':report.get('error')},ensure_ascii=False))
    return 0 if report['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
