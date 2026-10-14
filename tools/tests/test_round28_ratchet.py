"""Round28: real CLI, isolated E-drive fixtures; never mutate production."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
TOOLS = REPO / 'tools'


def load(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class Round28Ratchet(unittest.TestCase):
    def setUp(self):
        # Explicit E-drive ownership; no windows or Godot processes.
        self.temp = tempfile.TemporaryDirectory(prefix='round28-ratchet-', dir=str(REPO.parent))
        self.addCleanup(self.temp.cleanup)
        self.parent = Path(self.temp.name)
        self.root = self.parent / 'authorized'
        (self.root / 'scripts').mkdir(parents=True)
        self.gate = load('check_layer_deps')

    def put(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
        return path

    def cli(self, tool, root=None, *extra):
        result = subprocess.run([sys.executable, str(TOOLS / (tool + '.py')),
                                 '--root', str(root or self.root), '--json', *extra],
                                capture_output=True, text=True, encoding='utf-8', timeout=30)
        data = json.loads(result.stdout)
        self.assertEqual(result.returncode, data['exit_code'], result.stderr)
        return result.returncode, data

    def baseline(self):
        self.assertEqual(len(self.gate.ALLOWLIST), 80)
        for name in {site.path for site in self.gate.ALLOWLIST}:
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / name, destination)
        code, data = self.cli('check_layer_deps')
        self.assertEqual(code, 0, data)
        self.assertEqual(data['findings'], 80)

    def test_ignored_tests_helper_comments_and_deleted_freeze(self):
        self.baseline()
        self.put('.gitignore', 'tests/\nreports/\n')
        self.put('tests/helper/new.gd', '# EffectManager._comment()\nvar doc = "GameProgress._string"\nDummyBot._real()\n')
        code, data = self.cli('check_layer_deps')
        self.assertEqual(code, 1)
        self.assertEqual([(f['rule'], f['target']) for f in data['new']], [('private', 'DummyBot._real')])
        (self.root / 'tests/helper/new.gd').unlink()
        self.put('reports/freeze/scripts/copy.gd', 'EffectManager._copied()\n')
        self.assertEqual(self.cli('check_layer_deps')[1]['new'][0]['path'], 'reports/freeze/scripts/copy.gd')
        shutil.rmtree(self.root / 'reports/freeze')
        self.assertEqual(self.cli('check_layer_deps')[0], 0)
        # A directory ending .gd is not a source file and must not make ERROR.
        (self.root / 'tests/not_a_source.gd').mkdir()
        self.assertEqual(self.cli('check_layer_deps')[0], 0)

    def test_real_stale_and_duplicate_multiset(self):
        self.baseline()
        findings = self.gate.scan(self.root)
        finding = next(f for f in findings if sum(o.path == f.path and o.line == f.line for o in findings) == 1)
        path = self.root / finding.path
        lines = path.read_text(encoding='utf-8-sig').splitlines(keepends=True)
        del lines[finding.line - 1]
        path.write_text(''.join(lines), encoding='utf-8')
        code, data = self.cli('check_layer_deps')
        self.assertEqual(code, 1)
        self.assertEqual(len(data['stale']), 1)
        self.assertEqual(data['new'], [])
        site = self.gate.ExceptionSite('private', 'tests/two.gd', 'EffectManager._same', 'EffectManager._same()', 1)
        self.put(site.path, site.code + '\n' + site.code + '\n')
        actual = [f for f in self.gate.scan(self.root) if f.path == site.path]
        self.assertEqual(self.gate.evaluate(actual, (site, site)), ([], []))
        self.assertEqual(len(self.gate.evaluate(actual, (site,))[0]), 1)
        self.assertEqual(len(self.gate.evaluate(actual[:1], (site, site))[1]), 1)
        # Duplicate real occurrence is NEW, not a directory-wide waiver.
        (self.root / site.path).unlink()
        self.baseline()
        site = next(s for s in self.gate.ALLOWLIST if s.rule == 'private')
        with (self.root / site.path).open('a', encoding='utf-8') as stream:
            stream.write('\n' + site.code + '\n')
        self.assertEqual(len(self.cli('check_layer_deps')[1]['new']), 1)

    def test_authorized_root_parent_child_missing(self):
        self.baseline()
        for wrong in (self.parent, self.root / 'scripts', self.parent / 'absent'):
            self.assertEqual(self.cli('check_layer_deps', wrong)[0], 2)
        self.put('scripts/systematic/outside_layer.gd', 'var label = "res://scripts/game_scene/ui.gd"\n')
        self.assertEqual(self.cli('check_layer_deps')[0], 0)
        self.put('scripts/system/inside.gd', 'const UI = "res://scripts/game_scene/ui.gd"\n')
        self.assertEqual(self.cli('check_layer_deps')[1]['new'][0]['rule'], 'layer')

    def test_inventory_new_gone_drift_duplicates_bad_utf8(self):
        inventory = load('check_inventory_drift')
        self.put('scripts/base.gd', 'extends RefCounted\n')
        hashes = inventory.scan_scripts(self.root)
        manifest = self.put('docs/inventory.json', json.dumps({'script_count': len(hashes), 'files':
            [{'path': name, 'sha256': digest} for name, digest in hashes.items()]}))
        def run(root=None):
            return self.cli('check_inventory_drift', root, '--inventory', str(manifest))
        self.assertEqual(run()[0], 0)
        self.put('tests/helper.gd', 'EffectManager._real()\n')
        self.assertEqual(run()[0], 0)  # inventory owns scripts only; layer owns full tree
        self.put('scripts/helper.gd', 'extends RefCounted\n')
        self.assertEqual(run()[1]['new'], ['scripts/helper.gd'])
        self.put('scripts/base.gd', 'extends Resource\n')
        self.assertEqual(run()[1]['drift'], ['scripts/base.gd'])
        (self.root / 'scripts/base.gd').unlink()
        self.assertEqual(run()[1]['gone'], ['scripts/base.gd'])
        for wrong in (self.parent, self.root / 'scripts', self.parent / 'absent'):
            self.assertEqual(run(wrong)[0], 2)
        entry = {'path': 'scripts/base.gd', 'sha256': next(iter(hashes.values()))}
        manifest.write_text(json.dumps({'script_count': 2, 'files': [entry, entry]}), encoding='utf-8')
        self.assertEqual(run()[0], 2)
        self.assertIn('duplicate', run()[1]['error'])
        manifest.write_bytes(b'\xff')
        self.assertEqual(run()[0], 2)
        manifest.write_text(json.dumps({'script_count': 1, 'files': [{**entry, 'path': 'scripts/../outside.gd'}]}), encoding='utf-8')
        self.assertEqual(run()[0], 2)

    def test_symlink_outside_authorized_root(self):
        external = self.parent / 'external.gd'
        external.write_text('EffectManager._external()\n', encoding='utf-8')
        link = self.root / 'scripts/link.gd'
        try:
            link.symlink_to(external)
        except OSError as error:
            self.skipTest('Windows symlink privilege unavailable: ' + str(error))
        self.assertEqual(self.cli('check_layer_deps')[0], 2)
        inventory = load('check_inventory_drift')
        with self.assertRaisesRegex(ValueError, 'outside authorized root'):
            inventory.scan_scripts(self.root)


if __name__ == '__main__':
    unittest.main()
