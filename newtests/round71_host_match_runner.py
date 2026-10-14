"""Round71 owned E-drive frozen Godot scene runner, 180s PID-tree watchdog."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe')
SELF = Path(__file__).resolve()
SPEC = importlib.util.spec_from_file_location('gate', ROOT/'tools/run_isolated_godot_test.py')
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)

def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def run(scope, label, scene):
    project = scope/'project'
    evidence = scope/'evidence'
    env = os.environ.copy()
    for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR'):
        p = scope/key.lower()
        p.mkdir(exist_ok=True)
        env[key] = str(p)
    command = [str(ENGINE),'--headless','--fixed-fps','60','--path',str(project),'--scene',scene]
    out, err = evidence/(label+'.stdout.log'), evidence/(label+'.stderr.log')
    job = GATE.OwnedJob()
    with out.open('wb') as stdout, err.open('wb') as stderr:
        proc = subprocess.Popen(command,env=env,cwd=project,stdout=stdout,stderr=stderr,creationflags=0x00000004)
        timeout = False
        try:
            job.attach_resume(proc)
            try: code = proc.wait(timeout=180)
            except subprocess.TimeoutExpired:
                timeout = True
                job.stop()
                code = proc.wait(timeout=15)
        finally:
            if job.active(): job.stop()
            if proc.poll() is None: proc.kill()
            code = proc.wait(timeout=15)
            active_owned_processes = job.active()
            job.close()
    job.wait_log_release([out,err])
    stdout, stderr = out.read_text(encoding='utf-8'), err.read_text(encoding='utf-8')
    analysis = GATE.analyze(stdout,stderr,code)
    analysis['passed'] = analysis['passed'] and not timeout
    comparisons = re.findall(r'^COMPARE (.*)$',stdout,re.M)
    row = {'label':label,'scene':scene,'command':command,'pid':proc.pid,'exit_code':code,'timeout':timeout,'analysis':analysis,'environment':{k:env[k] for k in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR')},'engine_sha256':digest(ENGINE),'stdout_sha256':digest(out),'stderr_sha256':digest(err),'compare':json.loads(comparisons[0]) if len(comparisons)==1 else None}
    row['process_ownership'] = {'kind':'Windows Job Object','created_suspended':True,'active_owned_processes':active_owned_processes,'log_handles_released':True}
    owned = ['scripts/net/session/lobby_session.gd','scripts/net/session/host_match_request_inbox.gd'] + [p.relative_to(project).as_posix() for p in (project/'tests').glob('round71_host_match*') if p.is_file()]
    row['frozen_source_sha256'] = {name:digest(project/name) for name in owned if (project/name).is_file()}
    row['native_dll_sha256'] = digest(project/'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll')
    (evidence/(label+'.json')).write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({key:row[key] for key in ('label','pid','exit_code','timeout','analysis')},ensure_ascii=False),flush=True)
    return row

def freeze():
    scope = Path('E:/scratch')/('round71-host-match-'+uuid.uuid4().hex)
    scope.mkdir(parents=True)
    assert scope.resolve().drive.lower() == 'e:'
    project = scope/'project'; project.mkdir()
    (scope/'evidence').mkdir()
    files = []
    for folder in ('scripts','data','assets','.godot/imported'):
        for p in (ROOT/folder).rglob('*'):
            if p.is_file(): files.append(p.relative_to(ROOT))
    for folder in ('tests',):
        files.extend(p.relative_to(ROOT) for p in (ROOT/folder).iterdir() if p.is_file() and p.suffix in {'.gd','.tscn','.uid'})
    files.extend(Path(p) for p in ('project.godot','icon.svg','.godot/global_script_class_cache.cfg','.godot/extension_list.cfg','addons/fate_server_signals/fate_server_signals.gdextension','addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll'))
    files.extend(Path(p) for p in ('addons/godot-git-plugin/git_plugin.gdextension','addons/godot-git-plugin/win64/libgit_plugin.windows.editor.x86_64.dll','addons/webrtc_native/webrtc_native.gdextension','addons/webrtc_native/lib/libwebrtc_native.windows.template_debug.x86_64.dll','addons/webrtc_native/lib/libwebrtc_native.windows.template_release.x86_64.dll'))
    inventory = []
    for name in sorted(set(files)):
        source = ROOT/name
        if not source.is_file(): continue
        assert not source.is_symlink()
        dest = project/name; dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(source,dest)
        inventory.append({'path':name.as_posix(),'sha256':digest(dest),'bytes':dest.stat().st_size})
    config = (project/'project.godot').read_text(encoding='utf-8')
    config = re.sub(r'^_mcp_game_helper=.*\n','',config,flags=re.M)
    config = re.sub(r'^enabled=PackedStringArray\("res://addons/godot_ai/plugin.cfg"\)','enabled=PackedStringArray()',config,flags=re.M)
    config = config.replace('worker_pool/max_threads=20','worker_pool/max_threads=2')
    (project/'project.godot').write_text(config,encoding='utf-8')
    (scope/'evidence/freeze.json').write_text(json.dumps({'inventory':inventory,'runner_sha256':digest(SELF),'engine_sha256':digest(ENGINE)},ensure_ascii=False,indent=2),encoding='utf-8')
    layer = subprocess.run([sys.executable,'-B','tools/check_layer_deps.py','--json'],cwd=ROOT,capture_output=True)
    (scope/'evidence/layer-before.json').write_bytes(layer.stdout)
    print('SCOPE',scope,flush=True)
    return scope

if __name__ == '__main__':
    action = sys.argv[1]
    if action == 'verify':
        scope = freeze()
        rows = []
        for label, scene in [('integration','round71_host_match_inbox_test'),('contract','round71_host_match_contract_test')] + [(name,name) for name in ('match_command_result_protocol_test','net_cards_test','net_move_test','net_pending_test','match_command_dispatcher_test')]:
            rows.append(run(scope,label,'res://tests/'+scene+'.tscn'))
            if sum(not row['analysis']['passed'] for row in rows) >= 3: break
        (scope/'evidence/verify.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
        raise SystemExit(0 if len(rows)==7 and all(row['analysis']['passed'] for row in rows) else 1)
    if action == 'baseline':
        scope = freeze()
        row = run(scope,'baseline','res://tests/round71_host_match_inbox_test.tscn')
        raise SystemExit(0 if row['analysis']['passed'] else 1)
    scope = Path(sys.argv[2]).resolve()
    assert scope.drive.lower() == 'e:' and scope.name.startswith('round71-host-match-') and (scope/'evidence/freeze.json').is_file()
    if action == 'red':
        path = scope/'project/scripts/net/session/lobby_session.gd'
        original = path.read_bytes()
        text = original.decode('utf-8')
        anchor = 'ok = match_authority.submit(sender, args.view_seq, args.command, args.params)'
        if text.count(anchor) == 1:
            mutated = text.replace(anchor,'ok = match_authority.submit(sender, args.view_seq, "end_action", args.params)')
        else:
            path = scope/'project/scripts/net/session/host_match_request_inbox.gd'
            original = path.read_bytes()
            text = original.decode('utf-8')
            anchor = 'submit.call(args.view_seq,args.command,args.params)'
            assert text.count(anchor) == 1
            mutated = text.replace(anchor,'submit.call(args.view_seq,"end_action",args.params)')
        path.write_text(mutated,encoding='utf-8')
        try: row = run(scope,'valid-red','res://tests/round71_host_match_inbox_test.tscn')
        finally: path.write_bytes(original)
        a = row['analysis']
        valid = row['exit_code'] == 1 and a['result'] and any('accepted reaches real handler' in x for x in a['result']['failures']) and 'engine_error' not in a['reasons']
        print('VALID_RED',bool(valid))
        raise SystemExit(0 if valid else 1)
    if action == 'green':
        for path in (ROOT/'tests').glob('round71_host_match*'):
            if path.is_file(): shutil.copyfile(path,scope/'project/tests'/path.name)
        for name in ('scripts/net/session/lobby_session.gd','scripts/net/session/host_match_request_inbox.gd'):
            shutil.copyfile(ROOT/name,scope/'project'/name)
        row = run(scope,'green','res://tests/round71_host_match_inbox_test.tscn')
        before = json.loads((scope/'evidence/baseline.json').read_text(encoding='utf-8'))
        same = row['compare'] == before['compare']
        (scope/'evidence/compare.json').write_text(json.dumps({'same':same,'before':before['compare'],'after':row['compare']},ensure_ascii=False,indent=2),encoding='utf-8')
        print('SAME_INPUT_OUTPUT_TRACE',same)
        raise SystemExit(0 if row['analysis']['passed'] and same else 1)
    if action == 'contract':
        row = run(scope,'contract','res://tests/round71_host_match_contract_test.tscn')
        raise SystemExit(0 if row['analysis']['passed'] else 1)
    if action == 'regression':
        rows = []
        for name in ('match_command_result_protocol_test','net_cards_test','net_move_test','net_pending_test','match_command_dispatcher_test'):
            rows.append(run(scope,name,'res://tests/'+name+'.tscn'))
            if sum(not x['analysis']['passed'] for x in rows) >= 3: break
        (scope/'evidence/regression.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
        raise SystemExit(0 if len(rows)==5 and all(x['analysis']['passed'] for x in rows) else 1)
    raise SystemExit('unknown action')
