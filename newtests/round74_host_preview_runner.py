"""Bounded preview RED/GREEN and existing match-command contract on one owned E freeze."""
import importlib.util
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('round71_host_match_runner', ROOT/'newtests/round71_host_match_runner.py')
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


def add_preview(scope):
    dest = scope/'project/newtests'
    dest.mkdir(exist_ok=True)
    for suffix in ('.gd', '.tscn'):
        source = ROOT/'newtests'/('round74_host_preview_contract_test'+suffix)
        shutil.copyfile(source, dest/source.name)


def main():
    action = sys.argv[1]
    if action == 'red':
        scope = RUNNER.freeze()
        add_preview(scope)
        row = RUNNER.run(scope, 'preview-red', 'res://newtests/round74_host_preview_contract_test.tscn')
        result = row['analysis'].get('result') or {}
        valid_red = row['exit_code'] == 1 and result.get('failures') == ['existing inbox owns preview request shape closure'] and 'engine_error' not in row['analysis']['reasons']
        print(json.dumps({'scope':str(scope), 'valid_red':valid_red}), flush=True)
        return 0 if valid_red else 1
    scope = Path(sys.argv[2]).resolve()
    if scope.drive.upper() != 'E:' or not scope.name.startswith('round71-host-match-') or not (scope/'evidence/freeze.json').is_file():
        raise ValueError('not this runner owned freeze')
    add_preview(scope)
    relative = Path('scripts/net/session/host_match_request_inbox.gd')
    shutil.copyfile(ROOT/relative, scope/'project'/relative)
    rows = [RUNNER.run(scope, 'preview-green', 'res://newtests/round74_host_preview_contract_test.tscn')]
    rows.append(RUNNER.run(scope, 'existing-match-command-contract', 'res://tests/round71_host_match_contract_test.tscn'))
    report = scope/'evidence/preview-verification.json'
    report.write_text(json.dumps(rows,ensure_ascii=False,indent=2), encoding='utf-8')
    print('REPORT',report, flush=True)
    return 0 if all(row['analysis']['passed'] for row in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
