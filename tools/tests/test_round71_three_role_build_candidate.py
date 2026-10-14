"""R71 diagnostic snapshot boundary tests; no Godot or native load."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('r71_freeze', REPO / 'tools/release/round56_three_role_freeze.py')
subject = importlib.util.module_from_spec(spec)
spec.loader.exec_module(subject)


class SnapshotTests(unittest.TestCase):
    def test_snapshot_copy_is_exact_not_approval(self):
        self.assertTrue(callable(getattr(subject, 'diagnostic_snapshot', None)), 'diagnostic snapshot API missing')
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as tmp:
            root = Path(tmp); source = root / 'source'; source.mkdir()
            (source / 'a.txt').write_text('first')
            def inventory(_):
                files = {'a.txt': subject.sha(source / 'a.txt')}
                return {'source_files': files, 'source_fingerprint': subject.fingerprint(files)}
            with patch.object(subject, 'current_inventory', inventory):
                result = subject.diagnostic_snapshot(source, root / 'attempts')
            self.assertEqual(result['inventory']['source_files'], {'a.txt': subject.sha(Path(result['snapshot']) / 'a.txt')})
            self.assertEqual(result['classification'], 'BUILD_ONLY_DIAGNOSTIC_NOT_RELEASE_APPROVAL')
            self.assertNotIn('ready_token', result)
            self.assertEqual(len(result['attempts']), 1)

    def test_diagnostic_cli_requires_explicit_build_authorization(self):
        with self.assertRaisesRegex(ValueError, 'BUILD_ONLY_AUTHORIZATION_REQUIRED'):
            subject.diagnostic_build(None, None, None, None, None, authorized=False)

    def test_diagnostic_cli_rejects_mixed_final_or_runtime_stage(self):
        for extra in ('--build', '--inventory', '--run-formal', '--ready-token'):
            args = ['--build-only-diagnostic', extra]
            if extra == '--ready-token': args.append('nonexistent.json')
            self.assertEqual(subject.main(args), 2)

    def test_later_source_difference_preserves_exact_hash_pair(self):
        before = {'a': 'old', 'removed': 'old'}
        after = {'a': 'new', 'added': 'new'}
        self.assertEqual(subject.file_drift(before, after), {
            'added': ['added'], 'removed': ['removed'],
            'changed': {'a': {'before': 'old', 'after': 'new'}}})

    def test_one_reacquisition_can_accept_new_exact_snapshot(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as tmp:
            root = Path(tmp); source = root / 'source'; source.mkdir()
            (source / 'a.txt').write_text('first')
            def inventory(_):
                files = {'a.txt': subject.sha(source / 'a.txt')}
                return {'source_files': files, 'source_fingerprint': subject.fingerprint(files)}
            original = subject.shutil.copyfile
            calls = []
            def drift_once(src, dst):
                original(src, dst); calls.append(dst)
                if len(calls) == 1: src.write_text('second')
            with patch.object(subject, 'current_inventory', inventory), patch.object(subject.shutil, 'copyfile', drift_once):
                result = subject.diagnostic_snapshot(source, root / 'attempts')
            self.assertEqual(len(result['attempts']), 2)
            self.assertEqual(result['attempts'][0]['status'], 'REJECTED')
            self.assertEqual(result['attempts'][1]['status'], 'EXACT_COPY_VERIFIED')
            self.assertEqual((Path(result['snapshot']) / 'a.txt').read_text(), 'second')

    def test_persistent_drift_stops_after_two_preserved_attempts(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as tmp:
            root = Path(tmp); source = root / 'source'; source.mkdir()
            (source / 'a.txt').write_text('first')
            def inventory(_):
                files = {'a.txt': subject.sha(source / 'a.txt')}
                return {'source_files': files, 'source_fingerprint': subject.fingerprint(files)}
            original = subject.shutil.copyfile
            def drift(src, dst):
                original(src, dst)
                src.write_text(src.read_text() + 'drift')
            with patch.object(subject, 'current_inventory', inventory), patch.object(subject.shutil, 'copyfile', drift):
                with self.assertRaisesRegex(ValueError, 'SOURCE_DRIFT_AFTER_ONE_REACQUISITION'):
                    subject.diagnostic_snapshot(source, root / 'attempts')
            import json
            receipt = json.loads((root / 'attempts/acquisition.json').read_text())
            self.assertEqual(len(receipt['attempts']), 2)
            self.assertTrue(all(r['drift']['changed'] for r in receipt['attempts']))
            self.assertTrue(all(Path(r['snapshot']).is_dir() for r in receipt['attempts']))


if __name__ == '__main__':
    unittest.main()
