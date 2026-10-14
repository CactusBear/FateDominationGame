"""Round35：发行渲染器必须显式声明，import/export 使用同一参数。"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.tests.test_release_prepare import ROOT, SCRATCH, load

release = load('round35_release', ROOT / 'tools/release/release_prepare.py')


class ReleaseRendererTests(unittest.TestCase):
    def test_explicit_renderer_reaches_import_and_export_for_every_role(self):
        with tempfile.TemporaryDirectory(prefix='round35-renderer-', dir=SCRATCH) as tmp:
            project = Path(tmp) / 'project'
            project.mkdir()
            (project / 'data').mkdir()
            original = '[network]\nsignaling_only=true\n\n[rendering]\nrenderer/rendering_method="forward_plus"\n'
            (project / 'project.godot').write_text(original, encoding='utf-8')
            for role in ('client', 'server', 'signaling'):
                preset = 'Explicit ' + role
                (project / 'export_presets.cfg').write_text(
                    f'[preset.0]\nname="{preset}"\nplatform="Windows Desktop"\n'
                    f'dedicated_server={str(role != "client").lower()}\n'
                    '[preset.0.options]\nbinary_format/embed_pck=false\n', encoding='utf-8')
                (project / 'release_contract.json').write_text(json.dumps({
                    'version': 1, 'targets': [{'preset': preset, 'platform': 'windows',
                    'role': role, 'executable': 'Fate.exe', 'runtime_files': []}]
                }), encoding='utf-8')
                try:
                    value = release.plan(project, Path(tmp) / ('output-' + role),
                                         Path(tmp) / 'godot.exe', preset, role=role,
                                         rendering_method='gl_compatibility')
                except TypeError as exc:
                    self.fail('发行入口没有显式 rendering_method 参数: ' + str(exc))
                for command in (value['import_command'], value['commands'][0]):
                    self.assertEqual(command.count('--rendering-method'), 1)
                    self.assertEqual(command[command.index('--rendering-method') + 1],
                                     'gl_compatibility')
                self.assertEqual((project / 'project.godot').read_text(encoding='utf-8'), original)
                default = release.plan(project, Path(tmp) / ('default-' + role),
                                       Path(tmp) / 'godot.exe', preset, role=role)
                self.assertEqual(default['import_command'], [str((Path(tmp) / 'godot.exe').resolve()),
                    '--headless', '--editor', '--path', str(project.resolve()), '--import'])
                self.assertEqual(default['commands'][0], [str((Path(tmp) / 'godot.exe').resolve()),
                    '--headless', '--path', str(project.resolve()), '--export-release', preset,
                    str((Path(tmp) / ('default-' + role) / 'windows' / role / 'Fate.exe').resolve())])
                for selected in (None, 'gl_compatibility'):
                    label = 'default' if selected is None else selected
                    manifest = Path(tmp) / f'cli-{role}-{label}.json'
                    command = [sys.executable, '-B', str(ROOT / 'tools/release/release_prepare.py'),
                               '--project', str(project), '--output', str(Path(tmp) / ('cli-output-' + role + label)),
                               '--godot', str(Path(tmp) / 'godot.exe'), '--preset', preset,
                               '--role', role, '--manifest', str(manifest)]
                    if selected is not None:
                        command.extend(['--rendering-method', selected])
                    cli = subprocess.run(command, capture_output=True, timeout=15)
                    self.assertEqual(cli.returncode, 0, cli.stderr)
                    actual = json.loads(manifest.read_text(encoding='utf-8'))
                    self.assertFalse(actual['godot_invoked'])
                    self.assertEqual(actual['mode'], 'DRY_RUN_GODOT_NOT_INVOKED')
                    self.assertEqual(actual['import_command'],
                                     default['import_command'] if selected is None else value['import_command'])
                    self.assertEqual('--rendering-method' in actual['commands'][0], selected is not None)
                for method in release.RENDERING_METHODS:
                    explicit = release.plan(project, Path(tmp) / ('explicit-' + role + method),
                                            Path(tmp) / 'godot.exe', preset, role=role,
                                            rendering_method=method)
                    self.assertIn(method, explicit['import_command'])
                    self.assertIn(method, explicit['commands'][0])

    def test_unknown_renderer_rejected_by_api_and_cli(self):
        with self.assertRaises(ValueError):
            release.plan(ROOT, SCRATCH / 'unused-round35', SCRATCH / 'godot.exe',
                         'unused', rendering_method='AUTO_BY_ROLE')
        result = subprocess.run([sys.executable, '-B', str(ROOT / 'tools/release/release_prepare.py'),
            '--project', str(ROOT), '--output', str(SCRATCH / 'unused-round35'),
            '--godot', str(SCRATCH / 'godot.exe'), '--preset', 'unused',
            '--manifest', str(SCRATCH / 'unused-round35.json'),
            '--rendering-method', 'AUTO_BY_ROLE'], capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 2)
        self.assertIn(b'invalid choice', result.stderr)

    def test_execute_errors_fail_closed_before_later_steps(self):
        # 这里只模拟外部 Godot，真实 main 的非零和日志拒绝控制流不替换。
        for failed_step in (0, 1):
            for code, payload in ((3221225477, b'normal editor output'),
                                  (-1073741819, b'normal editor output'),
                                  (139, b'normal editor output'),
                                  (0, b'SCRIPT ERROR: Parse Error'),
                                  (0, b'ERROR: Failed to load script')):
                with self.subTest(step=failed_step, code=code, payload=payload):
                    with tempfile.TemporaryDirectory(prefix='round35-reject-', dir=SCRATCH) as tmp:
                        root = Path(tmp)
                        project = root / 'project'; project.mkdir()
                        godot = root / 'godot.exe'; godot.write_bytes(b'fixture')
                        output = root / 'output'; manifest = root / 'release.json'
                        value = {'import_command': ['godot-import'],
                                 'commands': [['godot-export'], ['package-audit']]}
                        results = [subprocess.CompletedProcess([], 0, b'ok', b'') for _ in range(failed_step)]
                        results.append(subprocess.CompletedProcess([], code, payload, b''))
                        argv = ['--project', str(project), '--output', str(output), '--godot', str(godot),
                                '--preset', 'Explicit signaling', '--role', 'signaling',
                                '--manifest', str(manifest), '--freeze-manifest', str(root / 'freeze.json'),
                                '--execute', '--credential-free-project', '--rendering-method', 'gl_compatibility',
                                '--allowed-root', str(root)]
                        with patch.object(release, 'plan', return_value=value), \
                             patch.object(release, 'verify', return_value={'source': str(root / 'source'),
                                                                         'allowed_root': str(root)}), \
                             patch.object(release.subprocess, 'run', side_effect=results) as run:
                            with self.assertRaises(ValueError) as rejected:
                                release.main(argv)
                            self.assertEqual(run.call_count, failed_step + 1)
                            if code:
                                self.assertIn(f'exit_code={code}', str(rejected.exception))
                                self.assertIn(f'0x{code & 0xffffffff:08X}', str(rejected.exception))
                        self.assertFalse(manifest.exists(), '失败不得写入成功发行清单')
                        self.assertIn(payload, (output / f'step-{failed_step}.log').read_bytes())


if __name__ == '__main__':
    unittest.main()