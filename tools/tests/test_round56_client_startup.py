"""Consumer-only Python tests; fixture receipts never count as runtime evidence."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.release import round56_three_role_freeze as freeze


class ClientStartupConsumerTests(unittest.TestCase):
    def setUp(self):
        from tools.diagnostics import round53_exported_runtime as producer
        # PASS consumption also requires the producer's approved scratch root.
        scratch = producer.safe(Path('E:/Caches/Hermes/cache/scratch'))
        owned = self.enterContext(tempfile.TemporaryDirectory(
            prefix='round56-client-startup-', dir=scratch))
        self.enterContext(patch.dict(os.environ, {'TMPDIR': owned}))

    def test_independent_phase_is_not_original_client(self):
        self.assertIn('client-startup', freeze.RUN_PHASES)
        stages = {name: {'status': 'NOTRUN'} for name in freeze.RUN_PHASES}
        stages['client-startup'] = {'status': 'PASS', 'exit_code': 0}
        self.assertEqual(freeze.runtime_verdict('client-startup', stages),
                         ('PARTIAL_NOT_THREE_ROLE_PASS', 0))
        self.assertEqual(stages['client']['status'], 'NOTRUN')
        self.assertEqual(freeze.runtime_verdict('all', stages), ('INCOMPLETE_NOTRUN', 3))

    def fixture(self, base, status='PASS', code=0):
        from tools.diagnostics import round53_exported_runtime as producer
        files = {'project.godot': 'a' * 64}
        fp = freeze.fingerprint(files)
        document = {'source': str(base / 'source'), 'source_files': files,
                    'source_fingerprint': fp, 'roles': {'client': {
                        'package': str(base / 'package'), 'source_fingerprint': fp,
                        'declaration': {'role': 'client', 'platform': 'windows',
                                        'executable': 'FateDomination.exe'},
                        'package_files': {'FateDomination.exe': 'b' * 64,
                                          'FateDomination.pck': 'c' * 64}}}}
        manifest = base / 'manifest.json'
        manifest.write_text(json.dumps(document), encoding='utf-8')
        root = base / 'probe'; root.mkdir()
        receipt = {'schema': 'round53-client-startup-v1', 'stage': 'client-startup',
                   'owner': 'round53-client-startup', 'nonfinal': True, 'old_artifact': False,
                   'classification': 'STARTUP_ONLY_NOT_FINAL', 'root': str(root),
                   'artifact_manifest': str(manifest), 'artifact_manifest_sha256': freeze.sha(manifest),
                   'identity': producer.startup_identity(document), 'runs': [],
                   'stages': {'client-startup': {'status': status, 'exit_code': code}},
                   'exit_code': 0 if status == 'PASS' else 1}
        proof = root / 'runtime.json'; proof.write_text(json.dumps(receipt), encoding='utf-8')
        return manifest, proof, receipt

    def test_fabricated_pass_without_exit_receipt_rejected(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as tmp:
            manifest, proof, receipt = self.fixture(Path(tmp))
            self.assertTrue(callable(getattr(freeze, 'load_client_startup_proof', None)),
                            'hash-bound startup receipt consumer missing')
            with patch('subprocess.Popen', side_effect=AssertionError('consumer must not launch')):
                with self.assertRaisesRegex(ValueError, 'CLIENT_STARTUP_PASS_PROOF_REQUIRED'):
                    freeze.load_client_startup_proof(proof, freeze.sha(proof), manifest, freeze.sha(manifest))

    def test_formal_startup_pass_without_proof_rejected(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as tmp:
            manifest, proof, receipt = self.fixture(Path(tmp))
            stages = {name: {'status': 'NOTRUN'} for name in freeze.RUN_PHASES}
            stages['client-startup'] = {'status': 'PASS', 'exit_code': 0}
            formal = {'schema': 1, 'artifact_manifest': str(manifest),
                      'artifact_manifest_sha256': freeze.sha(manifest), 'run_phase': 'client-startup',
                      'stages': stages, 'classification': 'PARTIAL_NOT_THREE_ROLE_PASS', 'exit_code': 0}
            with self.assertRaisesRegex(ValueError, 'CLIENT_STARTUP_PROOF_REQUIRED'):
                freeze.validate_formal_receipt(formal, manifest, freeze.sha(manifest))

    def test_failed_proof_keeps_raw_exit_and_explicit_old_boundary(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as tmp:
            manifest, proof, receipt = self.fixture(Path(tmp), status='FAIL', code=17)
            receipt['old_artifact'] = True
            receipt['stages']['client-startup']['first_cause'] = 'original failure'
            proof.write_text(json.dumps(receipt), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'EXPLICIT_OLD_ARTIFACT'):
                freeze.load_client_startup_proof(proof, freeze.sha(proof), manifest, freeze.sha(manifest))
            result = freeze.load_client_startup_proof(proof, freeze.sha(proof), manifest,
                                                     freeze.sha(manifest), allow_old=True)
            self.assertEqual(result['status'], 'FAIL')
            self.assertEqual(result['raw_exit_code'], 17)
            self.assertEqual(result['exit_code'], 17)
            self.assertEqual(result['producer_stage'], receipt['stages']['client-startup'])
            self.assertTrue(result['nonfinal'])
            self.assertFalse(result['eligible_for_current_candidate'])

    def test_pinned_manifest_and_identity_hash_refusals(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as tmp:
            manifest, proof, receipt = self.fixture(Path(tmp), status='FAIL', code=7)
            with self.assertRaisesRegex(ValueError, 'MANIFEST_HASH_MISMATCH'):
                freeze.load_client_startup_proof(proof, freeze.sha(proof), manifest, 'd' * 64)
            receipt['identity']['exe_sha256'] = 'd' * 64
            proof.write_text(json.dumps(receipt), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'IDENTITY_MISMATCH'):
                freeze.load_client_startup_proof(proof, freeze.sha(proof), manifest, freeze.sha(manifest))
            with self.assertRaisesRegex(ValueError, 'PROOF_HASH_MISMATCH'):
                freeze.load_client_startup_proof(proof, 'd' * 64, manifest, freeze.sha(manifest))

    def test_exact_pck_missing_refused(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as tmp:
            manifest, proof, receipt = self.fixture(Path(tmp), status='FAIL', code=1)
            doc = json.loads(manifest.read_text(encoding='utf-8'))
            del doc['roles']['client']['package_files']['FateDomination.pck']
            manifest.write_text(json.dumps(doc), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'EXACT_EXE_PCK_REQUIRED'):
                freeze.load_client_startup_proof(proof, freeze.sha(proof), manifest, freeze.sha(manifest))

    def test_cli_reuses_failure_without_process_launch(self):
        import contextlib
        import io
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as tmp:
            base = Path(tmp)
            inputs = base / 'inputs'; inputs.mkdir()
            manifest, proof, receipt = self.fixture(inputs, status='FAIL', code=17)
            root = base / 'formal'
            argv = ['--run-formal', '--run-phase', 'client-startup',
                    '--artifact-manifest', str(manifest), '--artifact-manifest-sha256', freeze.sha(manifest),
                    '--root', str(root), '--approved-root', str(base),
                    '--client-startup-receipt', str(proof), '--client-startup-receipt-sha256', freeze.sha(proof)]
            with patch.object(freeze, 'validate_roles', return_value={}), \
                 patch('subprocess.Popen', side_effect=AssertionError('reuse must not launch')), \
                 contextlib.redirect_stdout(io.StringIO()):
                code = freeze.main(argv)
            self.assertEqual(code, 17)
            formal = json.loads((root / 'formal-runtime.json').read_text(encoding='utf-8'))
            verified = freeze.validate_formal_receipt(formal, manifest, freeze.sha(manifest))
            self.assertEqual(verified['classification'], 'FAIL_OR_PRESERVED_PROCESS')
            self.assertEqual(formal['stages']['client-startup']['producer_stage'], receipt['stages']['client-startup'])
            self.assertEqual(formal['stages']['client']['status'], 'NOTRUN')
            self.assertEqual(formal['formal_exported_client_RSA'], 'NOTRUN')

    def test_existing_signaling_receipt_has_startup_notrun(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as tmp:
            manifest, proof, receipt = self.fixture(Path(tmp))
            stages = {name: {'status': 'NOTRUN'} for name in freeze.RUN_PHASES if name != 'client-startup'}
            stages['signaling-ready'] = {'status': 'PASS', 'exit_code': 0}
            formal = {'schema': 1, 'artifact_manifest': str(manifest),
                      'artifact_manifest_sha256': freeze.sha(manifest), 'run_phase': 'signaling-ready',
                      'stages': stages, 'classification': 'PARTIAL_NOT_THREE_ROLE_PASS', 'exit_code': 0}
            verified = freeze.validate_formal_receipt(formal, manifest, freeze.sha(manifest))
            self.assertEqual(verified['stages']['client-startup']['status'], 'NOTRUN')

    def test_startup_receipt_cannot_upgrade_original_client_stage(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as tmp:
            manifest, proof, receipt = self.fixture(Path(tmp), status='FAIL', code=17)
            stages = {name: {'status': 'NOTRUN'} for name in freeze.RUN_PHASES}
            stages['client-startup'] = {'status': 'FAIL', 'exit_code': 17}
            stages['client'] = {'status': 'PASS', 'exit_code': 0}
            formal = {'schema': 1, 'artifact_manifest': str(manifest),
                      'artifact_manifest_sha256': freeze.sha(manifest), 'run_phase': 'client-startup',
                      'stages': stages, 'classification': 'FAIL_OR_PRESERVED_PROCESS', 'exit_code': 17}
            with self.assertRaisesRegex(ValueError, 'CLIENT_STARTUP_CANNOT_UPGRADE_OTHER_STAGES'):
                freeze.validate_formal_receipt(formal, manifest, freeze.sha(manifest))

    def test_cli_missing_real_artifact_never_starts_producer(self):
        import contextlib
        import io
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as tmp:
            base = Path(tmp)
            inputs = base / 'inputs'; inputs.mkdir()
            manifest, proof, receipt = self.fixture(inputs)
            root = base / 'formal'
            argv = ['--run-formal', '--run-phase', 'client-startup',
                    '--artifact-manifest', str(manifest), '--artifact-manifest-sha256', freeze.sha(manifest),
                    '--root', str(root), '--approved-root', str(base)]
            output = io.StringIO()
            with patch('tools.diagnostics.round53_exported_runtime.run_client_startup',
                       side_effect=AssertionError('missing artifact must not run')), \
                 contextlib.redirect_stdout(output):
                code = freeze.main(argv)
            self.assertEqual(code, 2)
            self.assertIn('PHYSICAL_E_PACKAGE_REQUIRED', output.getvalue())
            self.assertFalse(root.exists())

    def test_new_execution_delegates_once_to_real_producer_api(self):
        from types import SimpleNamespace
        from tools.diagnostics import round53_exported_runtime as producer
        import inspect
        inspect.signature(producer.run_client_startup).bind(Path('E:/new'), Path('E:/manifest'), 'a' * 64,
                                                          old_artifact=False)
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as tmp:
            base = Path(tmp)
            manifest, proof, receipt = self.fixture(base, status='FAIL', code=17)
            root = base / 'new-formal'; root.mkdir()
            args = SimpleNamespace(client_startup_receipt=None, client_startup_receipt_sha256=None,
                                   artifact_manifest_sha256=freeze.sha(manifest), client_startup_old_artifact=False)
            def fixture_only_producer(owned, manifest_path, digest, old_artifact=False):
                owned.mkdir()
                receipt['root'] = str(owned)
                (owned / 'runtime.json').write_text(json.dumps(receipt), encoding='utf-8')
                return receipt
            with patch.object(producer, 'run_client_startup', side_effect=fixture_only_producer) as call, \
                 patch('subprocess.Popen', side_effect=AssertionError('unit must not run an EXE')):
                result = freeze.client_startup_phase(root, manifest, args)
            call.assert_called_once_with(root / 'client-startup', manifest, freeze.sha(manifest), old_artifact=False)
            self.assertEqual(result['raw_exit_code'], 17)
            self.assertEqual(result['status'], 'FAIL')


if __name__ == '__main__':
    unittest.main()
