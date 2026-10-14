"""G04 静态包审计：只读文件和 manifest，不启动 Godot 或加载原生库。"""
from __future__ import annotations
import argparse, fnmatch, hashlib, json, re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from path_safety import checked, new_output, write_new_json
from release_contract import select


PRIVACY_POLICY = Path(__file__).with_name('release_privacy_policy.json')


def privacy_policy() -> dict:
    return json.loads(PRIVACY_POLICY.read_text(encoding='utf-8'))


def privacy_denies(name: str, package_policy: dict) -> bool:
    path = Path(name)
    parts = {part.lower() for part in path.parts}
    return bool(
        parts & {item.lower() for item in package_policy['deny_components']}
        or path.name.lower() in {item.lower() for item in package_policy['deny_filenames']}
        or path.suffix.lower() in {item.lower() for item in package_policy['deny_suffixes']}
        or any(fnmatch.fnmatchcase(path.name.lower(), pattern.lower())
               for pattern in package_policy['deny_filename_patterns'])
    )


def privacy_denied_paths(names, package_policy: dict) -> list[str]:
    return sorted(name for name in names if privacy_denies(name, package_policy))


def privacy_blockers(package_files: dict[str, str], package_policy: dict) -> list[str]:
    return ['privacy_denied_path:' + name
            for name in privacy_denied_paths(package_files, package_policy)]


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def manifest(root: Path, skip_suffixes=()) -> dict[str, str]:
    root = checked(root)
    skipped = set(skip_suffixes)
    files = {}

    def walk(directory):
        for child in sorted(directory.iterdir()):
            child = checked(child)
            if child.is_dir():
                walk(child)
            elif child.is_file() and child.suffix not in skipped:
                files[child.relative_to(root).as_posix()] = sha(child)

    if root.is_dir():
        walk(root)
    return files


def preset_options(project: Path, name: str) -> dict[str, object]:
    project = checked(project)
    presets = checked(project / 'export_presets.cfg')
    sections = {}
    current = None
    for raw in presets.read_text(encoding='utf-8-sig').splitlines():
        line = raw.strip()
        if line.startswith('[') and line.endswith(']'):
            current = line[1:-1] if re.fullmatch(r'preset\.\d+(?:\.options)?', line[1:-1]) else None
            if current and current not in sections: sections[current] = {}
        elif current and '=' in line:
            key, value = line.split('=', 1)
            if key.strip() in {'name', 'platform', 'dedicated_server', 'binary_format/embed_pck'}:
                try: sections[current][key.strip()] = json.loads(value.strip())
                except json.JSONDecodeError: raise ValueError(f'预设字段不是合法值：{key.strip()}')
    matches = [k for k, v in sections.items() if k.startswith('preset.') and not k.endswith('.options') and v.get('name') == name]
    if len(matches) != 1: raise ValueError(f'预设名不存在或不唯一：{name}')
    index = matches[0].split('.')[1]
    base = sections[matches[0]]; options = sections.get(f'preset.{index}.options', {})
    if base.get('platform') != 'Windows Desktop': raise ValueError('当前发行准入只实现 Windows Desktop 预设')
    if 'binary_format/embed_pck' not in options: raise ValueError('预设缺少 binary_format/embed_pck 显式声明')
    return {'embed_pck': options['binary_format/embed_pck'], 'dedicated_server': base.get('dedicated_server', False)}


