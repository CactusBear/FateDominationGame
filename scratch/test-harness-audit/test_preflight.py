import importlib.util
import pathlib
import unittest

MODULE = pathlib.Path(__file__).with_name('preflight.py')

class ReconciliationTests(unittest.TestCase):
    def test_numeric_failures_cannot_be_green(self):
        self.assertTrue(MODULE.exists(), 'preflight implementation is missing')
        spec = importlib.util.spec_from_file_location('preflight', MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module.reconcile('RESULT checks=3 failures=2 [a,b]', 0)['status'], 'FAIL')

    def test_exit_result_error_and_skip_matrix(self):
        spec = importlib.util.spec_from_file_location('preflight', MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        cases = [
            ('RESULT checks=4 failures=[]', 0, 'LOG_CLEAN_NOT_RUNTIME_VERIFIED'),
            ('RESULT {"checks":4,"failures":[]}', 0, 'LOG_CLEAN_NOT_RUNTIME_VERIFIED'),
            ('RESULT checks=4 failures=0', 0, 'LOG_CLEAN_NOT_RUNTIME_VERIFIED'),
            ('RESULT checks=4 failures=2', 0, 'FAIL'),
            ('RESULT {"failures":2}', 0, 'FAIL'),
            ('RESULT failures=[broken]', 0, 'FAIL'),
            ('RESULT checks=4 failures=[]\nSCRIPT ERROR: crash', 0, 'FAIL'),
            ('RESULT checks=4 failures=[]', 1, 'FAIL'),
            ('RESULT checks=4 failures=[]', 'TIMEOUT', 'FAIL'),
            ('startup only', 0, 'INCOMPLETE'),
            ('RESULT checks=4', 0, 'INCOMPLETE'),
            ('RESULT checks=0 failures=[] window_only=true', 0, 'SKIP'),
            ('RESULT checks=0 failures=[] external_pair_only=true', 0, 'SKIP'),
            ('RESULT failures=[bad]\nRESULT failures=[]', 0, 'FAIL'),
        ]
        for text, code, expected in cases:
            with self.subTest(text=text, exit=code):
                self.assertEqual(module.reconcile(text, code)['status'], expected)

class DiscoveryTests(unittest.TestCase):
    def test_script_resource_attribute_order(self):
        spec = importlib.util.spec_from_file_location('preflight', MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        root = MODULE.parents[2]
        result = module.scan(root)
        row = next(x for x in result['rows'] if x['scene'] == 'tests/servant_skill_eight_magic_test.tscn')
        self.assertIn('res://tests/servant_skill_eight_magic_test.gd', row['scripts'])

if __name__ == '__main__':
    unittest.main()
