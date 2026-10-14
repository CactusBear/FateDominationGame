"""Only identity_ack wiring, E frozen engine/old DLL, 180s owned Job; no GUI/ports/full."""
import difflib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('password_freezer',ROOT/'newtests/f09_room_password_session_runner.py')
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)
OWNED = ['scripts/net/session/lobby_session.gd','scripts/net/identity/resume_ack_transaction.gd','newtests/identity_ack_session_wiring_test.gd','newtests/identity_ack_session_wiring_test.tscn']
BASE.OWNED = OWNED


def branch(source, label, following):
    return source.split('\t\t"'+label+'":\n',1)[1].split('\t\t"'+following+'":\n',1)[0]


def main():
    action = sys.argv[1]
    scope = BASE.freeze() if action == 'red' else Path(sys.argv[2]).resolve()
    assert scope.drive.upper() == 'E:' and scope.name.startswith('pw-')
    snapshot = scope/'evidence/session-before.gd'
    if action == 'red':
        shutil.copyfile(ROOT/OWNED[0],snapshot)
    else:
        for name in OWNED:
            dest = scope/'project'/name
            dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(ROOT/name,dest)
    BASE.RUNNER.ENGINE = scope/'engine'/BASE.RUNNER.ENGINE.name
    row = BASE.RUNNER.run(scope,'identity-ack-'+action,'res://newtests/identity_ack_session_wiring_test.tscn')
    row['source_sha256'] = {name:BASE.sha(ROOT/name) for name in OWNED}
    row['frozen_ack_source_sha256'] = {name:BASE.sha(scope/'project'/name) for name in OWNED}
    before = snapshot.read_text(encoding='utf-8')
    after = (ROOT/OWNED[0]).read_text(encoding='utf-8')
    before_ack = branch(before,'identity_ack','preview_group')
    after_ack = branch(after,'identity_ack','preview_group')
    row['session_before_sha256'] = BASE.sha(snapshot)
    row['only_identity_ack_changed'] = before.replace(before_ack,'<ACK>',1) == after.replace(after_ack,'<ACK>',1)
    row['password_branch_unchanged'] = before.split('\t\t"room_password":\n',1)[1].split('\t\t"server_data_catalog",',1)[0] == after.split('\t\t"room_password":\n',1)[1].split('\t\t"server_data_catalog",',1)[0]
    row['password_branch_before_sha256'] = BASE.hashlib.sha256(before.split('\t\t"room_password":\n',1)[1].split('\t\t"server_data_catalog",',1)[0].encode()).hexdigest()
    row['password_branch_after_sha256'] = BASE.hashlib.sha256(after.split('\t\t"room_password":\n',1)[1].split('\t\t"server_data_catalog",',1)[0].encode()).hexdigest()
    row['old_inline_deleted'] = all(x not in after_ack for x in ('sha256_text()','_resume_previous.erase(sender)','_resume_previous[sender] = previous','var previous:String'))
    row['static_no_retained_object'] = '.acknowledge(sender,' in after_ack and 'resume_ack_transaction.gd").new()' not in after
    stdout = (scope/'evidence'/('identity-ack-'+action+'.stdout.log')).read_text(encoding='utf-8')
    stderr = (scope/'evidence'/('identity-ack-'+action+'.stderr.log')).read_text(encoding='utf-8')
    row['user_path_on_E'] = bool(re.search(r'^USER_PATH E:[/\\]',stdout,re.M))
    row['ERROR'] = len(re.findall(r'(?:SCRIPT ERROR:|(?m:^ERROR:))',stdout+'\n'+stderr))
    row['actualchecks'] = (row['analysis'].get('result') or {}).get('checks',0)
    (scope/'evidence/session-local.diff').write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='session-before',tofile='session-after')),encoding='utf-8')
    report = scope/'evidence'/('identity-ack-'+action+'-verified.json')
    report.write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf-8')
    print('REPORT',report,flush=True)
    print(json.dumps({k:row[k] for k in ('actualchecks','ERROR','process_ownership','only_identity_ack_changed','password_branch_unchanged','old_inline_deleted','source_sha256')},ensure_ascii=False),flush=True)
    if action == 'red':
        failures = (row['analysis'].get('result') or {}).get('failures',[])
        return 0 if row['exit_code'] == 1 and failures == ['Session calls static resume ack transaction'] and row['ERROR'] == 0 else 1
    return 0 if row['analysis']['passed'] and row['user_path_on_E'] and row['source_sha256'] == row['frozen_ack_source_sha256'] and row['only_identity_ack_changed'] and row['password_branch_unchanged'] and row['old_inline_deleted'] and row['static_no_retained_object'] and row['ERROR'] == 0 and row['process_ownership']['active_owned_processes'] == 0 else 1


if __name__ == '__main__':
    raise SystemExit(main())
