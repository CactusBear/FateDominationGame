"""G04：隔离 scratch 中验证迁移入口，不运行发行 EXE。"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = Path(os.environ['TMPDIR']).resolve()
RELEASE = ROOT / 'tools/release/release_prepare.py'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MigrationTests(unittest.TestCase):
    def test_migrated_entry_has_real_cli(self):
        self.assertTrue(RELEASE.is_file(), 'G04 迁移入口尚未落地')
        result = subprocess.run([sys.executable, '-B', str(RELEASE), '--help'], capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        for option in (b'--preset', b'--output', b'--project', b'--manifest'):
            self.assertIn(option, result.stdout)

    def test_g03_complete_module_copy_compatible(self):
        tool = load('g04_copy_data', ROOT / 'tools/copy_data_after_export.py')
        with tempfile.TemporaryDirectory(prefix='g04-copy-', dir=SCRATCH) as temp:
            destination = Path(temp) / 'new-output'
            copied, skipped = tool.copy_data(destination, tool.PROJECT_ROOT)
            expected = {p.relative_to(tool.DATA_DIR).as_posix(): p.read_bytes()
                        for p in tool.DATA_DIR.rglob('*') if p.is_file() and p.suffix != '.import'}
            actual = {p.relative_to(destination / 'data').as_posix(): p.read_bytes()
                      for p in (destination / 'data').rglob('*') if p.is_file()}
            self.assertEqual(actual, expected)
            self.assertEqual(copied, len(expected))
            self.assertGreaterEqual(skipped, 0)

    def test_plan_propagates_explicit_project_and_rejects_unimplemented_platform(self):
        release = load('g04_release', RELEASE)
        project = SCRATCH / 'round9-plan-project'; output = SCRATCH / 'round9-plan-output'
        project.mkdir(exist_ok=True)
        (project / 'export_presets.cfg').write_text('[preset.0]\nname="Windows Client"\nplatform="Windows Desktop"\ndedicated_server=false\n[preset.0.options]\nbinary_format/embed_pck=false\n', encoding='utf-8')
        (project / 'data').mkdir(exist_ok=True)
        (project / 'release_contract.json').write_text(json.dumps({'version':1,'targets':[{'preset':'Windows Client','platform':'windows','role':'client','executable':'FateDomination.exe','runtime_files':[]}]}), encoding='utf-8')
        value = release.plan(project, output, SCRATCH / 'godot.exe', 'Windows Client')
        self.assertIn('--project', value['commands'][1])
        self.assertIn(str(project.resolve()), value['commands'][1])
        with self.assertRaises(ValueError):
            release.plan(project, output, SCRATCH / 'godot.exe', 'Linux', platform='linux')


if __name__ == '__main__':
    unittest.main()
