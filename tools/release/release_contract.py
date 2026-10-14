"""项目显式发行声明；只选择精确 preset/platform/role，不推测职责。"""
from __future__ import annotations
import argparse
import json
import re
import shutil
from pathlib import Path
from path_safety import checked

NAME = 'release_contract.json'


def relative(value):
    if not isinstance(value, str) or not value or ':' in value or '\\' in value:
        raise ValueError('发行依赖必须是非空相对路径')
    path = Path(value)
    if path.is_absolute() or '..' in path.parts or path.as_posix() != value:
        raise ValueError('发行依赖路径越界/不规范')
    return value


def declarations(project):
    path = checked(project / NAME)
    if not path.is_file(): raise ValueError('缺少项目发行声明: ' + NAME)
    value = json.loads(path.read_text(encoding='utf-8'))
    if value.get('version') != 1 or not isinstance(value.get('targets'), list) or not value['targets']:
        raise ValueError('缺少发行 targets/version 显式声明')
    seen = set()
    for target in value['targets']:
        if not isinstance(target, dict) or set(target) != {'preset','platform','role','executable','runtime_files'}:
            raise ValueError('发行 target 字段不完整/未知')
        key = (target['preset'], target['platform'], target['role'])
        if not all(isinstance(x, str) and x for x in key) or key in seen:
            raise ValueError('重复/非法发行 target')
        seen.add(key)
        if target['platform'] != 'windows' or target['role'] not in ('client','server','signaling'):
            raise ValueError('未实现的发行平台/角色')
        exe = relative(target['executable'])
        if Path(exe).name != exe or not exe.endswith('.exe'):
            raise ValueError('发行 executable 必须是单层 EXE 文件名')
        if not isinstance(target['runtime_files'], list): raise ValueError('缺少 runtime_files 声明')
        destinations = set()
        for item in target['runtime_files']:
            if not isinstance(item, dict) or set(item) != {'source','target'}: raise ValueError('非法运行依赖声明')
            source = relative(item['source']); destination = relative(item['target'])
            if target['role'] == 'signaling' and (source.startswith(('data/', 'scripts/match/', 'scripts/system/', 'scripts/game_scene/', 'operations/', 'json_maker/', 'assets/scenes/game_scene/')) or destination.startswith('data/')):
                raise ValueError('纯信令外置依赖禁止承载游戏数据/规则')
            if destination in destinations or destination in (exe, Path(exe).with_suffix('.pck').name) or Path(destination).parts[0] == 'data':
                raise ValueError('运行依赖目标冲突/data 契约不可覆盖')
            destinations.add(destination)
            if not checked(project / source).is_file(): raise ValueError('缺少声明的运行依赖: ' + source)
    return value['targets']


def select(project, preset, platform='windows', role=None):
    project = checked(project)
    matches = [t for t in declarations(project) if t['preset'] == preset and t['platform'] == platform and (role is None or t['role'] == role)]
    if len(matches) != 1: raise ValueError('preset/platform/role 发行声明不存在或不唯一')
    target = matches[0]
    if target['role'] in ('client','server'):
        if not checked(project / 'data').is_dir(): raise ValueError('游戏发行缺少强制 data 契约')

    else:
        text = checked(project / 'project.godot').read_text(encoding='utf-8-sig')
        blocks = re.split(r'(?m)^(?=\[[^\n]+\]\s*$)', text)
        if any(b.startswith('[autoload]') and re.search(r'(?m)^\s*[^;\s][^=\n]*=', b) for b in blocks):
            raise ValueError('纯信令工程禁止游戏/其他 autoload')
        network = [b for b in blocks if b.startswith('[network]')]
        if len(network) != 1 or not re.search(r'(?m)^signaling_only=true\s*$', network[0]):
            raise ValueError('纯信令缺少 signaling_only=true 声明')
    return target


def copy_runtime(project, output, preset, platform, role):
    from package_audit import sha
    project = checked(project); output = checked(output)
    if project == output or project in output.parents or output in project.parents:
        raise ValueError('工程与包目录不可包含')
    target = select(project, preset, platform, role)
    for item in target['runtime_files']:
        source = checked(project / item['source']); dest = checked(output / item['target'])
        if dest.exists():
            if not dest.is_file() or sha(source) != sha(dest): raise ValueError('已导出运行依赖不匹配: ' + item['target'])
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        with source.open('rb') as reader, dest.open('xb') as writer: shutil.copyfileobj(reader, writer)
        if sha(source) != sha(dest): raise ValueError('运行依赖复制哈希不匹配')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project', type=Path, required=True); p.add_argument('--output-dir', type=Path, required=True)
    p.add_argument('--preset', required=True); p.add_argument('--platform', default='windows'); p.add_argument('--role', required=True)
    a = p.parse_args(); copy_runtime(a.project, a.output_dir, a.preset, a.platform, a.role)


if __name__ == '__main__':
    try: main()
    except (OSError, ValueError) as exc: raise SystemExit(f'BLOCK: {exc}')