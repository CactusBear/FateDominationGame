"""Repeatable host close save-guard regression; generated state stays on physical E.

Uses the existing Job Object executor and readonly dependency collector. Reads only
source, probe receipts and completed logs; never archives recovery/key/ticket data.
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

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
TESTS = ('host_close_save_guard_test.gd', 'host_close_save_guard_test.tscn',
         'net_server_shutdown_failure_test.gd', 'net_shutdown_owned_worker.gd',
         'net_shutdown_owned_worker.tscn', 'match_journal_test.gd')
SCENE = 'res://newtests/host_close_save_guard_test.tscn'
ERROR = re.compile(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:', re.M)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args):
    r = load('host_guard_executor', REPO / 'tools/run_isolated_godot_test.py')
    d = load('host_guard_dependencies', REPO / 'tools/diagnostics/round71_publish_save_verification.py')
    d.SUITES = []
    root = r.physical_e(args.root)
    engine_source = r.no_links(Path(args.engine)).resolve(strict=True)
    token = uuid.uuid4().hex
    owner = root / ('isolated-' + token)
    owner.mkdir()
    generated = owner / 'generated'
    evidence = owner / 'evidence'
    generated.mkdir()
    evidence.mkdir()
    m = {'run_id': token, 'generated': str(generated), 'processes': [],
         'owned_labels': [], 'source_hashes': {}, 'passed': False,
         'watchdog_seconds': 600, 'scene': SCENE, 'cleanup': 'not_started',
         'scope': 'headless owned fixture: real RoomControl/LobbySession and native owner; not UI/full release'}

    def save():
        (owner / 'manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent=2), encoding='utf-8')

    def environment(label):
        base = generated / label
        base.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ)
        for key in list(env):
            if key.startswith(('HERMES_ASSEMBLY_', 'FATE_R60_', 'ROUND66_', 'FD_')) or key in {
                'HERMES_RECOVERY_VALIDATION_ROOT', 'HERMES_SHUTDOWN_TEST_ROOT',
                'ROUND56_HANDOFF_ROOT', 'FATE_TEST_SCRATCH_ROOT'}:
                env.pop(key, None)
        for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR'):
            path = base / key.lower()
            path.mkdir(exist_ok=True)
            env[key] = path.as_posix()
        (base / 'localappdata/hermes/cache/scratch').mkdir(parents=True, exist_ok=True)
        fixtures = base / 'fixtures'
        fixtures.mkdir(exist_ok=True)
        env['HERMES_SHUTDOWN_TEST_ROOT'] = fixtures.as_posix()
        return env

    def execute(label, command, env):
        m['owned_labels'].append(label)
        save()
        try:
            result = r.execute(command, env, generated, evidence, label,
                               {'seconds': 600, 'bytes': 8 * 1024**3, 'min_free': 1024**3}, m['processes'])
        finally:
            save()
        d.require_exit(m)
        return result

    save()
    print('HOST_CLOSE_GUARD_SCOPE ' + str(owner), flush=True)
    try:
        if (REPO / 'override.cfg').exists():
            raise ValueError('unprobed project override')
        files = sorted(set(d.collect_files(r)) | {Path('newtests') / x for x in TESTS}
                       | {Path(__file__).relative_to(REPO)})
        project = generated / 'project'
        project.mkdir()
        for rel in files:
            source = r.contained(REPO / rel, REPO)
            raw = source.read_bytes()
            m['source_hashes'][rel.as_posix()] = hashlib.sha256(raw).hexdigest()
            target = project / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
            if digest(source) != digest(target):
                raise ValueError('source drift at freeze: ' + str(rel))
        engine = generated / 'engine/Godot.exe'
        engine.parent.mkdir()
        shutil.copyfile(engine_source, engine)
        r.physical_e(engine)
        m['engine_sha256'] = digest(engine)
        if m['engine_sha256'] != digest(engine_source):
            raise ValueError('engine copy mismatch')
        config = (project / 'project.godot').read_text(encoding='utf-8-sig')
        if re.search(r'^\s*config/project_settings_override', config, re.M):
            raise ValueError('unprobed project settings override')
        changed = '\n'.join(x for x in config.splitlines() if not x.startswith((
            'run/main_scene=', 'run/main_scene.fate_server=', '_mcp_game_helper=',
            'enabled=PackedStringArray(', 'version_control/')))
        changed = changed.replace('renderer/rendering_method="mobile"', 'renderer/rendering_method="gl_compatibility"')
        app = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)', changed, re.M | re.S)[1]
        threads = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)', changed, re.M | re.S)[0]
        simple = 'config_version=5\n[application]\n' + app + '\n' + threads
        m['project_transform'] = 'isolated copy only: remove main_scene/VCS/MCP helper/plugin; compatibility renderer; preserve application/runtime autoloads/threading'
        m['transformed_project_sha256'] = hashlib.sha256(changed.encode()).hexdigest()
        setup = environment('setup')
        probe = generated / 'probe'
        probe.mkdir()
        (probe / 'project.godot').write_text(simple, encoding='utf-8')
        (probe / 'probe.gd').write_text(r.PROBE_SCRIPT, encoding='utf-8')
        out, err, code = execute('probe', [str(engine), '--headless', '--fixed-fps', '60', '--path', str(probe),
            '--script', 'res://probe.gd', '--', token, 'main', str(generated)], setup)
        if code or ERROR.search(out + err):
            raise ValueError('main/child physical E probe failed')
        m['user_probes'] = r.verify_probe(out, generated, token)
        for label, cfg in [('resource-import', simple), ('import', changed)]:
            (project / 'project.godot').write_text(cfg, encoding='utf-8')
            out, err, code = execute(label, [str(engine), '--headless', '--fixed-fps', '60',
                '--editor', '--import', '--path', str(project)], setup)
            if code or ERROR.search(out + err):
                raise ValueError(label + ' failed')
        env = environment('guard')
        command = [str(engine), '--headless', '--audio-driver', 'Dummy', '--fixed-fps', '60',
                   '--path', str(project), '--log-file', str(generated / 'guard/parent.log'), '--scene', SCENE]
        m['command'] = command
        out, err, code = execute('guard', command, env)
        m['analysis'] = r.analyze(out, err, code)
        m['exit_code'] = code
        m['check_count'] = len(re.findall(r'^CHECK\b', out, re.M))
        m['errors'] = ERROR.findall(out + '\n' + err)
        m['child_errors'] = []
        for log in (generated / 'guard/fixtures').rglob('worker.log'):
            text = log.read_text(encoding='utf-8', errors='replace')
            target = evidence / (log.parent.name + '.worker.log')
            target.write_bytes(log.read_bytes())
            m['child_errors'].extend(ERROR.findall(text))
        required = ('NOT-SAVED：真实 EXITED 加 closing 而无保存回执不得判已保存关闭',
                    'NOT-SAVED：保存标志明确为 false 不得判已保存关闭',
                    'NOT-SAVED：真实 EXITED 且回执完全缺失不得判已保存关闭')
        required += tuple('NOT-SAVED：真实保存失败保留房间及运行句柄：' + mode for mode in ('unsaved', 'persist_fail'))
        required += tuple('SAVED：成功保存及实际退出登记已确认关闭绑定：' + mode for mode in ('lan', 'p2p'))
        m['mandatory_checks_passed'] = all('CHECK ' + label + ' true' in out.splitlines() for label in required)
        m['source_drift'] = [p for p, h in m['source_hashes'].items() if digest(REPO / p) != h]
        m['passed'] = (m['analysis']['passed'] and m['mandatory_checks_passed'] and not m['child_errors']
                       and not m['source_drift'] and m['check_count'] == m['analysis']['result']['checks'])
        print('\n'.join(x for x in out.splitlines() if x.startswith('RESULT') or x.startswith('CHECK NOT-SAVED') or x.startswith('CHECK SAVED')), flush=True)
    except Exception as exc:
        m['error'] = type(exc).__name__ + ': ' + str(exc)
    finally:
        save()
        try:
            d.require_exit(m)
            m['job_active_processes'] = 0
            r.delete_owned(generated, owner)
            m['cleanup'] = 'generated_removed'
        except Exception as exc:
            m['cleanup_error'] = type(exc).__name__ + ': ' + str(exc)
            m['passed'] = False
        save()
    print(json.dumps({key: m.get(key) for key in ('passed', 'check_count', 'exit_code', 'errors',
        'child_errors', 'job_active_processes', 'cleanup', 'error', 'source_drift')}, ensure_ascii=False))
    print('MANIFEST ' + str(owner / 'manifest.json'))
    return 0 if m['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default='E:/scratch')
    parser.add_argument('--engine', default='D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
    raise SystemExit(run(parser.parse_args()))