def audit(project: Path, package: Path, output: Path, preset: str, platform='windows', role=None, freeze_manifest=None) -> int:
    project = checked(project); package = checked(package); output = new_output(output, (project, package))
    if project == package or project in package.parents or package in project.parents:
        raise ValueError('工程与包目录不可互相包含')
    policy = privacy_policy()
    package_policy = policy['package']
    if package_policy.get('integration_status', '').startswith('DECLARED_NOT_WIRED'):
        raise ValueError('隐私策略未接线: package_audit.py 必须消费 package policy')
    if not project.is_dir(): raise ValueError(f'工程目录不存在：{project}')
    options = preset_options(project, preset)
    target = select(project, preset, platform, role)
    if options['dedicated_server'] != (target['role'] != 'client'): raise ValueError('preset 与 role 不一致')
    expected = manifest(project / 'data', ('.import',)) if target['role'] != 'signaling' else {}
    if target['role'] != 'signaling' and not expected: raise ValueError('游戏发行 data 不得为空')
    actual = manifest(package / 'data', ('.import',)) if (package / 'data').is_dir() else {}
    executable_name = target['executable']
    executable = package / executable_name
    pck = package / (executable.stem + '.pck')
    blockers = []
    if not package.is_dir(): blockers.append('package_missing')
    if not executable.is_file(): blockers.append('executable_missing')
    elif executable.stat().st_size == 0: blockers.append('executable_empty')
    if options['embed_pck']: blockers.append('embedded_pck_unsupported')
    if not options['embed_pck'] and not pck.is_file(): blockers.append('pck_missing')
    package_files = manifest(package) if package.is_dir() else {}
    blockers.extend(privacy_blockers(package_files, package_policy))
    runtime = []
    for item in target['runtime_files']:
        source = checked(project / item['source']); dest = checked(package / item['target'])
        valid = dest.is_file() and sha(source) == sha(dest)
        runtime.append({**item, 'sha256':sha(source), 'matches':valid})
        if not valid: blockers.append('runtime_dependency_mismatch:' + item['target'])
    index = None
    if not options['embed_pck'] and pck.is_file():
        try: index = pck_index(pck)
        except ValueError as exc: blockers.append('pck_invalid:' + str(exc))
    if index:
        if not {'res://project.binary', 'res://project.godot'} & set(index['files']): blockers.append('packed_project_missing')
        for project_name in ('res://project.binary','res://project.godot'):
            if project_name in index['files']:
                entry = index['files'][project_name]
                with pck.open('rb') as stream:
                    stream.seek(entry['offset']); payload = stream.read(entry['size'])
                if b'_mcp_game_helper' in payload or b'addons/godot_ai' in payload:
                    blockers.append('development_autoload_in_project')
        for name in index['files']:
            parts = name[6:].lower().split('/')
            if any(p in {'test','tests','reports','runtime_reports','scratch','tools','docs','data'} for p in parts) or name.startswith(('res://addons/godot_ai/', 'res://addons/godot-git-plugin/')) or '_mcp_game_helper' in name or name in ('res://export_presets.cfg','res://release_contract.json'):
                blockers.append('unexpected_packed_resource:' + name)
            if target['role'] == 'signaling' and name.startswith(('res://scripts/match/', 'res://scripts/system/', 'res://scripts/game_scene/', 'res://operations/', 'res://json_maker/', 'res://assets/scenes/game_scene/')):
                blockers.append('signaling_contains_game_rules:' + name)
    if index:
        if index:
            mappings = {item['source']: item['target'] for item in target['runtime_files']}
            for name, entry in index['files'].items():
                if name.startswith(('res://data/', 'res://tests/', 'res://tools/')) or name in ('res://export_presets.cfg', 'res://release_contract.json'):
                    blockers.append('unexpected_packed_resource:' + name)
                if not name.endswith('.gdextension'): continue
                descriptor = checked(project / name[6:])
                if not descriptor.is_file() or sha(descriptor) != entry['sha256']:
                    blockers.append('descriptor_mismatch:' + name); continue
                libraries = {}
                for line in descriptor.read_text(encoding='utf-8-sig').splitlines():
                    match = re.fullmatch(r'\s*(windows(?:\.[\w]+)*)\s*=\s*"([^"]+)"\s*', line)
                    if match: libraries[match[1]] = match[2]
                library = libraries.get('windows.release.x86_64', libraries.get('windows.x86_64'))
                if not library: blockers.append('release_library_missing:' + name); continue
                source = checked(project / library[6:]) if library.startswith('res://') else checked(descriptor.parent / library)
                if project not in source.parents: raise ValueError('descriptor 原生依赖越界')
                relative = source.relative_to(project).as_posix()
                if relative not in mappings or mappings[relative] != source.name:
                    blockers.append('undeclared_native_dependency:' + relative)
    provenance = {'source':str(project / 'data'), 'sha256_files':expected}
    if freeze_manifest:
        frozen = json.loads(checked(freeze_manifest).read_text(encoding='utf-8'))
        if checked(frozen['target']) != project: raise ValueError('审计冻结目标不匹配')
        frozen_data = {k[5:]:v for k,v in frozen['source_files'].items() if k.startswith('data/') and not k.endswith('.import')}
        if target['role'] != 'signaling' and frozen_data != expected: blockers.append('data_freeze_provenance_mismatch')
        provenance.update({'original_source':str(Path(frozen['source']) / 'data'), 'freeze_manifest':str(checked(freeze_manifest)), 'freeze_manifest_sha256':sha(checked(freeze_manifest))})
    report = {
        'mode': 'STATIC_ONLY', 'godot_invoked': False, 'native_loaded': False,
        'role':target['role'], 'platform':platform, 'runtime_files':runtime,
        'pck_index':index,
        'project': str(project), 'package': str(package),
        'data': {'missing': sorted(expected.keys() - actual.keys()),
                 'extra': sorted(actual.keys() - expected.keys()),
                 'changed': sorted(k for k in expected.keys() & actual.keys() if expected[k] != actual[k])},
        'data_provenance': provenance,
        'package_files': package_files,
        'privacy': {
            'policy': str(PRIVACY_POLICY),
            'integration': package_policy['integration_status'],
            'denied_paths': privacy_denied_paths(package_files, package_policy),
            'enforced': True,
        },
        'classification': 'CANDIDATE_SOURCE_NOT_LOCKED',
        'preset': preset, 'embed_pck': options['embed_pck'], 'executable': executable_name,
        'executable_present': executable.is_file(), 'pck_present': pck.is_file(), 'blockers': blockers,
    }
    report['status'] = 'STATIC_PASS_RUNTIME_PENDING' if not any(report['data'].values()) and not blockers else 'BLOCK'
    write_new_json(output, report)
    print(json.dumps({'status': report['status'], 'report': str(output), 'godot_invoked': False}, ensure_ascii=False))
    return 0 if report['status'] != 'BLOCK' else 2


