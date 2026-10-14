"""只测真实既有回执的非空判据；不启动客户端。"""
import json
import runpy
import unittest
from pathlib import Path

HERE = Path(__file__).parent
EVIDENCE = Path('E:/Caches/Hermes/cache/scratch/round71-dual-identity-once-12796/evidence.json')

class IdentityEvidenceTest(unittest.TestCase):
    def test_absent_identity_is_not_isolation_pass(self):
        reporter = HERE / 'round71_dual_identity_evidence_report.py'
        self.assertTrue(reporter.exists(), 'missing non-vacuous evidence classifier')
        classify = runpy.run_path(str(reporter))['identity_verdict']
        source = json.loads(EVIDENCE.read_text(encoding='utf-8'))
        result = classify(source['snapshots'])
        self.assertFalse(result['generated_both'])
        self.assertTrue(result['paths_disjoint'])
        self.assertIsNone(result['different_identity_sha'])
        self.assertIsNone(result['no_identity_overwrite'])
        self.assertEqual(result['max_identity_file_counts'], {'host': 0, 'guest': 0})

if __name__ == '__main__':
    unittest.main()
