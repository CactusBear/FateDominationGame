"""B24 bounded legacy display query RED/GREEN, reusing the owned E-drive runner."""
import difflib
import importlib.util
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('owned_runner', ROOT/'newtests/round71_host_match_runner.py')
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)
SOURCE = Path('scripts/game_scene/tactical_board_ui.gd')
TESTS = [Path('newtests/round74_tactical_player_query_test'+suffix) for suffix in ('.gd', '.tscn')]
SCENE = 'res://newtests/round74_tactical_player_query_test.tscn'


def copy_tests(scope):
    for name in TESTS:
        dest = scope/'project'/name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT/name, dest)


def annotate(scope, row):
    row['b24_source_sha256'] = {name.as_posix():RUNNER.digest(scope/'project'/name) for name in [SOURCE]+TESTS}
    (scope/'evidence'/(row['label']+'.json')).write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf-8')
    return row


def main():
    action = sys.argv[1]
    if action == 'red':
        scope = RUNNER.freeze()
        copy_tests(scope)
        shutil.copyfile(scope/'project'/SOURCE, scope/'evidence/tactical-before.gd')
        row = annotate(scope, RUNNER.run(scope,'b24-red',SCENE))
        result = row['analysis'].get('result') or {}
        failed = result.get('failures', [])
        valid = row['exit_code'] == 1 and len(failed) == 18 and all(label.startswith(('unknown class ','unknown prompt refresh ','unknown geometry ')) and label.endswith(' preserves player keys') for label in failed) and 'engine_error' not in row['analysis']['reasons']
        print(json.dumps({'scope':str(scope),'valid_red':valid}),flush=True)
        return 0 if valid else 1
    scope = Path(sys.argv[2]).resolve()
    if scope.drive.upper() != 'E:' or not scope.name.startswith('round71-host-match-') or not (scope/'evidence/tactical-before.gd').is_file():
        raise ValueError('not this task owned freeze')
    copy_tests(scope)
    shutil.copyfile(ROOT/SOURCE,scope/'project'/SOURCE)
    rows = [annotate(scope,RUNNER.run(scope,'b24-green',SCENE))]
    rows.append(annotate(scope,RUNNER.run(scope,'player-query-purity','res://tests/player_query_purity_test.tscn')))
    before = json.loads((scope/'evidence/b24-red.json').read_text(encoding='utf-8'))
    same = rows[0]['compare'] == before['compare']
    diff = ''.join(difflib.unified_diff((scope/'evidence/tactical-before.gd').read_text(encoding='utf-8').splitlines(keepends=True),(ROOT/SOURCE).read_text(encoding='utf-8').splitlines(keepends=True),fromfile='before/'+SOURCE.as_posix(),tofile='after/'+SOURCE.as_posix()))
    (scope/'evidence/b24.diff').write_text(diff,encoding='utf-8')
    report = {'same_display_trace':same,'rows':rows}
    (scope/'evidence/b24-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'same_display_trace':same,'report':str(scope/'evidence/b24-verification.json')}),flush=True)
    return 0 if same and all(row['analysis']['passed'] for row in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
