"""Dedicated R64 tests: no Godot, export, credentials or production writes."""
import contextlib
import io
import unittest
import json
import os
from pathlib import Path
import tempfile
from tools.release import round56_three_role_freeze as entry


class RuntimeEntryTest(unittest.TestCase):
    def test_run_formal_requires_explicit_artifact_manifest(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = entry.main(['--run-formal'])
        self.assertEqual(code, 2)
        self.assertIn('ARTIFACT_MANIFEST_REQUIRED', output.getvalue())


    def test_unsupported_phase_never_passes(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = entry.main(['--run-formal', '--artifact-manifest', 'missing.json', '--run-phase', 'invented'])
        self.assertEqual(code, 2)
        self.assertIn('UNSUPPORTED_RUN_PHASE', output.getvalue())

    def test_fake_artifact_rejected(self):
        with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as tmp:
            root = Path(tmp); (root/'Fake.exe').write_bytes(b'not an exe')
            (root/'Fake.pck').write_bytes(b'not a PCK')
            files = {p.name: entry.sha(p) for p in root.iterdir()}
            row = {'package': str(root), 'package_files': files, 'native_files': {},
                   'source_fingerprint': 'a'*64,
                   'declaration': {'role': 'client', 'platform': 'windows', 'executable': 'Fake.exe'}}
            with self.assertRaisesRegex(ValueError, 'INVALID_PE|DATA_REQUIRED|NATIVE'):
                entry.validate_artifact('client', row)

    def test_missing_role_refused(self):
        with self.assertRaisesRegex(ValueError, 'MISSING_ROLE'):
            entry.validate_roles({'roles': {}}, ['server'])

    def test_hash_drift_refused_before_execution(self):
        with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as tmp:
            root = Path(tmp); (root/'Fake.exe').write_bytes(b'changed')
            row = {'package': str(root), 'package_files': {'Fake.exe': 'a'*64},
                   'native_files': {}, 'source_fingerprint': 'a'*64,
                   'declaration': {'role': 'client', 'platform': 'windows', 'executable': 'Fake.exe'}}
            with self.assertRaisesRegex(ValueError, 'PACKAGE_HASH_DRIFT'):
                entry.validate_artifact('client', row)

    def test_nonzero_and_unrun_not_green(self):
        result, code = entry.runtime_verdict('all', {'client': {'status': 'FAIL', 'exit_code': 7},
                                                  'server': {'status': 'NOTRUN'},
                                                  'signaling': {'status': 'NOTRUN'}})
        self.assertEqual(code, 7)
        self.assertNotEqual(result, 'PASS')
        self.assertEqual(entry.runtime_verdict('all', {'client': {'status': 'PASS'}})[1], 3)
        self.assertEqual(entry.runtime_verdict('signaling-ready', {'signaling-ready': {'status': 'PASS'}}),
                         ('PARTIAL_NOT_THREE_ROLE_PASS', 0))


    def test_status_requires_original_fields_and_full_native_contract(self):
        from tools.diagnostics.round53_signaling_initialization import METHODS
        result = dict.fromkeys(['game_port', 'rooms', 'attached_clients', 'pending_clients',
                               'relay_port', 'server_name', 'motd'], 0)
        result.update(native_capabilities={name: {'exists': True, 'can_instantiate': True,
                      'methods': dict.fromkeys(methods, True)} for name, methods in METHODS.items()},
                      validation_policy={'enabled': True, 'budget': 15}, worker_pool={'max_threads': 20})
        receipt = {'ok': True, 'result': result}
        self.assertIs(entry.validate_status(receipt), receipt)
        del result['motd']
        with self.assertRaisesRegex(ValueError, 'ORIGINAL_FIELDS'):
            entry.validate_status(receipt)
        result['motd'] = ''
        result['native_capabilities']['FateProcessOwner']['methods']['release'] = False
        with self.assertRaisesRegex(ValueError, 'METHODS_MISMATCH'):
            entry.validate_status(receipt)
        result['native_capabilities']['FateProcessOwner']['methods']['release'] = True
        result['validation_policy']['budget'] = 10
        with self.assertRaisesRegex(ValueError, 'DEFAULT15_POOL20'):
            entry.validate_status(receipt)

    def test_signal_nonzero_raw_exit_is_preserved(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        import struct
        with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as tmp:
            root = Path(tmp); runner = root/'runner.exe'
            runner.write_bytes(b'MZ' + bytes(58) + struct.pack('<I', 64) + b'PE\0\0\x64\x86')
            args = SimpleNamespace(signal_runner=runner, signal_runner_sha256=entry.sha(runner))
            row = {'package': str(root), 'declaration': {'executable': 'not-launched.exe'}}
            with patch('tools.diagnostics.round53_signaling_initialization.run',
                       return_value=({'exit': 17}, '')), patch('subprocess.Popen', side_effect=AssertionError('unit must not launch')):
                result = entry.signal_phase(root, row, args, negative=False)
            self.assertEqual(result['status'], 'FAIL')
            self.assertEqual(result['raw_exit_code'], 17)
            self.assertEqual(result['exit_code'], 17)

    def test_client_command_is_official_opening_without_override(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as tmp:
            root = Path(tmp); manifest = root/'manifest.json'; manifest.write_text('{}')
            document = {'roles': {'client': {'package': str(root), 'declaration': {'executable': 'game.exe'}}}}
            args = SimpleNamespace(rsa_project=None)
            with patch('subprocess.Popen', side_effect=AssertionError('unit must not launch')):
                runner = entry.formal_runner(root, document, manifest, args)
                command = runner.command('client', ['--quit-after', '180'])
            self.assertEqual(command[0], str(root/'game.exe'))
            for option in ('--path', '--script', '--scene', '--headless'):
                self.assertNotIn(option, command)


    def test_same_fingerprint_cannot_hide_native_drift_between_roles(self):
        from unittest.mock import patch
        rows = {'client': {'source_fingerprint': 'a'*64, 'pck_sha256': 'b'*64,
                           'native_files': {'native.dll': 'c'*64}},
                'server': {'source_fingerprint': 'a'*64, 'pck_sha256': 'd'*64,
                           'native_files': {'native.dll': 'e'*64}}}
        with patch.object(entry, 'validate_artifact', side_effect=lambda role, row: rows[role]):
            with self.assertRaisesRegex(ValueError, 'CROSS_ROLE_NATIVE_HASH_DRIFT'):
                entry.validate_roles({'roles': {'client': {}, 'server': {}}}, ['client', 'server'])


if __name__ == '__main__':
    unittest.main()
