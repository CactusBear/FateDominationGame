"""Four real rule command cases; frozen inputs, E-only IO, owned Job, 900s watchdog."""
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
SUITE = 'newtests/choice_submit_real_execution_test.gd'
SCENE = 'newtests/choice_submit_real_execution_test.tscn'
KINDS = ('player_choice', 'option_choice', 'cancel_choice', 'confirm_broadcast')
AUTOLOADS = {
    'GameData': 'scripts/system/global/game_data.gd',
    'GameStart': 'scripts/main_menu/game_start.gd',
    'MasterManager': 'scripts/system/global/master_manager.gd',
    'ServantManager': 'scripts/system/global/servant_manager.gd',
    'GameDataManager': 'scripts/system/global/game_data_manager.gd',
    'TimePointChecker': 'scripts/system/global/time_point_checker.gd',
    'LoadGame': 'scripts/system/global/load_game.gd',
    'MapData': 'scripts/system/map_data.gd',
    'GameProgress': 'scripts/system/global/game_progress.gd',
    'EffectManager': 'scripts/system/global/effect_manager.gd',
}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def dependencies():
    texts = {p.relative_to(REPO).as_posix(): p.read_text(encoding='utf-8-sig')
             for p in (REPO / 'scripts').rglob('*.gd')}
    classes = {}
    for name, text in texts.items():
        match = re.search(r'^class_name\s+(\w+)', text, re.M)
        if match:
            if match[1] in classes:
                raise ValueError('duplicate class: ' + match[1])
            classes[match[1]] = name
    pending = [SUITE, SCENE, *AUTOLOADS.values()]
    # JSON func_name is dynamically loaded by the real loader; explicitly include all operations.
    pending += [p.relative_to(REPO).as_posix() for p in (REPO / 'scripts/system/operations').glob('*.gd')]
    pending += [p.relative_to(REPO).as_posix() for p in (REPO / 'data').rglob('*.json')]
    pending += [p.relative_to(REPO).as_posix() for p in (REPO / 'assets/config').glob('*') if p.is_file()]
    found = set()
    while pending:
        name = pending.pop()
        if name in found:
            continue
        found.add(name)
        path = REPO / name
        if path.suffix not in {'.gd', '.tscn', '.tres', '.gdshader', '.gdextension'}:
            continue
        text = texts.get(name) or path.read_text(encoding='utf-8-sig')
        if path.suffix == '.gd':
            pending += [classes[token] for token in set(re.findall(r'\b[A-Za-z_]\w*\b', text)) if token in classes]
        for resource in re.findall(r'"res://([^"\n]+)"', text):
            if (REPO / resource).is_file():
                pending.append(resource)
    return sorted(found)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--kind', choices=KINDS, action='append')
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('isolated_choice_job', REPO / 'tools/run_isolated_godot_test.py')
    isolated = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(isolated)
    root = isolated.physical_e(args.root)
    engine = isolated.physical_e(args.godot)
    token = uuid.uuid4().hex
    owner = root / ('isolated-' + token)
    owner.mkdir()
    generated, evidence = owner / 'generated', owner / 'evidence'
    generated.mkdir()
    evidence.mkdir()
    project = generated / 'project'
    project.mkdir()
    report = {'run_id': token, 'generated': str(generated), 'passed': False,
              'processes': [], 'source_files': {}, 'results': {}, 'cleanup': 'not_started',
              'runner_sha256': sha(Path(__file__)), 'job_executor_sha256': sha(REPO / 'tools/run_isolated_godot_test.py'),
              'engine': str(engine), 'engine_sha256': sha(engine)}
    budgets = {'seconds': 900, 'bytes': 1024 * 1024 * 1024, 'min_free': 512 * 1024 * 1024}
    report['budgets'] = budgets
    env = os.environ.copy()
    for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR'):
        path = generated / key.lower()
        path.mkdir()
        env[key] = str(path)
    try:
        executable = generated / 'Godot.exe'
        shutil.copyfile(engine, executable)
        if sha(executable) != report['engine_sha256']:
            raise ValueError('engine copy digest mismatch')
        for name in dependencies():
            source = isolated.contained(REPO / name, REPO)
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            report['source_files'][name] = sha(source)
            if sha(target) != report['source_files'][name]:
                raise ValueError('freeze drift: ' + name)
        # Only diagnostic application configuration is new. Every rule/loader script is unmodified.
        application = '[application]\nconfig/name="ChoiceSubmitReal"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="ChoiceSubmitReal"\n'
        threading = '[threading]\nworker_pool/max_threads=20\n'
        configuration = 'config_version=5\n' + application + '[autoload]\n'
        configuration += ''.join('%s="*res://%s"\n' % pair for pair in AUTOLOADS.items())
        configuration += '[rendering]\nrenderer/rendering_method="gl_compatibility"\n' + threading
        (project / 'project.godot').write_text(configuration, encoding='utf-8')
        (evidence / 'project.godot').write_text(configuration, encoding='utf-8')
        shutil.copyfile(REPO / SUITE, evidence / Path(SUITE).name)
        shutil.copyfile(REPO / SCENE, evidence / Path(SCENE).name)
        probe = generated / 'probe'
        probe.mkdir()
        (probe / 'project.godot').write_text('config_version=5\n' + application + threading, encoding='utf-8')
        script = isolated.PROBE_SCRIPT.replace('["--headless", "--path",', '["--headless", "--fixed-fps", "60", "--path",')
        (probe / 'probe.gd').write_text(script, encoding='utf-8')
        command = [str(executable), '--headless', '--fixed-fps', '60', '--path', str(probe), '--script', 'res://probe.gd', '--', token, 'main', str(generated)]
        out, err, code = isolated.execute(command, env, generated, evidence, 'probe', budgets, report['processes'])
        if code or re.search(r'SCRIPT ERROR|^\s*ERROR:', out + err, re.M):
            raise ValueError('physical IO probe refused')
        report['user_probes'] = isolated.verify_probe(out, generated, token)
        command = [str(executable), '--headless', '--fixed-fps', '60', '--path', str(project)]
        out, err, code = isolated.execute(command + ['--editor', '--import'], env, generated, evidence, 'import', budgets, report['processes'])
        report['import'] = {'exit': code, 'errors': len(re.findall(r'SCRIPT ERROR|^\s*ERROR:', out + err, re.M))}
        if code or report['import']['errors']:
            raise ValueError('frozen import refused; inspect exact errors')
        for kind in args.kind or KINDS:
            argv = command + ['--scene', 'res://' + SCENE, '--', kind]
            out, err, code = isolated.execute(argv, env, generated, evidence, kind, budgets, report['processes'])
            analysis = isolated.analyze(out, err, code)
            analysis['exit'] = code
            analysis['errors'] = len(re.findall(r'SCRIPT ERROR|^\s*ERROR:', out + err, re.M))
            analysis['check_lines'] = len(re.findall(r'^CHECK\b', out, re.M))
            analysis['argv'] = argv
            process = report['processes'][-1]
            analysis['job0'] = process.get('active_owned_processes') == 0 and process.get('log_handles_released') is True
            paths = re.findall(r'^DIAGNOSTIC_USER_PATH ([^\r\n]+)', out, re.M)
            if len(paths) != 1:
                analysis['passed'] = False
                analysis['reasons'].append('missing_actual_user_path')
            else:
                analysis['actual_user_path'] = str(isolated.contained(isolated.physical_e(paths[0]), generated))
            report['results'][kind] = analysis
        report['source_drift'] = [name for name, digest in report['source_files'].items() if sha(REPO / name) != digest]
        report['job0'] = bool(report['processes']) and all(p.get('active_owned_processes') == 0 and p.get('log_handles_released') is True for p in report['processes'])
        report['passed'] = not report['source_drift'] and report['job0'] and all(x['passed'] for x in report['results'].values())
    except Exception as exc:
        report['error'] = type(exc).__name__ + ': ' + str(exc)
    finally:
        report['logs'] = {p.name: sha(p) for p in evidence.glob('*.log')}
        (owner / 'manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        try:
            if report['processes'] and all(p.get('exited') is True and p.get('active_owned_processes') == 0 for p in report['processes']):
                isolated.delete_owned(generated, owner)
                report['cleanup'] = 'generated_removed'
            else:
                report['cleanup'] = 'retained_unproven_exit'
                report['passed'] = False
        except Exception as exc:
            report['cleanup_error'] = str(exc)
            report['passed'] = False
        (owner / 'manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'passed': report['passed'], 'manifest': str(owner / 'manifest.json'),
                      'error': report.get('error'), 'results': report['results'], 'cleanup': report['cleanup']}, ensure_ascii=False))
    return 0 if report['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
