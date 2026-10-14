"""D1 source-frozen Godot differential evidence; only owns its child PID."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

REPO = Path(__file__).resolve().parents[1]
OUT = Path('E:/scratch/payment-d1-implementation')
ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe')
TARGET = Path('scripts/system/operations/ActivateEffect.gd')
ROOTS = ['scripts', 'data', 'assets', 'addons', 'tests', 'newtests']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def freeze():
    dest = OUT / 'frozen'
    if dest.exists():
        raise RuntimeError('Freeze already exists; use run only, never silently overwrite it')
    dest.mkdir(parents=True)
    hashes = {}
    for name in ROOTS:
        for src in (REPO / name).rglob('*'):
            if not src.is_file() or '__pycache__' in src.parts:
                continue
            if src.is_symlink():
                raise RuntimeError(f'linked dependency {src}')
            rel = src.relative_to(REPO)
            target = dest / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, target)
            hashes[rel.as_posix()] = digest(src)
    for name in ['icon.svg', 'project.godot']:
        shutil.copy2(REPO / name, dest / name)
        hashes[name] = digest(REPO / name)
    project = (dest / 'project.godot').read_text(encoding='utf-8')
    project = re.sub(r'^_mcp_game_helper=.*\n', '', project, flags=re.M)
    project = project.replace('enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")', 'enabled=PackedStringArray()')
    (dest / 'project.godot').write_text(project, encoding='utf-8')
    cache = dest / '.godot'
    cache.mkdir()
    for name in ['global_script_class_cache.cfg', 'uid_cache.bin']:
        src = REPO / '.godot' / name
        if src.exists():
            shutil.copy2(src, cache / name)
    shutil.copytree(REPO / '.godot/imported', cache / 'imported')
    (OUT / 'frozen-source-hashes.json').write_text(json.dumps(hashes, indent=2), encoding='utf-8')
    return dest


def run(tag, scene, source=None):
    dest = OUT / 'frozen'
    if source:
        shutil.copy2(source, dest / TARGET)
    env = os.environ.copy()
    for key in ['APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR']:
        path = OUT / 'environment' / key
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    command = [str(ENGINE), '--headless', '--fixed-fps', '60', '--path', '.', '--scene', 'res://' + scene]
    process = subprocess.Popen(command, cwd=dest, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8', errors='replace')
    try:
        stdout, stderr = process.communicate(timeout=240)
    except subprocess.TimeoutExpired:
        process.kill()
        stdout, stderr = process.communicate()
    (OUT / (tag + '.stdout.log')).write_text(stdout, encoding='utf-8')
    (OUT / (tag + '.stderr.log')).write_text(stderr, encoding='utf-8')
    combined = stdout + '\n' + stderr
    result = {'tag': tag, 'command': command, 'cwd': str(dest), 'pid': process.pid,
              'exit': process.returncode, 'RESULT': re.findall(r'^RESULT.*$', stdout, re.M),
              'SCRIPT_ERROR': len(re.findall(r'SCRIPT ERROR', combined)),
              'ERROR': len(re.findall(r'^\s*ERROR:', combined, re.M)),
              'source_sha256': digest(dest / TARGET),
              'user_dir': re.findall(r'^USER_DIR (.*)$', stdout, re.M)}
    (OUT / (tag + '.json')).write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))
    return result


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['freeze', 'red', 'green', 'regressions', 'helpers', 'boundary', 'compare'])
    args = parser.parse_args()
    if args.action == 'freeze':
        print(freeze())
    elif args.action == 'red':
        run('red', 'newtests/payment_d1_registration_test.tscn', OUT / 'before-ActivateEffect.gd')
    elif args.action == 'green':
        run('green', 'newtests/payment_d1_registration_test.tscn', REPO / TARGET)
    elif args.action in {'helpers', 'boundary'}:
        name = 'payment_d1_registration_helpers_test' if args.action == 'helpers' else 'payment_d1_delayed_boundary_test'
        run(args.action, 'newtests/' + name + '.tscn')
    elif args.action == 'regressions':
        for name in ['command_spell_test', 'ask_player_option_test', 'card_effect_runtime_test', 'card_selection_owner_test']:
            run(name, 'tests/' + name + '.tscn')
    else:
        traces = {}
        for tag in ['red', 'green']:
            text = (OUT / (tag + '.stdout.log')).read_text(encoding='utf-8')
            traces[tag] = [json.loads(x) for x in re.findall(r'^SUCCESS_TRACE (.*)$', text, re.M)]
        result = {'before_count': len(traces['red']), 'after_count': len(traces['green']),
                  'equal': traces['red'] == traces['green'], 'before': traces['red'], 'after': traces['green']}
        (OUT / 'success-comparison.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps({k: v for k, v in result.items() if k not in {'before','after'}}))
        if not result['equal'] or result['before_count'] != 9:
            raise SystemExit(1)
