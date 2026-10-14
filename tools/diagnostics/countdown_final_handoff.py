"""Round49: serial, unchanged formal countdown/CLI suites on one E freeze.

Only this diagnostic driver and its report are owned by this task. No production,
board, test, or generic-runner edits. Every engine process belongs to a Job Object.
"""
import sys
sys.dont_write_bytecode = True
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import time
import uuid

PROJECT = Path(__file__).resolve().parents[2]
HELPER = PROJECT / 'tools/run_isolated_godot_test.py'
spec = importlib.util.spec_from_file_location('isolated', HELPER)
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
SUITES = ['server_simulation_default_budget', 'server_validation_countdown']
CRITICAL = [
    'scripts/net/ui/room_data_panel.gd', 'scripts/net/server/server_data_approval.gd',
    'scripts/net/validation/room_validation_task.gd',
    'scripts/net/validation/room_data_validation_worker.gd',
    'scripts/net/validation/room_data_preparation.gd',
    'scripts/net/validation/rule_random_simulation.gd',
    'scripts/net/session/lobby_session.gd',
    'scripts/net/session/server_data_status_inbox.gd',
    'scripts/game_scene/battle_board_v2.gd',
    'scripts/game_scene/battle_io/battle_host_lifecycle.gd',
    'scripts/game_scene/battle_io/shared_view_sections.gd',
    'scripts/net/ui/v2_view_presenter.gd',
    'assets/config/server.cfg', 'project.godot',
    *['tests/' + name + '_test.' + suffix for name in SUITES for suffix in ['gd', 'tscn']],
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'), object_pairs_hook=r.unique_fields)


def function(text, name):
    match = re.search(r'^func ' + re.escape(name) + r'\(.*?(?=^func |\Z)', text, re.M | re.S)
    return match.group(0) if match else ''


def migration_inventory():
    session = (PROJECT / 'scripts/net/session/lobby_session.gd').read_text(encoding='utf-8')
    board = (PROJECT / 'scripts/game_scene/battle_board_v2.gd').read_text(encoding='utf-8')
    request = function(session, 'request')
    finish = re.search(r'^\t\t"match_finished_lobby":.*?(?=^\t\t"|\Z)', session, re.M | re.S)
    finish = finish.group(0) if finish else ''
    bind = function(board, '_bind_self')
    return {
        'host_lifecycle': {
            'executed': False,
            'request_registers_finish': '"match_finished_lobby"' in request,
            'finish_delivers_success': '_deliver_match_result(' in finish,
            'entry': 'tests/round47_host_lifecycle_runner.py --board --window',
            'reason': 'No current correlated finish registration/accepted receipt; do not inject acceptance or edit Session/board.'
        },
        'shared_view': {
            'executed': False,
            'board_uses_shared_render': 'render_self_power(' in bind,
            'board_still_draws_network_power': '_set_text(stats, "PowerRow/Power"' in bind,
            'entry': 'res://tests/net_v2_ui_input_parity_window_test.tscn -- window',
            'reason': 'Formal board still renders base network power; migration owner handoff not implemented. No broad substitute run.'
        }
    }


RUNTIME_PROBE = '''extends Node
func _init() -> void:
    var role:String = "suite-main"
    var arguments:PackedStringArray = OS.get_cmdline_user_args()
    if arguments.has("--server-room-worker"): role = "server-worker"
    elif arguments.has("--room-data-validation-worker"): role = "validation-worker"
    elif arguments.has("--config"): role = "cli-or-gui-main"
    var receipt:Dictionary = {"pid":OS.get_process_id(),"role":role,"path":OS.get_user_data_dir(),"token":OS.get_environment("ROUND49_PROBE_TOKEN"),"worker_pool_max_threads":ProjectSettings.get_setting("threading/worker_pool/max_threads")}
    var file := FileAccess.open("user://runtime-user-probe-%d.json" % OS.get_process_id(),FileAccess.WRITE)
    if file == null:
        push_error("ROUND49 runtime user probe cannot write")
        return
    file.store_string(JSON.stringify(receipt))
    file.close()
    print("ROUND49_RUNTIME_USER_PROBE ",JSON.stringify(receipt))
'''


def main():
    r.physical_e(PROJECT)
    for name in ['override.cfg', 'project.godot.override']:
        if (PROJECT / name).exists():
            raise r.SafetyError('unprobed project override: ' + name)
    root = r.physical_e('E:/scratch')
    run_id = uuid.uuid4().hex
    owner = root / ('isolated-' + run_id)
    owner.mkdir()
    generated = owner / 'generated'
    generated.mkdir()
    evidence = owner / 'evidence'
    evidence.mkdir()
    target = generated / 'project'
    target.mkdir()
    budgets = {'seconds': 180.0, 'bytes': 2000000000, 'min_free': 1000000000}
    m = {'run_id': run_id, 'owner': str(owner), 'generated': str(generated),
         'purpose': 'round49 current Session/status inbox real countdown integration',
         'budgets': budgets, 'processes': [], 'suites': {}, 'passed': False,
         'visual_review': 'not yet reviewed; native images required separately',
         'migration_inventory': migration_inventory()}
    save(owner / 'ownership.json', {'run_id': run_id, 'generated': str(generated), 'purpose': m['purpose']})
    save(owner / 'manifest.json', m)
    shutil.copyfile(__file__, evidence / 'runner.py')
    shutil.copyfile(HELPER, evidence / 'generic-runner-readonly.py')
    tools_before = {str(p): sha(p) for p in [Path(__file__), HELPER]}
    files = {Path(x) for x in CRITICAL}
    files.update(Path(x) for x in [
        'icon.svg', 'assets/scenes/main_menu/server_room_worker.tscn',
        'assets/scenes/main_menu/room_data_validation_worker.tscn',
        'assets/scenes/main_menu/server_cli.tscn',
        'assets/scenes/main_menu/multiplayer_lobby.tscn',
        'addons/fate_server_signals/fate_server_signals.gdextension',
        'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll'])
    files.update(p.relative_to(PROJECT) for p in (PROJECT / 'scripts').rglob('*.gd'))
    files.update(p.relative_to(PROJECT) for p in (PROJECT / 'addons/godot_ai').rglob('*')
                 if p.is_file() and p.suffix in {'.gd', '.cfg', '.svg', '.png', '.tres', '.tscn'})
    files.update(p.relative_to(PROJECT) for p in (PROJECT / 'data').rglob('*')
                 if p.is_file() and p.suffix.lower() in {'.json', '.png', '.jpg', '.jpeg', '.webp'})
    queue, seen = list(files), set()
    while queue:
        rel = queue.pop()
        if rel in seen or rel.suffix not in {'.gd', '.tscn', '.tres', '.godot'}:
            continue
        seen.add(rel)
        text = (PROJECT / rel).read_text(encoding='utf-8-sig')
        text = '\n'.join(x for x in text.splitlines() if not x.lstrip().startswith('#'))
        refs = re.findall(r'preload\(\s*["\'](res://[^"\']+)["\']', text)
        if rel.suffix in {'.tscn', '.tres'}:
            refs += re.findall(r'path="(res://[^"\n]+)"', text)
        for value in refs:
            new = Path(value[6:])
            if not (PROJECT / new).is_file():
                raise r.SafetyError('missing dependency ' + value)
            if new not in files:
                files.add(new)
                queue.append(new)
    files = sorted(files)
    source_before = {p.as_posix(): sha(r.contained(PROJECT / p, PROJECT)) for p in files}
    m['source_before'] = source_before
    m['test_scope'] = sorted(k for k in source_before if k.startswith('tests/'))
    m['critical_sources'] = {k: source_before[k] for k in CRITICAL}
    m['engine_sha256'] = sha(ENGINE)
    env = os.environ.copy()
    env.update(APPDATA=str(generated / 'appdata'), LOCALAPPDATA=str(generated / 'localappdata'),
               HERMES_VALIDATION_USER_PROBE='1', ROUND49_PROBE_TOKEN=run_id)
    for name in ['appdata', 'localappdata']:
        (generated / name).mkdir()
    executable = generated / 'engine/Godot.exe'
    executable.parent.mkdir()
    shutil.copyfile(ENGINE, executable)
    try:
        if sha(executable) != m['engine_sha256']:
            raise r.SafetyError('engine copy changed')
        r.physical_e(executable)
        for rel in files:
            dest = target / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(PROJECT / rel, dest)
            if sha(dest) != source_before[rel.as_posix()]:
                raise r.SafetyError('source drift during freeze: ' + str(rel))
        original = (target / 'project.godot').read_text(encoding='utf-8-sig')
        transformed = original.replace('version_control/plugin_name="GitPlugin"\n', '')
        transformed = transformed.replace('version_control/autoload_on_startup=true', 'version_control/autoload_on_startup=false')
        transformed = transformed.replace('run/main_scene="res://assets/scenes/main_menu/opening_background.tscn"', 'run/main_scene="res://tests/server_simulation_default_budget_test.tscn"')
        transformed = transformed.replace('[autoload]\n', '[autoload]\n\nRound49UserProbe="*res://round49_runtime_user_probe.gd"\n', 1)
        (target / 'round49_runtime_user_probe.gd').write_text(RUNTIME_PROBE, encoding='utf-8')
        (target / 'project.godot').write_text(transformed, encoding='utf-8')
        m['project_transform'] = 'isolated VCS disabled, selected explicit main, read-only runtime user receipt autoload; application/threading unchanged'
        m['frozen_before'] = {p.as_posix(): sha(target / p) for p in files}
        m['frozen_before']['round49_runtime_user_probe.gd'] = sha(target / 'round49_runtime_user_probe.gd')
        m['copy_files'] = len(files)
        m['copy_bytes'] = sum((target / p).stat().st_size for p in files)
        for name in CRITICAL + ['round49_runtime_user_probe.gd']:
            dest = evidence / 'frozen-source' / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(target / name, dest)
        probe = generated / 'probe'
        probe.mkdir()
        application = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)', original, re.M | re.S)[1]
        threading = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)', original, re.M | re.S)[1]
        probe_config = 'config_version=5\n[application]\n' + application + '\n[threading]\n' + threading
        (probe / 'project.godot').write_text(probe_config, encoding='utf-8')
        (probe / 'probe.gd').write_text(r.PROBE_SCRIPT, encoding='utf-8')
        command = [str(executable), '--headless', '--path', str(probe), '--script', 'res://probe.gd', '--', run_id, 'main', str(generated)]
        out, err, code = r.execute(command, env, generated, evidence, 'probe', budgets, m['processes'])
        if code or re.search(r'SCRIPT ERROR|ERROR:', out + err):
            raise r.SafetyError('physical E main/child probe failed')
        m['user_probes'] = r.verify_probe(out, generated, run_id)
        resource_config = re.sub(r'^run/main_scene=.*\n', '', probe_config, flags=re.M)
        for label, config in [('resource-import', resource_config), ('import', transformed)]:
            (target / 'project.godot').write_text(config, encoding='utf-8')
            command = [str(executable), '--headless', '--editor', '--import', '--path', str(target)]
            out, err, code = r.execute(command, env, generated, evidence, label, budgets, m['processes'])
            errors = [line for line in (out + err).splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|ERROR:', line)]
            m[label] = {'exit': code, 'errors': errors}
            if code or errors:
                raise r.SafetyError(label + ' failed; no retry')
        for suite in SUITES:
            gui = suite == 'server_validation_countdown'
            command = [str(executable), *([] if gui else ['--headless']), '--fixed-fps', '60', '--path', str(target), '--scene', 'res://tests/' + suite + '_test.tscn']
            if gui:
                command += ['--', '--config', (generated / 'appdata/FateDomination/gui.cfg').as_posix()]
            started = time.monotonic()
            out, err, code = r.execute(command, env, generated, evidence, suite, budgets, m['processes'])
            row = {'command': command, 'exit': code, 'wall_seconds': time.monotonic() - started, 'analysis': r.analyze(out, err, code)}
            m['suites'][suite] = row
            for line in out.splitlines():
                if line.startswith('DEFAULT_CONTRACT '):
                    contract = json.loads(line[len('DEFAULT_CONTRACT '):], object_pairs_hook=r.unique_fields)
                    save(evidence / 'default-contract.json', contract)
                    row['child_checks'] = contract['child'][0]['checks']
                    row['child_exit'] = contract['child_exit']
                elif line.startswith('COUNTDOWN_OBSERVATIONS '):
                    save(evidence / 'countdown-observations.json', json.loads(line[len('COUNTDOWN_OBSERVATIONS '):]))
            expected = 72 if gui else 13
            if row['analysis'].get('result', {}).get('checks') != expected:
                row['analysis']['passed'] = False
                row['analysis']['reasons'].append('current_test_contract_count_changed')
            if not gui and (row.get('child_checks') != 24 or row.get('child_exit') != 0):
                row['analysis']['passed'] = False
                row['analysis']['reasons'].append('CLI_child_contract_not_24_exit0')
            save(owner / 'manifest.json', m)
            if not row['analysis']['passed']:
                raise r.SafetyError('formal suite failed: ' + suite)
        m['passed'] = True
    except Exception as exc:
        m['error'] = repr(exc)
        m['passed'] = False
    finally:
        runtime_receipts, output_errors = [], []
        for path in (generated / 'appdata').rglob('*'):
            if not path.is_file():
                continue
            if path.name.startswith('runtime-user-probe-') and path.suffix == '.json':
                item = read_json(path)
                r.contained(r.physical_e(item['path']), generated)
                if item.get('token') != run_id or item.get('worker_pool_max_threads') != 20:
                    raise r.SafetyError('actual runtime user probe mismatch')
                runtime_receipts.append(item)
            if path.suffix in {'.json', '.log', '.cfg', '.txt'} or (path.suffix == '.png' and path.parent.name.startswith('countdown-')):
                dest = evidence / 'actual-user-output' / path.relative_to(generated / 'appdata')
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(r.no_links(path), dest)
                if path.suffix == '.log':
                    for index, line in enumerate(path.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
                        if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:', line):
                            output_errors.append({'path': str(dest.relative_to(evidence)), 'line': index, 'text': line})
        m['runtime_user_probes'] = runtime_receipts
        m['actual_output_errors'] = output_errors
        roles = {x['role'] for x in runtime_receipts}
        m['runtime_probe_roles_complete'] = {'suite-main', 'cli-or-gui-main', 'server-worker', 'validation-worker'}.issubset(roles)
        m['source_after'] = {p.as_posix(): sha(PROJECT / p) for p in files}
        m['source_drift'] = [k for k, v in source_before.items() if m['source_after'][k] != v]
        m['frozen_after'] = {k: sha(target / k) for k in m.get('frozen_before', {}) if (target / k).is_file()}
        m['frozen_drift'] = [k for k, v in m.get('frozen_before', {}).items() if m['frozen_after'].get(k) != v]
        m['tools_drift'] = [k for k, v in tools_before.items() if sha(Path(k)) != v]
        m['engine_source_unchanged'] = sha(ENGINE) == m['engine_sha256']
        m['migration_inventory_after'] = migration_inventory()
        m['passed'] = (m['passed'] and not output_errors and m['runtime_probe_roles_complete']
                       and not m['source_drift'] and not m['frozen_drift'] and not m['tools_drift']
                       and m['engine_source_unchanged'])
        m['artifacts'] = [{'path': p.relative_to(evidence).as_posix(), 'bytes': p.stat().st_size, 'sha256': sha(p)}
                          for p in evidence.rglob('*') if p.is_file()]
        save(owner / 'manifest.json', m)
        verified = [x['path'] for x in m['artifacts'] if sha(evidence / x['path']) == x['sha256']]
        if len(verified) != len(m['artifacts']):
            raise r.SafetyError('archive artifact readback mismatch; retain generated')
        if all(p.get('exited') and p.get('log_handles_released') for p in m['processes']):
            r.delete_owned(generated, owner)
            m['cleanup'] = 'generated_removed'
        else:
            m['cleanup'] = 'retained_exit_or_log_release_unproven'
            m['passed'] = False
        m['generated_exists_after_cleanup'] = generated.exists()
        save(owner / 'manifest.json', m)
        save(owner / 'delivery-readback.json', {'manifest_sha256': sha(owner / 'manifest.json'),
             'artifact_count': len(verified), 'artifacts_verified': True,
             'generated_exists': generated.exists(), 'all_jobs_empty': all(p.get('active_owned_processes') == 0 for p in m['processes'])})
    print(json.dumps({'manifest': str(owner / 'manifest.json'), 'passed_automated': m['passed'],
          'visual_review': m['visual_review'], 'error': m.get('error'), 'source_drift': m['source_drift'],
          'frozen_drift': m['frozen_drift'], 'cleanup': m['cleanup'],
          'suites': m['suites'], 'actual_output_errors': m['actual_output_errors'],
          'migration_inventory': m['migration_inventory_after']}, ensure_ascii=False))
    return 0 if m['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
