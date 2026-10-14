"""Frozen E-only Godot contract test; no production writes or cleanup."""
from pathlib import Path
import hashlib
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe')
SCENE = 'newtests/round74_cleanup_handoff_contract_test.tscn'
TEST = SCENE.replace('.tscn', '.gd')
DLL = 'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutation-binding', action='store_true', help='Test-only RED: bypass member binding equality in the frozen copy')
    args = parser.parse_args()
    parent = Path('E:/scratch').resolve()
    if parent.drive.lower() != 'e:':
        raise RuntimeError('physical E scratch required')
    scope = parent / ('round74-cleanup-handoff-' + uuid.uuid4().hex)
    project = scope / 'project'
    project.mkdir(parents=True)
    pending = ['scripts/net/server/temporary_cleanup_ledger.gd', TEST]
    sources = {}
    while pending:
        name = pending.pop()
        if name in sources:
            continue
        source = ROOT / name
        content = source.read_text(encoding='utf-8')
        sources[name] = sha(source)
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        pending += re.findall(r'(?:preload|extends)\s*\(?\s*[\"\x27]res://([^\"\x27]+\.gd)[\"\x27]', content)
    shutil.copyfile(ROOT / SCENE, project / SCENE)
    sources[SCENE] = sha(ROOT / SCENE)
    mutation = None
    if args.mutation_binding:
        collector = project / 'scripts/net/server/temporary_cleanup_proof_collector.gd'
        original = collector.read_text(encoding='utf-8')
        needle = 'member.binding != binding'
        if original.count(needle) != 1:
            raise RuntimeError('mutation anchor drift')
        collector.write_text(original.replace(needle, 'false'), encoding='utf-8')
        mutation = {'test_only': True, 'target': 'scripts/net/server/temporary_cleanup_proof_collector.gd', 'bypass': needle, 'frozen_sha256': sha(collector)}
    native = project / 'native'
    native.mkdir()
    shutil.copyfile(ROOT / DLL, native / 'production_old.dll')
    sources[DLL] = sha(ROOT / DLL)
    (native / 'production_old.gdextension').write_text('[configuration]\nentry_symbol="fate_server_signals_init"\ncompatibility_minimum="4.4"\nreloadable=false\n[libraries]\nwindows.x86_64="res://native/production_old.dll"\n', encoding='utf-8')
    (project / 'project.godot').write_text('[application]\nconfig/name="Round74CleanupHandoffContract"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')
    env = dict(os.environ)
    for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR'):
        target = scope / 'environment' / key.lower()
        target.mkdir(parents=True)
        env[key] = str(target)
    command = [str(ENGINE), '--headless', '--fixed-fps', '60', '--path', str(project), '--scene', 'res://' + SCENE]
    (scope / 'freeze.json').write_text(json.dumps({'sources': sources, 'mutation': mutation, 'command': command, 'environment': {key: env[key] for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR')}, 'contract_test_only': True}, indent=2), encoding='utf-8')
    process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        output, _ = process.communicate(timeout=90)
    except subprocess.TimeoutExpired:
        # Exact owned PID tree only; this is a watchdog, never evidence of Job release.
        subprocess.run(['taskkill.exe', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
        output, _ = process.communicate(timeout=10)
        (scope / 'godot.log').write_bytes(output)
        raise RuntimeError('owned fixture watchdog expired: ' + str(scope))
    (scope / 'godot.log').write_bytes(output)
    report_path = project / 'result.json'
    report = json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {}
    unchanged = {name: sha(ROOT / name) == digest for name, digest in sources.items()}
    text = output.decode('utf-8', errors='replace')
    passed = process.returncode == 0 and report.get('passed') is True and all(unchanged.values()) and 'SCRIPT ERROR' not in text and 'ERROR:' not in text
    independent = {key: sha(Path(report[key.replace('_sha256', '_path')])) == report[key] for key in ('artifact_sha256', 'ledger_sha256')} if report else {}
    passed = passed and all(independent.values())
    evidence = {'passed': passed, 'exit_code': process.returncode, 'pid': process.pid, 'command': command, 'sources_before_sha256': sources, 'sources_after_unchanged': unchanged, 'independent_readback': independent, 'checks': len(report.get('checks', [])), 'failed_checks': [row['name'] for row in report.get('checks', []) if row['ok'] is False], 'mutation': mutation, 'native_observation': report.get('native_observation'), 'actual_job_zero_verified': False, 'scope': str(scope), 'production_auto_cleanup_enabled': False}
    (scope / 'verification.json').write_text(json.dumps(evidence, indent=2), encoding='utf-8')
    print(text)
    print(json.dumps(evidence, indent=2))
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())