"""Join shape only: first import E freeze; owned 180s Job; no GUI/listen/full."""
import difflib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('join_freezer', ROOT/'newtests/f09_room_password_session_runner.py')
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)
OWNED = ['scripts/net/session/lobby_session.gd','scripts/net/identity/host_identity_request_codec.gd','newtests/join_shape_session_wiring_test.gd','newtests/join_shape_session_wiring_test.tscn']
BASE.OWNED = OWNED
BEFORE = 'dfa448a286ca698b3f88b70baac5567aaa3f7bd1f581f4c1c414ff328d598886'
OLD = 'if args.get("name") is String and args.get("spectator") is bool:'
NEW = 'if _host_identity_request_codec.validate(message.kind,args).ok:'


def import_project(scope):
    env = os.environ.copy()
    for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR'):
        p = scope/key.lower()
        p.mkdir(exist_ok=True)
        env[key] = str(p)
    command = [str(BASE.RUNNER.ENGINE),'--headless','--editor','--path',str(scope/'project'),'--import','--quit']
    out, err = scope/'evidence/import.stdout.log', scope/'evidence/import.stderr.log'
    job = BASE.RUNNER.GATE.OwnedJob()
    timed_out = False
    with out.open('wb') as stdout, err.open('wb') as stderr:
        proc = subprocess.Popen(command,cwd=scope/'project',env=env,stdout=stdout,stderr=stderr,creationflags=0x00000004)
        try:
            job.attach_resume(proc)
            try:
                code = proc.wait(timeout=180)
            except subprocess.TimeoutExpired:
                timed_out = True
                job.stop()
                code = proc.wait(timeout=15)
        finally:
            if job.active(): job.stop()
            if proc.poll() is None: proc.kill()
            code = proc.wait(timeout=15)
            active = job.active()
            job.close()
    job.wait_log_release([out,err])
    errors = len(re.findall(r'(?:SCRIPT ERROR:|(?m:^ERROR:))',out.read_text(encoding='utf-8')+'\n'+err.read_text(encoding='utf-8')))
    row = {'command':command,'pid':proc.pid,'exit_code':code,'timeout':timed_out,'ERROR':errors,'active_owned_processes':active,'engine_sha256':BASE.sha(BASE.RUNNER.ENGINE)}
    (scope/'evidence/import.json').write_text(json.dumps(row,indent=2),encoding='utf-8')
    print('IMPORT',json.dumps(row),flush=True)
    assert code == 0 and not timed_out and errors == 0 and active == 0


def main():
    action = sys.argv[1]
    if action == 'red':
        assert BASE.sha(ROOT/OWNED[0]) == BEFORE
        scope = BASE.freeze()
        shutil.copyfile(ROOT/OWNED[0],scope/'evidence/session-before.gd')
        BASE.RUNNER.ENGINE = scope/'engine'/BASE.RUNNER.ENGINE.name
        import_project(scope)
    else:
        scope = Path(sys.argv[2]).resolve()
        assert scope.drive.upper() == 'E:' and scope.name.startswith('pw-')
        BASE.RUNNER.ENGINE = scope/'engine'/BASE.RUNNER.ENGINE.name
        for name in OWNED:
            shutil.copyfile(ROOT/name,scope/'project'/name)
    row = BASE.RUNNER.run(scope,'join-'+action,'res://newtests/join_shape_session_wiring_test.tscn')
    before_bytes = (scope/'evidence/session-before.gd').read_bytes()
    after_bytes = (ROOT/OWNED[0]).read_bytes()
    row['session_before_sha256'] = BASE.sha(scope/'evidence/session-before.gd')
    row['exact_one_line_change'] = before_bytes.count(OLD.encode()) == 1 and after_bytes == before_bytes.replace(OLD.encode(),NEW.encode(),1)
    row['source_sha256'] = {name:BASE.sha(ROOT/name) for name in OWNED}
    row['frozen_source_sha256_owned'] = {name:BASE.sha(scope/'project'/name) for name in OWNED}
    stdout = (scope/'evidence'/('join-'+action+'.stdout.log')).read_text(encoding='utf-8')
    stderr = (scope/'evidence'/('join-'+action+'.stderr.log')).read_text(encoding='utf-8')
    row['actual_CHECK_lines'] = len(re.findall(r'^CHECK ',stdout,re.M))
    row['ERROR'] = len(re.findall(r'(?:SCRIPT ERROR:|(?m:^ERROR:))',stdout+'\n'+stderr))
    row['user_path_on_E'] = bool(re.search(r'^USER_PATH E:[/\\]',stdout,re.M))
    result = row['analysis'].get('result') or {}
    row['CHECK_matches_result'] = row['actual_CHECK_lines'] == result.get('checks')
    diff = ''.join(difflib.unified_diff(before_bytes.decode().splitlines(True),after_bytes.decode().splitlines(True),fromfile='session-before',tofile='session-after'))
    (scope/'evidence/session-local.diff').write_text(diff,encoding='utf-8')
    report = scope/'evidence'/('join-'+action+'-verified.json')
    report.write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf-8')
    print('REPORT',report,flush=True)
    print(json.dumps({k:row[k] for k in ('actual_CHECK_lines','ERROR','CHECK_matches_result','exact_one_line_change','process_ownership','source_sha256')},ensure_ascii=False),flush=True)
    basic = not row['timeout'] and row['ERROR'] == 0 and row['user_path_on_E'] and row['CHECK_matches_result'] and row['process_ownership']['active_owned_processes'] == 0
    if action == 'red':
        return 0 if basic and row['exit_code'] == 1 and 'join shape调用已完成codec' in result.get('failures',[]) else 1
    return 0 if basic and row['analysis']['passed'] and row['exact_one_line_change'] and row['source_sha256'] == row['frozen_source_sha256_owned'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
