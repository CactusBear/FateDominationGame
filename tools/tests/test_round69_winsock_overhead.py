"""Offline assertions use only real persisted observer evidence; never fake wire traces."""
import importlib.util
import os
import sys
import unittest
from pathlib import Path
sys.dont_write_bytecode = True
P = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('r69', P/'tools/diagnostics/round68_owned_winsock_observer.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)

class ProfileContract(unittest.TestCase):
    def test_profile_api_exists(self):
        self.assertTrue(callable(getattr(r, 'summarize_profile', None)),
                        'missing real-event startup/network-active profiler')
    def test_module_cache_and_bulk_reader_contract(self):
        source = (P/'tools/diagnostics/round68_owned_winsock_observer.cpp').read_text(encoding='utf-8')
        self.assertFalse('b.assign(std::istreambuf_iterator<char>(f),{})' in source,
                         'whole-file byte iterator still dominates handler')
        self.assertIn('CACHE_INVALIDATE', source)
        self.assertIn('cache_creation_identity', source)
        self.assertIn('cached_source_byte_mismatch', source)
    def test_approved_port_pair_rejects_before_bind(self):
        guard=getattr(r,'approved_port_pair',None)
        self.assertTrue(callable(guard),'missing pre-bind baseline port guard')
        self.assertEqual(guard([59611,59612]),[59611,59612])
        for values in ([28100,59612],[59611,59611],['59611',59612],[0,59612],[65001,59612]):
            with self.assertRaises(ValueError):guard(values)
    def test_historical_unprofiled_trace_is_not_invented(self):
        if not hasattr(r, 'summarize_profile'):
            self.skipTest('profile not implemented')
        old = Path('E:/scratch/isolated-ade1b96e02db40efac298cbb4c3c8489/evidence/handshake.stdout.log')
        with self.assertRaises(ValueError):
            r.summarize_profile(old.read_text(encoding='utf-8'))

class RealArchivedEvidence(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root=os.environ.get('ROUND69_EVIDENCE')
        if not root:
            raise unittest.SkipTest('set ROUND69_EVIDENCE to an actual owned archive; no synthetic traces')
        import json
        cls.root=Path(root)
        cls.evidence=cls.root/'evidence'
        cls.report=json.loads((cls.evidence/'report.json').read_text(encoding='utf-8'))
        cls.verification=json.loads((cls.evidence/'verification.json').read_text(encoding='utf-8'))
    def test_owned_jobs_zero(self):
        self.assertTrue(self.report['job0'])
        self.assertTrue(all(p['exited'] and p['active_owned_processes']==0 for p in self.report['processes']))
    def test_raw_and_enet_real_pairs_headers(self):
        for kind,case in self.report['cases'].items():
            text=(self.evidence/(kind+'.stdout.log')).read_text(encoding='utf-8')
            actual=r.validate(text,kind)
            self.assertEqual(actual['pairs'],case['pairs'])
            self.assertEqual(actual['header_read_regions'],case['header_read_regions'])
            self.assertEqual(r.summarize_profile(text),case['profile'])
    def test_real_error_recursion_and_unload(self):
        for kind,case in self.report['small_cases'].items():
            text=(self.evidence/(kind+'.stdout.log')).read_text(encoding='utf-8')
            self.assertEqual(r.validate_small(text,kind),case)
    def test_aligned_wall_uses_identical_fixture_windows(self):
        for kind,case in self.report['cases'].items():
            debug=(self.evidence/(kind+'.stdout.log')).read_text(encoding='utf-8')
            control=(self.evidence/(kind+'-control.stdout.log')).read_text(encoding='utf-8')
            self.assertEqual(r.validate_control(control,kind),case['control'])
            self.assertEqual(r.compare_wall(case,debug),self.verification['cases'][kind]['aligned_wall_comparison'])
    def test_frozen_source_artifact_and_log_readback(self):
        for key in ('source_artifacts','log_artifacts'):
            for path,digest in self.report[key].items():
                self.assertEqual(r.sha(r.archive_path(path,self.root.resolve())),digest)
        with self.assertRaises(ValueError):r.archive_path(r.ENGINE,self.root.resolve())
        self.assertEqual(r.sha(self.evidence/'report.json'),self.verification['original_report_sha256'])
    def test_global_readonly_failure_is_not_relabeled_green(self):
        changed={p for p,h in self.report['protected_before'].items() if self.report['protected_after'][p]!=h}
        self.assertEqual(set(self.verification['protected_changed']),changed)
        self.assertEqual(self.verification['overall_passed'],self.report['passed'])
        self.assertEqual(self.verification['same_global_freeze'],not bool(changed))
        self.assertFalse(self.report['production_authorized'])
    def test_no_fake_recursive_system_api_claim(self):
        self.assertIn('NOT recursive system API',self.report['small_cases']['recursive']['scope'])
        self.assertEqual(self.report['unit'].strip(),'UNIT cases=63 payload_bytes_read=0')

if __name__ == '__main__':
    unittest.main()
