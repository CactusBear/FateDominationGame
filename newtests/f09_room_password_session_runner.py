"""Only password Session wiring: E-drive freeze, original native DLL, no GUI/ports/full suite."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('existing_owned_runner', ROOT/'newtests/round71_host_match_runner.py')
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)
OWNED = ['scripts/net/session/lobby_session.gd','scripts/net/session/host_room_password_request.gd','newtests/f09_room_password_session_test.gd','newtests/f09_room_password_session_test.tscn']

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def freeze():
    scope = Path('E:/scratch')/('pw-'+uuid.uuid4().hex[:8])
    scope.mkdir(parents=True)
    assert scope.resolve().drive.upper() == 'E:'
    project = scope/'project'
    project.mkdir()
    (scope/'evidence').mkdir()
    files = []
    for folder in ('scripts','data','assets','.godot/imported'):
        files.extend(p.relative_to(ROOT) for p in (ROOT/folder).rglob('*') if p.is_file())
    files.extend(Path(p) for p in ('project.godot','icon.svg','.godot/global_script_class_cache.cfg','.godot/extension_list.cfg','addons/fate_server_signals/fate_server_signals.gdextension','addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll','addons/godot-git-plugin/git_plugin.gdextension','addons/godot-git-plugin/win64/libgit_plugin.windows.editor.x86_64.dll','addons/webrtc_native/webrtc_native.gdextension','addons/webrtc_native/lib/libwebrtc_native.windows.template_debug.x86_64.dll','addons/webrtc_native/lib/libwebrtc_native.windows.template_release.x86_64.dll'))
    files.extend(Path(p) for p in OWNED)
    inventory = {}
    for name in sorted(set(files)):
        source = ROOT/name
        if not source.is_file(): continue
        assert not source.is_symlink()
        dest = project/name
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(source,dest)
        inventory[name.as_posix()] = sha(dest)
    # 保持正式autoload，副本仅移除开发MCP/editor插件，不改变规则或网络逻辑。
    config = (project/'project.godot').read_text(encoding='utf-8')
    config = re.sub(r'^_mcp_game_helper=.*\n','',config,flags=re.M)
    config = re.sub(r'^enabled=PackedStringArray\("res://addons/godot_ai/plugin.cfg"\)','enabled=PackedStringArray()',config,flags=re.M)
    (project/'project.godot').write_text(config,encoding='utf-8')
    (project/'tests').mkdir(exist_ok=True)
    (scope/'engine').mkdir()
    shutil.copyfile(RUNNER.ENGINE,scope/'engine'/RUNNER.ENGINE.name)
    main_engine = RUNNER.ENGINE.with_name(RUNNER.ENGINE.name.replace('_console.exe','.exe'))
    shutil.copyfile(main_engine,scope/'engine'/main_engine.name)
    (scope/'evidence/freeze.json').write_text(json.dumps({'source':str(ROOT),'inventory_sha256':inventory,'engine_sha256':sha(RUNNER.ENGINE)},indent=2),encoding='utf-8')
    print('SCOPE',scope,flush=True)
    return scope

def main():
    action = sys.argv[1]
    scope = freeze() if action == 'red' else Path(sys.argv[2]).resolve()
    assert scope.drive.upper() == 'E:' and scope.name.startswith('pw-') and (scope/'evidence/freeze.json').is_file()
    RUNNER.ENGINE = scope/'engine'/RUNNER.ENGINE.name
    if action != 'red':
        for name in OWNED:
            shutil.copyfile(ROOT/name,scope/'project'/name)
    row = RUNNER.run(scope,action,'res://newtests/f09_room_password_session_test.tscn')
    row['source_sha256'] = {name:sha(ROOT/name) for name in OWNED}
    row['frozen_password_source_sha256'] = {name:sha(scope/'project'/name) for name in OWNED}
    logs = (scope/'evidence'/(action+'.stdout.log')).read_text(encoding='utf-8')
    row['user_path_on_E'] = bool(re.search(r'^USER_PATH E:[/\\]',logs,re.M))
    report = scope/'evidence'/(action+'-verified.json')
    report.write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf-8')
    print('REPORT',report,flush=True)
    if action == 'red':
        failures = (row['analysis'].get('result') or {}).get('failures',[])
        valid = row['exit_code'] == 1 and 'Session owns reusable password request transaction' in failures and 'engine_error' not in row['analysis']['reasons']
        return 0 if valid else 1
    return 0 if row['analysis']['passed'] and row['user_path_on_E'] and row['source_sha256'] == row['frozen_password_source_sha256'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
