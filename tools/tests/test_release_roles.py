"""显式角色契约的真实文件/命令矩阵，不启动 Godot 或发行 EXE。"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/release'))
import release_prepare as release
import package_audit as audit
import release_contract as contract_tool


class RoleTests(unittest.TestCase):
    def test_signaling_autoload_role_mismatch_and_runtime_integrity(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as temp:
            root = Path(temp); project = root / 'project'; project.mkdir()
            config = project / 'project.godot'
            config.write_text('config_version=5\n[network]\nsignaling_only=true\n', encoding='utf-8')
            (project / 'export_presets.cfg').write_text('[preset.0]\nname="Explicit"\nplatform="Windows Desktop"\ndedicated_server=true\n[preset.0.options]\nbinary_format/embed_pck=false\n', encoding='utf-8')
            (project / 'dependency.dll').write_bytes(b'real fixture bytes')
            target = {'preset':'Explicit','platform':'windows','role':'signaling','executable':'FateSignaling.exe','runtime_files':[{'source':'dependency.dll','target':'dependency.dll'}]}
            contract = project / 'release_contract.json'
            contract.write_text(json.dumps({'version':1,'targets':[target]}), encoding='utf-8')
            with self.assertRaises(ValueError): release.plan(project, root / 'bad-role', root / 'godot.exe', 'Explicit', role='server')
            with self.assertRaises(ValueError): release.plan(project, root / 'bad-preset', root / 'godot.exe', 'Unknown', role='signaling')
            config.write_text('[network]\nsignaling_only=true\n[autoload]\nGame="*res://game.gd"\n', encoding='utf-8')
            with self.assertRaises(ValueError): release.plan(project, root / 'autoload', root / 'godot.exe', 'Explicit', role='signaling')
            config.write_text('[network]\nsignaling_only=true\n', encoding='utf-8')
            package = root / 'package'
            contract_tool.copy_runtime(project, package, 'Explicit', 'windows', 'signaling')
            self.assertEqual((package / 'dependency.dll').read_bytes(), b'real fixture bytes')
            (package / 'dependency.dll').write_bytes(b'changed')
            with self.assertRaises(ValueError): contract_tool.copy_runtime(project, package, 'Explicit', 'windows', 'signaling')
            self.assertEqual((package / 'dependency.dll').read_bytes(), b'changed')
            (project / 'dependency.dll').unlink()
            with self.assertRaises(ValueError): release.plan(project, root / 'missing-dependency', root / 'godot.exe', 'Explicit', role='signaling')

    def test_audit_rejects_missing_game_data_and_missing_contract(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as temp:
            root = Path(temp); project = root / 'project'; project.mkdir()
            (project / 'export_presets.cfg').write_text('[preset.0]\nname="Explicit"\nplatform="Windows Desktop"\ndedicated_server=false\n[preset.0.options]\nbinary_format/embed_pck=false\n', encoding='utf-8')
            package = root / 'package'; package.mkdir()
            (package / 'FateDomination.exe').write_bytes(b'exe')
            (package / 'FateDomination.pck').write_bytes(b'not a pck')
            with self.assertRaises(ValueError):
                audit.audit(project, package, root / 'report.json', 'Explicit')
            (project / 'release_contract.json').write_text(json.dumps({'version':1,'targets':[{'preset':'Explicit','platform':'windows','role':'client','executable':'FateDomination.exe','runtime_files':[]}]}), encoding='utf-8')
            with self.assertRaises(ValueError):
                audit.audit(project, package, root / 'report2.json', 'Explicit')

    def test_role_matrix_and_missing_declaration(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as temp:
            root = Path(temp)
            for role in ('client', 'server', 'signaling'):
                with self.subTest(role=role):
                    project = root / role
                    project.mkdir()
                    (project / 'project.godot').write_text('config_version=5\n[network]\nsignaling_only=true\n', encoding='utf-8')
                    (project / 'export_presets.cfg').write_text(
                        '[preset.0]\nname="Explicit"\nplatform="Windows Desktop"\n'
                        f'dedicated_server={str(role != "client").lower()}\n'
                        '[preset.0.options]\nbinary_format/embed_pck=false\n', encoding='utf-8')
                    target = {'preset':'Explicit', 'platform':'windows', 'role':role,
                              'executable': 'FateSignaling.exe' if role == 'signaling' else ('FateServer.exe' if role == 'server' else 'FateDomination.exe'),
                              'runtime_files': []}
                    contract = project / 'release_contract.json'
                    contract.write_text(json.dumps({'version':1, 'targets':[target]}), encoding='utf-8')
                    if role != 'signaling':
                        (project / 'data').mkdir()
                        (project / 'data/runtime.json').write_text('{}', encoding='utf-8')
                    value = release.plan(project, root / ('output-' + role), root / 'godot.exe', 'Explicit', role=role)
                    copies = [c for c in value['commands'] if any('copy_data_after_export.py' in x for x in c)]
                    self.assertEqual(len(copies), int(role != 'signaling'))
                    if copies:
                        result = subprocess.run(copies[0], capture_output=True)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        (project / 'data/runtime.json').unlink()
                        (project / 'data').rmdir()
                        with self.assertRaises(ValueError):
                            release.plan(project, root / ('missing-data-' + role), root / 'godot.exe', 'Explicit', role=role)
                    contract.unlink()
                    with self.assertRaises(ValueError):
                        release.plan(project, root / ('undeclared-' + role), root / 'godot.exe', 'Explicit', role=role)


if __name__ == '__main__':
    unittest.main()