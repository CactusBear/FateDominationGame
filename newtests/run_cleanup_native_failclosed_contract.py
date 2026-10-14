"""Real frozen Godot fail-closed contracts; E-only, no deletion, no native calls."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe')
SCENE = 'newtests/cleanup_native_failclosed_contract_test.tscn'
TEST = SCENE.replace('.tscn', '.gd')
DLL = 'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll'
GATE_PATH = ROOT / 'tools/run_isolated_godot_test.py'
spec = importlib.util.spec_from_file_location('isolated_gate', GATE_PATH)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--without-native', action='store_true')
    parser.add_argument('--mutation', choices=['binding', 'unknown', 'active', 'epoch'])
    args = parser.parse_args()
    parent = gate.physical_e(Path('E:/scratch'))
    scope = parent / ('cleanup-native-failclosed-' + uuid.uuid4().hex)
    project = scope / 'project'
    project.mkdir(parents=True)
    gate.physical_e(scope)
    sources = {}
    pending = [TEST]
    while pending:
        name = pending.pop()
        if name in sources:
            continue
        source = gate.contained(ROOT / name, ROOT)
        text = source.read_text(encoding='utf-8')
        sources[name] = sha(source)
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        pending += re.findall(r'(?:preload|extends)\s*\(?\s*[\"\x27]res://([^\"\x27]+\.gd)[\"\x27]', text)
    for name in [SCENE, 'tools/run_isolated_godot_test.py', 'newtests/run_cleanup_native_failclosed_contract.py']:
        source = gate.contained(ROOT / name, ROOT)
        sources[name] = sha(source)
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    mutation = None
    if args.mutation:
        target = project / 'scripts/net/server/temporary_cleanup_proof_collector.gd'
        original = target.read_text(encoding='utf-8')
        needle, replacement = {
            'binding': ('member.binding != binding', 'false'),
            'unknown': ('member.identity_status != "verified" or member.process_state not in ["RUNNING","EXITED"]', 'false'),
            'active': ('current.append(binding.instance_id)', 'pass'),
            'epoch': ('member.lease_epoch != held.epoch', 'false'),
        }[args.mutation]
        if original.count(needle) != 1:
            raise RuntimeError('frozen-only mutation anchor drift')
        target.write_text(original.replace(needle, replacement), encoding='utf-8')
        mutation = {'kind': args.mutation, 'test_only': True, 'needle': needle, 'frozen_sha256': sha(target)}
    if not args.without_native:
        native = project / 'native'
        native.mkdir()
        source = gate.contained(ROOT / DLL, ROOT)
        sources[DLL] = sha(source)
        shutil.copyfile(source, native / 'production_old.dll')
        (native / 'production_old.gdextension').write_text('[configuration]\nentry_symbol="fate_server_signals_init"\ncompatibility_minimum="4.4"\nreloadable=false\n[libraries]\nwindows.x86_64="res://native/production_old.dll"\n', encoding='utf-8')
        cache = project / '.godot'
        cache.mkdir()
        (cache / 'extension_list.cfg').write_text('res://native/production_old.gdextension\n', encoding='utf-8')
    (project / 'project.godot').write_text('[application]\nconfig/name="CleanupNativeFailclosedContract"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')
    env = dict(os.environ)
    for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR'):
        path = scope / 'environment' / key.lower()
        path.mkdir(parents=True)
        env[key] = str(path)
    command = [str(ENGINE), '--headless', '--fixed-fps', '60', '--path', str(project), '--scene', 'res://' + SCENE]
    if args.without_native:
        command += ['--', 'without-native']
    frozen = {'sources': sources, 'mutation': mutation, 'command': command, 'watchdog_seconds': 300, 'environment': {key: env[key] for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR')}}
    (scope / 'freeze.json').write_text(json.dumps(frozen, indent=2), encoding='utf-8')
    job = gate.OwnedJob()
    timed_out = False
    out_path, err_path = scope / 'godot.stdout.log', scope / 'godot.stderr.log'
    with out_path.open('wb') as out, err_path.open('wb') as err:
        process = subprocess.Popen(command, cwd=project, env=env, stdout=out, stderr=err, creationflags=4)
        try:
            job.attach_resume(process)
            process.wait(timeout=300)
            deadline = time.monotonic() + 15
            while job.active() and time.monotonic() < deadline:
                time.sleep(.02)
            active = job.active()
        except subprocess.TimeoutExpired:
            timed_out = True
            job.stop()  # Only this suspended-before-start attached Job, never PID lists.
            process.wait(timeout=15)
            active = job.active()
        finally:
            if process.poll() is None:
                # Exact root created here only; never enumerate/terminate external processes.
                job.stop()
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=15)
            job.close()
    stdout = out_path.read_text(encoding='utf-8', errors='replace')
    stderr = err_path.read_text(encoding='utf-8', errors='replace')
    parsed = gate.analyze(stdout, stderr, process.returncode)
    report_path = project / 'result.json'
    report = json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {}
    unchanged = {name: sha(ROOT / name) == digest for name, digest in sources.items()}
    readback = {key: sha(Path(report[key.replace('_sha256', '_path')])) == report[key] for key in ('artifact_sha256', 'ledger_sha256')} if report else {}
    actual_user_path = Path(report.get('user_data_dir', ''))
    user_on_e = bool(report) and actual_user_path.resolve().is_relative_to(scope.resolve())
    errors = [line for line in (stdout + '\n' + stderr).splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:', line)]
    rows = report.get('check_rows', [])
    passed = parsed['passed'] and report.get('passed') is True and all(unchanged.values()) and bool(readback) and all(readback.values()) and not timed_out and active == 0 and user_on_e
    evidence = {'passed': passed, 'exit_code': process.returncode, 'checks': len(rows), 'failed_checks': [row['name'] for row in rows if not row['ok']], 'ERROR_count': len(errors), 'errors': errors, 'watchdog_seconds': 300, 'timed_out': timed_out, 'fixture_Job0': active == 0, 'fixture_Job_active_processes': active, 'production_Job0': 'UNKNOWN_NOT_OBSERVED', 'native_observation': report.get('native_observation'), 'without_native': args.without_native, 'mutation': mutation, 'sources_before_sha256': sources, 'sources_after_unchanged': unchanged, 'independent_readback': readback, 'actual_user_dir_in_owned_E_scope': user_on_e, 'command': command, 'scope': str(scope), 'analysis': parsed, 'production_auto_cleanup_enabled': False, 'removed_files': 0}
    (scope / 'verification.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding='utf-8')
    print('\n'.join(line for line in stdout.splitlines() if line.startswith(('CHECK ', 'RESULT '))))
    print(json.dumps({key: evidence[key] for key in ('passed', 'exit_code', 'checks', 'failed_checks', 'ERROR_count', 'fixture_Job0', 'production_Job0', 'native_observation', 'scope')}, ensure_ascii=False, indent=2))
    if errors:
        print('\n'.join(errors))
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())
