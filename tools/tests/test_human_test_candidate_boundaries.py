"""Packaging policy tests only: fixtures are never Godot/runtime evidence."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('candidate_boundaries', REPO / 'tools/release/human_test_candidate.py')
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)


class BoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = Path(os.environ.get('HUMAN_TEST_SCRATCH', 'E:/Caches/Hermes/cache/scratch')).resolve()
        if cls.scratch.drive.upper() != 'E:':
            raise RuntimeError('TEST_PHYSICAL_E_SCRATCH_REQUIRED')
        cls.scratch.mkdir(parents=True, exist_ok=True)
        for key in ('TMPDIR', 'TEMP', 'TMP'):
            os.environ[key] = str(cls.scratch)

    def validated(self):
        return {'stages': {name: {'status': 'NOTRUN'} for name in s.freeze.RUN_PHASES},
                'classification': 'INCOMPLETE_NOTRUN', 'run_phase': 'client-startup'}

    def test_structured_boundaries_do_not_upgrade_smoke(self):
        result = s.known_limitations(self.validated())
        self.assertIsInstance(result, dict)
        self.assertEqual(result['full_suite']['status'], 'NOTRUN')
        self.assertEqual(result['save_restore']['status'], 'UNKNOWN')
        self.assertEqual(result['worker_ready']['status'], 'UNKNOWN')
        self.assertEqual(result['gui_two_client']['status'], 'NOTRUN')
        self.assertFalse(result['client_startup']['implies_multiplayer_acceptance'])
        self.assertEqual(set(result['formal_phases']), set(s.freeze.RUN_PHASES))

    def test_missing_formal_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as temp:
            with self.assertRaisesRegex(s.CandidateError, 'FORMAL_RECEIPT_REQUIRED'):
                s.load_formal(Path(temp) / 'absent.json', 'a' * 64, Path(temp) / 'artifact.json', 'b' * 64)

    def test_sneaky_lowercase_pass_is_rejected(self):
        for key, value in [('source_pass', 'PASS'), ('release_pass', 'PASS'),
                           ('ready_token', 'READY'), ('full_suite', 'PASS'), ('full_suite', 'FAIL')]:
            with self.subTest(key=key, value=value):
                with self.assertRaisesRegex(s.CandidateError, 'FALSE_FINAL_CLAIM|FULL_SUITE_RECEIPT_UNSUPPORTED'):
                    s.reject_final_claims({key: value}, 'INPUT')

    def test_candidate_label_cannot_smuggle_final_status(self):
        for key in ('status', 'classification'):
            for value in ('BUILD_ONLY_RELEASE_PASS', 'CANDIDATE_READY',
                          'NOTRUN_SOURCE_PASS', 'PARTIAL_NOT_THREE_ROLE_PASS_RELEASE_PASS'):
                with self.subTest(key=key, value=value):
                    with self.assertRaisesRegex(s.CandidateError, 'FALSE_FINAL_STATUS'):
                        s.reject_final_claims({key: value}, 'INPUT')
        for value in ('BUILD_ONLY_DIAGNOSTIC_THREE_ARTIFACTS_RUNTIME_NOTRUN',
                      'STATIC_BUILD_ACCEPTED_NOT_RUNTIME_PASS', 'PARTIAL_NOT_THREE_ROLE_PASS',
                      'HUMAN_TEST_CANDIDATE', 'NOTRUN'):
            s.reject_final_claims({'status': value}, 'INPUT')

    def test_old_package_cannot_claim_latest(self):
        for claim in ({'is_latest': True}, {'declared_latest': True},
                      {'artifact_currency': 'LATEST'}, {'source_comparison': {'is_latest': True}}):
            with self.subTest(claim=claim):
                with self.assertRaisesRegex(s.CandidateError, 'LATEST_CLAIM_NOT_SUPPORTED'):
                    s.reject_final_claims(claim, 'OLD_ARTIFACT')

    def test_raw_receipt_missing_new_phase_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=Path(os.environ['TMPDIR']).resolve()) as temp:
            root = Path(temp)
            artifact = root / 'manifest.json'
            artifact.write_text('{}', encoding='utf-8')
            stages = {name: {'status': 'NOTRUN'} for name in s.freeze.RUN_PHASES if name != 'client-startup'}
            stages['signaling-ready'] = {'status': 'PASS', 'exit_code': 0}
            receipt = {'schema': 1, 'artifact_manifest': str(artifact),
                       'artifact_manifest_sha256': s.sha(artifact), 'run_phase': 'signaling-ready',
                       'classification': 'PARTIAL_NOT_THREE_ROLE_PASS', 'exit_code': 0, 'stages': stages}
            formal = root / 'formal.json'
            formal.write_text(json.dumps(receipt), encoding='utf-8')
            with self.assertRaisesRegex(s.CandidateError, 'FORMAL_RECEIPT_EXACT_PHASES_REQUIRED'):
                s.load_formal(formal, s.sha(formal), artifact, s.sha(artifact))


if __name__ == '__main__':
    unittest.main()
