"""Only choose_master adapter contract; original DLL and owned 180s E-drive Godot run."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('choice_existing_freeze', ROOT/'newtests/f09_room_password_session_runner.py')
FREEZER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FREEZER)
OWNED = ['scripts/net/session/host_room_inbox.gd', 'newtests/host_room_choice_request_test.gd', 'newtests/host_room_choice_request_test.tscn']
FREEZER.OWNED = OWNED
SCENE = 'res://newtests/host_room_choice_request_test.tscn'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    action = sys.argv[1]
    scope = FREEZER.freeze() if action == 'initial' else Path(sys.argv[2]).resolve()
    assert scope.drive.upper() == 'E:' and scope.name.startswith('pw-') and (scope/'evidence/freeze.json').is_file()
    FREEZER.RUNNER.ENGINE = scope/'engine'/FREEZER.RUNNER.ENGINE.name
    if action != 'initial':
        for name in OWNED:
            shutil.copyfile(ROOT/name, scope/'project'/name)
    target = scope/'project/scripts/net/session/host_room_inbox.gd'
    original = target.read_bytes()
    if action == 'mutation':
        text = original.decode('utf-8')
        anchor = 'choose.call(actor,args.seat,args.name)'
        assert text.count(anchor) == 1
        target.write_text(text.replace(anchor, 'choose.call(actor,0,args.name)'), encoding='utf-8')
    try:
        row = FREEZER.RUNNER.run(scope, action, SCENE)
    finally:
        if action == 'mutation':
            target.write_bytes(original)
    row['source_sha256'] = {name:sha(ROOT/name) for name in OWNED}
    row['restored_frozen_source_sha256'] = {name:sha(scope/'project'/name) for name in OWNED}
    output = (scope/'evidence'/(action+'.stdout.log')).read_text(encoding='utf-8')
    row['user_path_on_E'] = '\nUSER_PATH E:' in output
    report = scope/'evidence'/(action+'-verified.json')
    report.write_text(json.dumps(row, ensure_ascii=False, indent=2), encoding='utf-8')
    print('REPORT', report, flush=True)
    if action == 'initial':
        return 0 if row['exit_code'] == 1 and row['analysis']['result']['failures'] == ['independent choice API exists'] and 'engine_error' not in row['analysis']['reasons'] else 1
    if action == 'mutation':
        failures = (row['analysis'].get('result') or {}).get('failures', [])
        return 0 if row['exit_code'] == 1 and 'adapter preserves values without normalization' in failures and 'engine_error' not in row['analysis']['reasons'] else 1
    return 0 if row['analysis']['passed'] and row['user_path_on_E'] and row['source_sha256'] == row['restored_frozen_source_sha256'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
