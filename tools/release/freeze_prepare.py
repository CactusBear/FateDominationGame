"""G04 Windows 冻结准备：只复制显式白名单到新目标，不执行 Godot。"""
from __future__ import annotations
import argparse, hashlib, json, shutil, re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from path_safety import checked, new_output, scratch_root, write_new_json
from release_contract import NAME, declarations

EXTENSIONS = {'.gd','.uid','.tscn','.tres','.gdshader','.gdshaderinc','.json','.png','.jpg','.jpeg','.webp','.svg','.ttf','.otf','.woff','.woff2','.ogv','.ogg','.wav','.mp3','.txt','.md','.csv','.import','.theme','.res','.cfg'}
DIRECTORIES = ('scripts', 'operations', 'assets', 'data', 'json_maker')
# 仅按显式路径组件排除；不按目录存在猜发行角色，不改导出过滤器。
# 任意 *.pem/*.key/*.log 与无凭据内容审批仍需独立发行门，见 release_privacy_policy.json。
EXCLUDED = {
    'test', 'tests', 'newtests', 'reports', 'scratch', 'runtime_reports',
    'game_data', '__pycache__', 'tools', 'newtools', 'docs', 'newdocs',
    'backups', 'buildmanifest', 'savedkeys', 'net_identity',
    'identities', 'match_saves', 'server_rooms', 'authority_rooms', 'saves',
    'savegames', 'logs', 'runtime', 'diagnostics', 'net_cache', 'net_session',
    'room_validation', 'rooms', 'private.pem', 'profile.json',
    'server_players.json', 'identity.json', 'resume_ticket.json',
    'resume_tickets', 'recovery_tickets', 'godot_ai', 'godot-git-plugin',
    'json_maker_backup.tscn', 'server.cfg', 'signaling.json',
}
FILES = ('project.godot', 'export_presets.cfg', 'icon.svg', 'icon.svg.import')
SIGNALING_SEEDS = (
    'scripts/net/server/server_bootstrap.gd',
    'scripts/net/server/server_process_signals.gd',
    'scripts/net/p2p/p2p_signal_server.gd',
    'scripts/net/p2p/p2p_invite.gd',
    'scripts/net/transport/webrtc_link.gd',
    'addons/fate_server_signals/fate_server_signals.gdextension',
    'assets/scenes/main_menu/server_bootstrap.tscn',
)


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''): h.update(chunk)
    return h.hexdigest()


def transform_project(source, role=None):
    text = (source / 'project.godot').read_text(encoding='utf-8-sig')
    if role == 'signaling':
        text = re.sub(r'(?m)^run/main_scene="[^"]*"$', 'run/main_scene="res://assets/scenes/main_menu/server_bootstrap.tscn"', text)
    output = []
    for block in re.split(r'(?m)^(?=\[[^\n]+\]\s*$)', text):
        if role == 'signaling' and block.startswith('[autoload]'):
            # server_bootstrap 的 signaling-only 入口明确要求零 autoload，
            # 否则游戏规则会在信令进程前被加载。
            block = ''
        elif block.startswith('[autoload]'):
            lines = []
            for line in block.splitlines(keepends=True):
                if line.strip().startswith('_mcp_game_helper='):
                    if line.strip() != '_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"': raise ValueError('未知开发 autoload 声明')
                    continue
                lines.append(line)
            block = ''.join(lines)
        if block.startswith('[editor_plugins]'): block = '[editor_plugins]\n\nenabled=PackedStringArray()\n\n'
        if block.startswith('[editor]'):
            block = re.sub(r'(?m)^version_control/plugin_name=.*\n?', '', block)
            block = re.sub(r'(?m)^version_control/autoload_on_startup=.*$', 'version_control/autoload_on_startup=false', block)
        output.append(block)
    if role == 'signaling' and '[network]' not in text:
        output.append('[network]\nsignaling_only=true\n\n')
    return ''.join(output)


