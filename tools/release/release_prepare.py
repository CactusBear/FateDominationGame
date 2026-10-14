"""G04 显式发行准备入口：默认 dry-run；真实导出必须由调用方显式执行。"""
from __future__ import annotations
import argparse, json, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from path_safety import checked, new_output, write_new_json
from freeze_prepare import verify
from package_audit import preset_options
from release_contract import select

HERE = Path(__file__).resolve().parent
COPY_TOOL = HERE.parent / 'copy_data_after_export.py'
FREEZE_TOOL = HERE / 'freeze_prepare.py'
AUDIT_TOOL = HERE / 'package_audit.py'
RENDERING_METHODS = ('forward_plus', 'mobile', 'gl_compatibility')


def plan(project, output, godot, preset, platform='windows', role='client', *, rendering_method=None):
    if platform != 'windows':
        raise ValueError('当前发行准入只实现 Windows；拒绝生成未实现平台计划')
    if rendering_method is not None and rendering_method not in RENDERING_METHODS:
        raise ValueError('未知 Godot rendering_method，拒绝生成发行计划')
    project = checked(project); output = new_output(output, (project,)); godot = checked(godot)
    options = preset_options(project, preset)
    target = select(project, preset, platform, role)
    if options['dedicated_server'] != (role != 'client'): raise ValueError('preset 与 role 不一致')
    exe = target['executable']
    destination = output / platform / role
    # 仅显式本机覆盖；不按发行角色推测，也不改写 project.godot。
    renderer_args = [] if rendering_method is None else ['--rendering-method', rendering_method]
    godot_command = [str(godot), '--headless', *renderer_args]
    commands = [
        [*godot_command, '--path', str(project), '--export-release', preset, str(destination / exe)],
    ]
    if role in ('client', 'server'):
        commands.append([sys.executable, str(COPY_TOOL), '--project', str(project), '--output-dir', str(destination)])
    if target['runtime_files']:
        commands.append([sys.executable, str(HERE / 'release_contract.py'), '--project', str(project), '--preset', preset, '--platform', platform, '--role', role, '--output-dir', str(destination)])
    commands.append([sys.executable, str(AUDIT_TOOL), '--project', str(project), '--preset', preset, '--platform', platform, '--role', role, '--package', str(destination), '--output', str(output / f'{platform}-{role}-audit.json')])
    return {'mode':'DRY_RUN_GODOT_NOT_INVOKED','classification':'CANDIDATE_SOURCE_NOT_LOCKED','source':str(project),'output':str(output),'preset':preset,'platform':platform,'role':role,'commands':commands,'import_command':[*godot_command, '--editor', '--path', str(project), '--import'],'godot_invoked':False,'native_loaded':False}


def check_export_log(payload):
    if b'SCRIPT ERROR:' in payload or b'ERROR:' in payload:
        raise ValueError('Godot 退出码为零但日志含错误，拒绝验收')


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project', type=Path, required=True); p.add_argument('--output', type=Path, required=True); p.add_argument('--godot', type=Path, required=True); p.add_argument('--preset', required=True); p.add_argument('--platform', choices=('windows',), default='windows'); p.add_argument('--role', choices=('client','server','signaling'), default='client'); p.add_argument('--manifest', type=Path, required=True); p.add_argument('--execute', action='store_true'); p.add_argument('--credential-free-project', action='store_true')
    p.add_argument('--freeze-manifest', type=Path)
    p.add_argument('--allowed-root', type=Path)
    p.add_argument('--rendering-method', choices=RENDERING_METHODS, help='显式本机 Godot import/export 渲染器覆盖；省略保留工程默认，不按 role 推断')
    a = p.parse_args(argv); value = plan(a.project, a.output, a.godot, a.preset, a.platform, a.role, rendering_method=a.rendering_method)
    protected = [a.project, a.output]
    if a.freeze_manifest:
        frozen = verify(a.project, a.freeze_manifest)
        protected.extend((Path(frozen['source']), a.freeze_manifest))
        new_output(a.output, (Path(frozen['source']), a.project), scratch=True, allowed_root=a.allowed_root)
        if a.allowed_root and checked(a.allowed_root) != checked(frozen['allowed_root']): raise ValueError('导出与冻结允许根不一致')
        value['freeze_manifest'] = str(checked(a.freeze_manifest))
        value['original_source'] = frozen['source']
        value['commands'][-1].extend(['--freeze-manifest', str(checked(a.freeze_manifest))])
    manifest_path = new_output(a.manifest, protected, allowed_root=a.allowed_root)
    if not a.execute:
        write_new_json(manifest_path, value); print(json.dumps({'mode':value['mode'],'manifest':str(manifest_path),'godot_invoked':False}, ensure_ascii=False)); return 0
    if not a.freeze_manifest: raise ValueError('执行必须提供已校验冻结清单')
    if not a.credential_free_project: raise ValueError('执行必须显式确认隔离工程无凭据')
    if not checked(a.godot).is_file(): raise ValueError('执行要求存在的 Godot 可执行文件')
    if a.role != 'signaling' and not any(p.is_file() and p.suffix != '.import' for p in (checked(a.project) / 'data').rglob('*')): raise ValueError('执行拒绝空 data')
    output = new_output(a.output, protected[:1], scratch=True, allowed_root=a.allowed_root)
    output.mkdir(parents=True, exist_ok=False)
    (output / a.platform / a.role).mkdir(parents=True)
    logs = []
    for index, command in enumerate([value['import_command'], *value['commands']]):
        result = subprocess.run(command, cwd=checked(a.project), capture_output=True, timeout=900)
        log = output / f'step-{index}.log'
        log.write_bytes(result.stdout + b'\nSTDERR\n' + result.stderr)
        logs.append({'command':command,'exit_code':result.returncode,'log':str(log)})
        if result.returncode: raise ValueError(f'步骤失败，exit_code={result.returncode} (0x{result.returncode & 0xffffffff:08X})，证据: {log}')
        if index < 2: check_export_log(result.stdout + result.stderr)
    value['steps'] = logs
    value['mode'] = 'EXECUTED_STATIC_AUDIT_RUNTIME_PENDING'; value['godot_invoked'] = True
    value['native_loaded'] = 'UNKNOWN_GODOT_EDITOR_MAY_LOAD_GDEXTENSION'
    write_new_json(manifest_path, value); return 0

if __name__ == '__main__':
    try: raise SystemExit(main())
    except (OSError, ValueError) as exc: raise SystemExit(f'BLOCK: {exc}')