def pck_index(path):
    """按 Godot 4.7 file_access_pack.cpp 读取非加密独立 PCK v3/v4。"""
    import struct
    path = checked(path); length = path.stat().st_size
    with path.open('rb') as stream:
        def read(size):
            value = stream.read(size)
            if len(value) != size: raise ValueError('PCK 截断')
            return value
        def u32(): return struct.unpack('<I', read(4))[0]
        def u64(): return struct.unpack('<Q', read(8))[0]
        if read(4) != b'GDPC': raise ValueError('非独立 PCK')
        version = u32()
        if version not in (3,4): raise ValueError('不支持的 PCK 格式')
        engine = [u32(),u32(),u32()]; flags = u32(); base = u64()
        if flags & ~2: raise ValueError('拒绝加密/sparse/未知 PCK 标志')
        directory = u64() if version in (3,4) else 96
        if directory >= length or base > length: raise ValueError('PCK 头越界')
        stream.seek(directory); count = u32()
        if count == 0: raise ValueError('PCK 为空')
        if count > 1000000: raise ValueError('PCK 数量超限')
        entries = {}
        for _ in range(count):
            name_length = u32()
            if name_length > 65536: raise ValueError('PCK 路径长度超限')
            name = read(name_length).rstrip(b'\x00').decode('utf-8')
            relative = name[6:] if name.startswith('res://') else name
            if not relative or ':' in relative or '\\' in relative or Path(relative).is_absolute() or '..' in Path(relative).parts: raise ValueError('PCK 非法资源路径')
            name = 'res://' + relative
            offset = u64() + base; size = u64(); md5 = read(16).hex(); entry_flags = u32()
            if entry_flags or name in entries or not name.startswith('res://') or '..' in Path(name[6:]).parts:
                raise ValueError('PCK 条目标志/路径/重复异常')
            if offset + size > directory or offset < base: raise ValueError('PCK 内容越界')
            entries[name] = {'offset':offset,'size':size,'md5':md5}
        for name, entry in entries.items():
            stream.seek(entry['offset']); remaining = entry['size']; digest = hashlib.sha256(); md5 = hashlib.md5()
            while remaining:
                data = read(min(remaining,1048576)); digest.update(data); md5.update(data); remaining -= len(data)
            if md5.hexdigest() != entry['md5']: raise ValueError('PCK 内容 MD5 不匹配: ' + name)
            entry['sha256'] = digest.hexdigest()
        if not any(entry['size'] for entry in entries.values()): raise ValueError('PCK 内容为空')
    return {'format':version,'engine':engine,'file_count':len(entries),'sha256':sha(path),'files':entries}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--preset', required=True)
    parser.add_argument('--platform', choices=('windows',), default='windows')
    parser.add_argument('--role', choices=('client','server','signaling'))
    parser.add_argument('--freeze-manifest', type=Path)
    args = parser.parse_args(argv)
    return audit(args.project, args.package, args.output, args.preset, args.platform, args.role, args.freeze_manifest)


if __name__ == '__main__':
    try: raise SystemExit(main())
    except (OSError, ValueError) as exc:
        raise SystemExit(f'BLOCK: {exc}')