def inventory(root, runtime_files=None, role=None, *, cold=False):
    result = set(FILES)
    if runtime_files is not None:
        result.update(item['source'] for item in runtime_files)
    elif (root / NAME).is_file():
        result.add(NAME)
        for target in declarations(root):
            if role is not None and target['role'] != role: continue
            result.update(item['source'] for item in target['runtime_files'])
    # 纯信令仍需冻结它自己的正式入口和原生信号适配；不能因无游戏
    # data 就得到一个只含 project.godot 的“空包”。
    if role == 'signaling':
        result.update(SIGNALING_SEEDS)
    for directory in (() if role == 'signaling' else DIRECTORIES):
        base = root / directory
        if not base.is_dir(): continue
        for path in base.rglob('*'):
            if path.is_file() and (directory == 'data' or path.suffix.lower() in EXTENSIONS) and not (set(p.lower() for p in path.relative_to(root).parts) & EXCLUDED):
                result.add(path.relative_to(root).as_posix())
    for rel in ('addons/fate_server_signals/fate_server_signals.gdextension', 'addons/webrtc_native/webrtc_native.gdextension'):
        if role == 'signaling' and rel not in result: continue
        descriptor = root / rel
        if not descriptor.is_file(): continue
        result.add(rel)
        for line in descriptor.read_text(encoding='utf-8-sig').splitlines():
            m = re.fullmatch(r'\s*(windows(?:\.[\w]+)*)\s*=\s*"([^"]+)"\s*', line)
            if not m or any(tag in m[1].split('.') for tag in ('x86_32','arm64')): continue
            lib = root / m[2][6:] if m[2].startswith('res://') else descriptor.parent / m[2]
            lib = checked(lib)
            if root not in lib.parents: raise ValueError('原生库越界: ' + rel)
            result.add(lib.relative_to(root).as_posix())
    if role == 'signaling':
        pending = ['project.godot']
        visited = set()
        while pending:
            rel = pending.pop()
            if rel in visited: continue
            visited.add(rel)
            if Path(rel).suffix not in {'.godot','.gd','.tscn','.tres'}: continue
            text = transform_project(root, 'signaling') if rel == 'project.godot' else (root / rel).read_text(encoding='utf-8-sig')
            if Path(rel).suffix == '.gd':
                references = re.findall(r'(?:preload|load)\(\s*"\*?res://([^"\n]+)"', text)
            else:
                references = re.findall(r'"\*?res://([^"\n]+)"', text)
            for dep in references:
                if set(Path(dep).parts) & EXCLUDED: raise ValueError('信令依赖开发资源')
                if (root / dep).is_dir():
                    continue
                result.add(dep); pending.append(dep)
    for rel in list(result):
        if not rel.endswith('.import'): continue
        # 冷候选保留导入元信息，由首次 --import 生成缓存；默认严格集合不变。
        if cold: continue
        for value in re.findall(r'res://(\.godot/imported/[^"\s]+)', (root / rel).read_text(encoding='utf-8-sig')):
            result.add(value)
            md5 = Path(value).with_suffix('.md5').as_posix()
            if (root / md5).is_file(): result.add(md5)
    for rel in sorted(result):
        path = root / rel
        if checked(path) != path or root not in checked(path).parents: raise ValueError('资源链接/越界: ' + rel)
        if not path.is_file(): raise ValueError('缺少白名单/依赖文件: ' + rel)
    return sorted(result)


