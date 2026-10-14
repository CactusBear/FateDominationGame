"""Python-only launcher declaration/copy regression; never launches Godot."""
from pathlib import Path
import json
import os
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools/release'))
import freeze_prepare
import human_test_candidate
import release_contract

SCRATCH = Path(os.environ.get('HUMAN_TEST_SCRATCH', 'E:/Caches/Hermes/cache/scratch')).resolve()


class LauncherDeclarationTests(unittest.TestCase):
    def test_role_inventory_contains_only_declared_launcher(self):
        for role, name in {'client': 'START-CLIENT.cmd', 'server': 'START-SERVER.cmd',
                           'signaling': 'START-SIGNALING.cmd'}.items():
            with self.subTest(role=role):
                declaration = next(t for t in release_contract.declarations(REPO) if t['role'] == role)
                mapping = {item['target']: item['source'] for item in declaration['runtime_files']}
                self.assertIn(name, mapping)
                self.assertIn('Launch-HumanTest.ps1', mapping)
                files = freeze_prepare.inventory(REPO, role=role, cold=True)
                self.assertIn(mapping[name], files)
                self.assertIn(mapping['Launch-HumanTest.ps1'], files)
                selected = {Path(p).name for p in files if p.endswith('.cmd')}
                self.assertEqual(selected, {name})
                launcher_sources = set(mapping[t] for t in (name, 'Launch-HumanTest.ps1'))
                before = freeze_prepare.transform(REPO, declaration['preset'],
                                                 [p for p in files if p not in launcher_sources], role)
                after = freeze_prepare.transform(REPO, declaration['preset'], files, role)
                self.assertEqual(after, before, 'Launcher declarations must not alter export filters')

    def test_build_role_declaration_uses_launcher_contract(self):
        import round56_three_role_freeze
        for role, preset, executable in (
            ('client', 'FateDomination_demo_v1', 'FateDomination.exe'),
            ('server', 'FateServer Windows', 'FateServer.exe'),
            ('signaling', 'FateServer Windows', 'FateSignaling.exe'),
        ):
            with self.subTest(role=role):
                expected = next(t for t in release_contract.declarations(REPO) if t['role'] == role)
                self.assertEqual(round56_three_role_freeze.role_declaration(REPO, preset, role, executable), expected)

    def test_declared_runtime_copy_places_launcher_and_helper_at_role_root(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.assertEqual(SCRATCH.drive.upper(), 'E:')
        with tempfile.TemporaryDirectory(dir=SCRATCH) as temp:
            root = Path(temp)
            for role, name in {'client': 'START-CLIENT.cmd', 'server': 'START-SERVER.cmd',
                               'signaling': 'START-SIGNALING.cmd'}.items():
                with self.subTest(role=role):
                    project = root / ('project-' + role)
                    project.mkdir()
                    declaration = next(t for t in release_contract.declarations(REPO) if t['role'] == role)
                    # Synthetic project validates only the real external-file copier.
                    # It contains no EXE/PCK, and is not a candidate/build receipt.
                    declaration = {**declaration, 'runtime_files': [item for item in declaration['runtime_files']
                                                                    if item['target'] in (name, 'Launch-HumanTest.ps1')]}
                    (project / 'project.godot').write_text('[network]\nsignaling_only=true\n', encoding='utf-8')
                    if role != 'signaling':
                        (project / 'data').mkdir()
                    (project / release_contract.NAME).write_text(
                        freeze_prepare.contract_text(declaration), encoding='utf-8')
                    for item in declaration['runtime_files']:
                        source = project / item['source']
                        source.parent.mkdir(parents=True, exist_ok=True)
                        source.write_bytes((REPO / item['source']).read_bytes())
                    output = root / ('package-' + role)
                    release_contract.copy_runtime(project, output, declaration['preset'], 'windows', role)
                    self.assertEqual({p.name for p in output.iterdir()}, {name, 'Launch-HumanTest.ps1'})
                    for item in declaration['runtime_files']:
                        self.assertEqual((output / item['target']).read_bytes(), (REPO / item['source']).read_bytes())
                    (output / name).write_bytes(b'negative-fixture-not-a-launcher')
                    with self.assertRaisesRegex(ValueError, '已导出运行依赖不匹配'):
                        release_contract.copy_runtime(project, output, declaration['preset'], 'windows', role)

    def test_packager_rejects_missing_launcher_declaration(self):
        with self.assertRaisesRegex(human_test_candidate.CandidateError, 'DECLARED_LAUNCHER_REQUIRED'):
            human_test_candidate.launcher_files({'runtime_files': []}, 'client')

    def test_packager_rejects_missing_helper_file(self):
        runtime = [{'source': 'release/human-test/' + name, 'target': name}
                   for name in ('START-CLIENT.cmd', 'Launch-HumanTest.ps1')]
        document = {'roles': {'client': {'package': str(SCRATCH / 'not-used'),
                                        'package_files': {'START-CLIENT.cmd': '0' * 64},
                                        'declaration': {'runtime_files': runtime}}}}
        with self.assertRaisesRegex(human_test_candidate.CandidateError, 'PACKAGE_DECLARED_LAUNCHER_MISSING'):
            human_test_candidate.copy_roles(SCRATCH / 'not-written', document, ['client'])

    def test_packager_preserves_declared_template_bytes(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.assertEqual(SCRATCH.drive.upper(), 'E:')
        with tempfile.TemporaryDirectory(dir=SCRATCH) as temp:
            root = Path(temp)
            for role, name in {'client': 'START-CLIENT.cmd', 'server': 'START-SERVER.cmd',
                               'signaling': 'START-SIGNALING.cmd'}.items():
                with self.subTest(role=role):
                    package = root / ('source-' + role)
                    package.mkdir()
                    files = {}
                    runtime = []
                    for target in (name, 'Launch-HumanTest.ps1'):
                        source = 'release/human-test/' + target
                        raw = (REPO / source).read_bytes()
                        (package / target).write_bytes(raw)
                        files[target] = human_test_candidate.sha(package / target)
                        runtime.append({'source': source, 'target': target})
                    declaration = {'role': role, 'runtime_files': runtime, 'executable': 'fixture.exe'}
                    document = {'roles': {role: {'package': str(package), 'package_files': files,
                                                'declaration': declaration}}}
                    destination = root / ('destination-' + role)
                    destination.mkdir()
                    human_test_candidate.copy_roles(destination, document, [role])
                    for target in files:
                        self.assertEqual((destination / role / target).read_bytes(), (package / target).read_bytes())


if __name__ == '__main__':
    unittest.main()
