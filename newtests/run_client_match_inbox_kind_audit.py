"""Read-only production freeze and one owned E-drive Godot contract run."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import sys
import uuid

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))
from tools.run_isolated_godot_test import execute, analyze

GODOT = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe')
SOURCES = ['scripts/net/session/client_match_inbox.gd', 'scripts/net/session/lobby_session.gd']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = Path('E:/Caches/Hermes/cache/scratch').resolve(strict=True)
    if root.drive.upper() != 'E:':
        raise RuntimeError('E scratch required')
    owner = root / ('client-inbox-kind-audit-' + uuid.uuid4().hex)
    owner.mkdir()
    project = owner / 'project'
    evidence = owner / 'evidence'
    project.mkdir()
    evidence.mkdir()
    env = os.environ.copy()
    for key in ['APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR']:
        path = owner / key.lower()
        path.mkdir()
        env[key] = str(path)
    before = {rel:digest(REPO / rel) for rel in SOURCES}
    envelope_defect = '--envelope-defect' in sys.argv
    env['CLIENT_INBOX_ENVELOPE_DEFECT'] = '1' if envelope_defect else '0'
    record = {'owner':str(owner), 'production_sha256_before':before,
              'envelope_defect_probe':envelope_defect,
              'environment':{key:env[key] for key in ['APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR']},
              'processes':[], 'source_files':[], 'watchdog_seconds':360,
              'excluded':['GUI','ENet serialization','whole suite','speed tests','secrets'],
              'protected_pids_untouched':[17120,28100]}
    copied = set()

    def copy(rel):
        if rel in copied:
            return
        src = REPO / rel
        if not src.is_file():
            raise RuntimeError('missing explicit frozen dependency: ' + rel)
        if src.stat().st_size > 64 * 1024 * 1024:
            raise RuntimeError('oversize frozen dependency: ' + rel)
        dst = project / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src,dst)
        if digest(src) != digest(dst):
            raise RuntimeError('source changed during freeze: ' + rel)
        copied.add(rel)
        record['source_files'].append({'path':rel,'sha256':digest(dst)})
        if src.suffix in ['.gd','.tscn','.tres','.import']:
            text = src.read_text(encoding='utf-8-sig')
            if src.suffix == '.gd':
                refs = re.findall(r'preload\(\s*[\"\']res://([^\"\']+)[\"\']',text)
            else:
                refs = re.findall(r'[\"\']res://([^\"\']+)[\"\']',text)
            for ref in refs:
                copy(ref)
        if src.suffix in ['.png','.jpg','.svg','.webp'] and (REPO / (rel + '.import')).is_file():
            copy(rel + '.import')

    try:
        for path in (REPO / 'scripts').rglob('*.gd'):
            copy(path.relative_to(REPO).as_posix())
        for path in (REPO / 'data').rglob('*.json'):
            copy(path.relative_to(REPO).as_posix())
        copy('.godot/global_script_class_cache.cfg')
        copy('newtests/client_match_inbox_kind_audit.gd')
        copy('newtests/client_match_inbox_kind_audit.tscn')
        (project / 'tests').mkdir(exist_ok=True)
        shutil.copyfile(project / 'newtests/client_match_inbox_kind_audit.tscn', project / 'tests/client_match_inbox_kind_audit.tscn')
        config = (REPO / 'project.godot').read_text(encoding='utf-8-sig')
        config = re.sub(r'^_mcp_game_helper=.*\n','',config,flags=re.M)
        config = re.sub(r'^enabled=PackedStringArray\("res://addons/godot_ai/plugin.cfg"\)', 'enabled=PackedStringArray()', config,flags=re.M)
        (project / 'project.godot').write_text(config,encoding='utf-8')
        record['frozen_config_sha256'] = digest(project / 'project.godot')
        record['config_changes'] = ['remove development MCP autoload','disable development editor plugin']
        record['scene_staging'] = 'newtests scene copied unchanged to frozen tests/; production tests directory untouched'
        budgets = {'seconds':360, 'bytes':256 * 1024 * 1024, 'min_free':1024 * 1024 * 1024}
        command = [str(GODOT),'--headless','--fixed-fps','60','--path','.','--scene','res://tests/client_match_inbox_kind_audit.tscn']
        stdout, stderr, code = execute(command,env,project,evidence,'contract',budgets,record['processes'])
        record['analysis'] = analyze(stdout,stderr,code)
        record['check_lines'] = [line for line in stdout.splitlines() if line.startswith('CHECK ')]
        record['result_lines'] = [line for line in stdout.splitlines() if line.startswith('RESULT ')]
        record['error_lines'] = [line for line in (stdout+'\n'+stderr).splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:|^\s*FAIL\b',line)]
        record['job0'] = all(p.get('active_owned_processes') == 0 and p.get('exited') is True for p in record['processes'])
        record['user_dir_lines'] = [line for line in stdout.splitlines() if line.startswith('AUDIT_USER_DIR ')]
        record['user_dir_e_verified'] = len(record['user_dir_lines']) == 1 and Path(record['user_dir_lines'][0].split(' ',1)[1]).resolve().is_relative_to(owner)
        record['status'] = 'PASS' if record['analysis']['passed'] and record['job0'] and record['user_dir_e_verified'] else 'FAIL'
    except Exception as exc:
        record['error'] = str(exc)
        record['status'] = 'INCONCLUSIVE' if 'timeout' in str(exc).lower() else 'BLOCKED'
    record['production_sha256_after'] = {rel:digest(REPO / rel) for rel in SOURCES}
    record['production_unchanged'] = before == record['production_sha256_after']
    if not record['production_unchanged']:
        record['status'] = 'SOURCE_CHANGED_REAUDIT_REQUIRED'
    path = owner / 'receipt.json'
    path.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({key:value for key,value in record.items() if key not in ['source_files','check_lines']},ensure_ascii=False,indent=2))
    print('RECEIPT', path)
    return 0 if record['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