def transform(source, preset=None, rels=None, role=None):
    project_text = transform_project(source, role)
    blocks = re.split(r'(?m)^(?=\[[^\n]+\]\s*$)', (source / 'export_presets.cfg').read_text(encoding='utf-8-sig'))
    selected = {}
    for block in blocks:
        m = re.match(r'\[preset\.(\d+)\]', block)
        if m and re.search(r'(?m)^platform="Windows Desktop"\s*$', block) and (preset is None or re.search(r'(?m)^name=' + re.escape(json.dumps(preset, ensure_ascii=False)) + r'\s*$', block)):
            selected[m[1]] = str(len(selected))
    if not selected: raise ValueError('没有 Windows Desktop 预设')
    if preset is not None and len(selected) != 1: raise ValueError('预设名称不唯一')
    presets = []
    for block in blocks:
        m = re.match(r'\[preset\.(\d+)(\.options)?\]', block)
        if not m or m[1] not in selected: continue
        block = re.sub(r'^\[preset\.\d+', '[preset.' + selected[m[1]], block)
        block = re.sub(r'(?m)^export_path=.*$', 'export_path=""', block)
        if not m[2]:
            exclude = re.search(r'(?m)^exclude_filter=(.*)$', block)
            old_exclude = json.loads(exclude[1]) if exclude else ''
            excludes = [item.strip() for item in old_exclude.split(',') if item.strip()]
            for pattern in ('addons/godot_ai/*', 'test/*', 'tests/*', 'reports/*', 'scratch/*', 'tools/*', 'docs/*', 'data/*'):
                if pattern not in excludes: excludes.append(pattern)
            if role == 'signaling':
                for pattern in ('json_maker/*', 'scripts/net/ui/*', 'scripts/game_scene/*', 'scripts/system/*', 'operations/*', 'assets/scenes/game_scene/*'):
                    if pattern not in excludes: excludes.append(pattern)
            if NAME not in excludes: excludes.append(NAME)
            exclude_line = 'exclude_filter=' + json.dumps(','.join(excludes), ensure_ascii=False)
            if exclude: block = block[:exclude.start()] + exclude_line + block[exclude.end():]
            else: block = block.replace('\n', '\n' + exclude_line + '\n', 1)
            include = re.search(r'(?m)^include_filter=(.*)$', block)
            old = json.loads(include[1]) if include else ''
            if role == 'signaling': old = ''
            filters = [item.strip() for item in old.split(',') if item.strip()]
            for cfg in (rels if rels is not None else inventory(source)):
                if cfg.endswith('.cfg') and cfg != 'export_presets.cfg' and cfg not in filters: filters.append(cfg)
            line = 'include_filter=' + json.dumps(','.join(filters), ensure_ascii=False)
            if include: block = block[:include.start()] + line + block[include.end():]
            else: block = block.replace('\n', '\n' + line + '\n', 1)
        presets.append(block)
    return {'project.godot': project_text, 'export_presets.cfg': ''.join(presets)}


def verify(project, manifest_path):
    project = checked(project)
    value = json.loads(checked(manifest_path).read_text(encoding='utf-8'))
    allowed = checked(value.get('allowed_root', scratch_root()))
    if not value.get('prepared') or checked(value['target']) != project or allowed not in project.parents: raise ValueError('冻结清单目标不匹配/越界')
    actual = {}
    for path in project.rglob('*'):
        if checked(path) != path: raise ValueError('冻结目标存在链接')
        if path.is_file(): actual[path.relative_to(project).as_posix()] = sha(path)
    if actual != value['files']: raise ValueError('冻结集合/哈希不匹配')
    source = checked(value['source'])
    runtime = (value.get('explicit_target') or {}).get('runtime_files')
    if set(inventory(source, runtime, (value.get('explicit_target') or {}).get('role'))) != set(value['source_files']): raise ValueError('源码资源集合变化')
    if any(checked(source / rel) != source / rel or sha(source / rel) != digest for rel, digest in value['source_files'].items()): raise ValueError('冻结后源码变化')
    expected = dict(value['source_files'])
    for rel, text in transform(source, value.get('preset'), list(value['source_files']), (value.get('explicit_target') or {}).get('role')).items(): expected[rel] = hashlib.sha256(text.encode('utf-8')).hexdigest()
    if value.get('explicit_target'):
        expected[NAME] = hashlib.sha256(contract_text(value['explicit_target']).encode('utf-8')).hexdigest()
    if expected != actual: raise ValueError('冻结转换不符合源码/project/preset 契约')
    return value


def contract_text(target):
    return json.dumps({'version':1, 'targets':[target]}, ensure_ascii=False, indent=2) + '\n'


