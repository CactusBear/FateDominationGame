"""Real Godot emergency-stop regression, with owned Windows Job and E-only scratch."""
import argparse
import importlib.util
import json
import os
import hashlib
import re
import shutil
from pathlib import Path
import sys
from types import SimpleNamespace
import uuid


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--root', required=True)
    parser.add_argument('--timeout', required=True, type=float)
    args = parser.parse_args()
    if args.timeout < 600:
        parser.error('watchdog must be at least 600 seconds')
    project = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location('isolated', project / 'tools/run_isolated_godot_test.py')
    isolated = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(isolated)
    native_execute = isolated.execute

    def fixed_execute(command, *positional, **keywords):
        command = list(command)
        if '--fixed-fps' not in command:
            command[1:1] = ['--fixed-fps', '60']
        return native_execute(command, *positional, **keywords)

    isolated.execute = fixed_execute
    root = isolated.physical_e(args.root)
    output = root / ('emergency-stop-' + uuid.uuid4().hex)
    output.mkdir()
    os.environ.update(TMPDIR=str(output), TEMP=str(output), TMP=str(output),
                      HERMES_SHUTDOWN_TEST_ROOT=output.as_posix())
    # Cold-import an independent snapshot: never repair the live editor's class cache.
    generated = output / 'generated'
    generated.mkdir()
    snapshot = generated / 'snapshot'
    snapshot.mkdir()
    includes = ['scripts', 'data', 'addons/fate_server_signals/fate_server_signals.gdextension',
                'addons/godot_ai/runtime/game_helper.gd', 'icon.svg',
                'newtests/net_emergency_stop_test.gd', 'newtests/net_emergency_stop_test.tscn',
                'newtests/net_server_shutdown_failure_test.gd', 'newtests/match_journal_test.gd',
                'newtests/net_shutdown_owned_worker.gd', 'newtests/net_shutdown_owned_worker.tscn']
    selected = set(isolated.source_files(project, includes))
    queue = list(selected)
    while queue:
        rel = queue.pop()
        if rel.suffix not in {'.gd', '.tscn', '.tres', '.gdextension'}:
            continue
        for ref in re.findall(r'res://([^\s\"\'\)]+)', (project / rel).read_text(encoding='utf-8-sig')):
            path = project / ref
            if path.is_file() and path.relative_to(project) not in selected:
                isolated.no_links(path)
                child = path.relative_to(project)
                selected.add(child)
                queue.append(child)
    fingerprints = []
    for rel in sorted(selected):
        if rel.name.startswith('~') and rel.suffix == '.dll':
            continue
        destination = snapshot / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(project / rel, destination)
        digest = hashlib.sha256(destination.read_bytes()).hexdigest()
        if digest != hashlib.sha256((project / rel).read_bytes()).hexdigest():
            raise RuntimeError('source changed during snapshot: ' + str(rel))
        fingerprints.append({'path': rel.as_posix(), 'sha256': digest})
    config = (project / 'project.godot').read_text(encoding='utf-8-sig')
    config = re.sub(r'^run/main_scene=.*$', '', config, flags=re.M)
    # This headless protocol fixture has no cursor/UI consumer; avoid texture autoload
    # running before a cold importer has produced its texture resources.
    config = re.sub(r'^CursorReplace=.*$', '', config, flags=re.M)
    config = config.replace('version_control/autoload_on_startup=true', 'version_control/autoload_on_startup=false')
    config = re.sub(r'^enabled=PackedStringArray\("res://addons/godot_ai/plugin.cfg"\)$', 'enabled=PackedStringArray()', config, flags=re.M)
    (snapshot / 'project.godot').write_text(config, encoding='utf-8')
    (output / 'snapshot-files.json').write_text(json.dumps(fingerprints, indent=2), encoding='utf-8')
    import_evidence = output / 'import-evidence'
    import_evidence.mkdir()
    env = os.environ.copy()
    env.update(APPDATA=str(output / 'appdata'), LOCALAPPDATA=str(output / 'localappdata'))
    processes = []
    try:
        stdout, stderr, code = isolated.execute([str(isolated.physical_e(args.godot)), '--headless', '--fixed-fps', '60',
            '--editor', '--import', '--path', str(snapshot)], env, generated, import_evidence, 'import',
            {'seconds': args.timeout, 'bytes': 2147483648, 'min_free': 1073741824}, processes)
    finally:
        (output / 'import-processes.json').write_text(json.dumps(processes, indent=2), encoding='utf-8')
    if code or re.search(r'SCRIPT ERROR|ERROR:', stdout + stderr):
        print(json.dumps({'passed': False, 'stage': 'import', 'output': str(output), 'exit': code, 'processes': processes}))
        return 1
    result = isolated.run(SimpleNamespace(project=str(snapshot), scene='res://newtests/net_emergency_stop_test.tscn',
        root=str(output), godot=args.godot, timeout=args.timeout, max_bytes=2147483648,
        min_free_bytes=1073741824, freeze=False, include=[]))
    manifests = list(output.glob('isolated-*/manifest.json'))
    for path in manifests:
        manifest = json.loads(path.read_text(encoding='utf-8'))
        print(json.dumps({'manifest': str(path), 'analysis': manifest.get('analysis'),
                          'processes': manifest.get('processes'), 'passed': manifest['passed']}, ensure_ascii=False))
    child_errors = []
    for log in output.glob('emergency-*/**/worker.log'):
        text = log.read_text(encoding='utf-8', errors='replace')
        if re.search(r'SCRIPT ERROR|SHADER ERROR|^ERROR:', text, re.M):
            child_errors.append(str(log))
    (output / 'child-log-check.json').write_text(json.dumps({'error_logs': child_errors}, indent=2), encoding='utf-8')
    if child_errors:
        print(json.dumps({'passed': False, 'stage': 'worker_log', 'error_logs': child_errors}))
        return 1
    return result


if __name__ == '__main__':
    sys.exit(main())