def prepare(source, target, manifest_path, dry_run=False, *, preset=None, role=None, executable=None, runtime_files=None, allowed_root=None):
    source = checked(source); target = new_output(target, (source,), scratch=True, allowed_root=allowed_root)
    manifest_path = new_output(manifest_path, (source, target), scratch=True, allowed_root=allowed_root)
    explicit = None
    if preset is not None:
        if role not in ('client','server','signaling') or not executable or runtime_files is None: raise ValueError('必须完整声明 preset/role/executable/runtime_files')
        explicit = {'preset':preset,'platform':'windows','role':role,'executable':executable,'runtime_files':runtime_files}
    rels = inventory(source, runtime_files if explicit else None, role)
    hashes = {rel: sha(source / rel) for rel in rels}
    transformed = transform(source, preset, rels, role)
    if explicit: transformed[NAME] = contract_text(explicit)
    for rel in rels:
        if Path(rel).suffix not in {'.gd', '.tscn', '.tres', '.godot'}: continue
        text = transformed.get(rel, (source / rel).read_text(encoding='utf-8-sig'))
        refs = re.findall(r'(?:preload|load)\(\s*"res://([^"]+)"', text)
        if rel.endswith(('.tscn', '.tres')) or rel == 'project.godot': refs += re.findall(r'"\*?res://([^"\n]+)"', text)
        for dependency in refs:
            if dependency not in rels: raise ValueError('未冻结正式依赖: ' + rel + ' -> ' + dependency)
    if any(sha(source / rel) != hashes[rel] for rel in rels): raise ValueError('准备前源码变化')
    if dry_run:
        value = {'mode':'DRY_RUN_NO_COPY','files':len(rels),'target':str(target),'godot_invoked':False}
        print(json.dumps(value, ensure_ascii=False)); return value
    target.mkdir(parents=True, exist_ok=False)
    for rel in rels:
        src = source / rel
        if checked(src) != src or sha(src) != hashes[rel]: raise ValueError('复制前源码变化: ' + rel)
        dst = target / rel; dst.parent.mkdir(parents=True, exist_ok=True)
        if rel in transformed:
            with dst.open('x', encoding='utf-8', newline='\n') as stream: stream.write(transformed[rel])
        else:
            with src.open('rb') as reader, dst.open('xb') as writer: shutil.copyfileobj(reader, writer)
            if sha(dst) != hashes[rel]: raise ValueError('复制校验失败: ' + rel)
    if any(sha(source / rel) != hashes[rel] for rel in rels): raise ValueError('复制后源码变化')
    if explicit:
        with (target / NAME).open('x', encoding='utf-8', newline='\n') as stream: stream.write(transformed[NAME])
        from release_contract import select
        select(target, preset, 'windows', role)
    report = {'source':str(source),'target':str(target),'prepared':True,'godot_invoked':False,'native_loaded':False,'source_files':hashes,'transformed':sorted(transformed),'files':{rel:sha(target / rel) for rel in rels}, 'classification':'CANDIDATE_SOURCE_NOT_LOCKED','preset':preset,'explicit_target':explicit,'allowed_root':str(checked(allowed_root)) if allowed_root else str(scratch_root())}
    if explicit: report['files'][NAME] = sha(target / NAME)
    write_new_json(manifest_path, report)
    verify(target, manifest_path)
    print(json.dumps({'mode':'PREPARED','files':len(rels),'manifest':str(manifest_path),'godot_invoked':False}, ensure_ascii=False))
    return report


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('--source', type=Path, required=True); p.add_argument('--target', type=Path, required=True); p.add_argument('--manifest', type=Path, required=True); p.add_argument('--prepare', action='store_true')
    p.add_argument('--preset'); p.add_argument('--role', choices=('client','server','signaling')); p.add_argument('--executable'); p.add_argument('--runtime-files', help='显式 JSON source/target 数组'); p.add_argument('--allowed-root', type=Path)
    a = p.parse_args(argv)
    prepare(a.source, a.target, a.manifest, dry_run=not a.prepare, preset=a.preset, role=a.role, executable=a.executable, runtime_files=json.loads(a.runtime_files) if a.runtime_files is not None else None, allowed_root=a.allowed_root)
    return 0

if __name__ == '__main__':
    try: raise SystemExit(main())
    except (OSError, ValueError) as exc: raise SystemExit(f'BLOCK: {exc}')
