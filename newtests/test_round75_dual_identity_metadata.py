"""只测试元数据判据；夹具不是身份文件，也不是运行证据。"""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('formal_proof', Path(__file__).with_name('round75_dual_identity_formal.py'))
proof = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proof)


class MetadataAcceptanceTests(unittest.TestCase):
    def test_empty_identity_never_passes(self):
        empty = {'host': {'directory': 'E:/a', 'exists': False, 'file_count': 0, 'files': {}},
                 'guest': {'directory': 'E:/b', 'exists': False, 'file_count': 0, 'files': {}}}
        result = proof.compare(empty)
        self.assertTrue(result['paths_distinct'])
        self.assertFalse(result['nonempty_both'])
        self.assertFalse(result['sha_distinct'])
        self.assertFalse(result['same_names'])

    def test_shared_sha_is_rejected(self):
        rows = {'host': {'directory': 'E:/a', 'exists': True, 'file_count': 1, 'files': {'sample': 'metadata-only'}},
                'guest': {'directory': 'E:/b', 'exists': True, 'file_count': 1, 'files': {'sample': 'metadata-only'}}}
        result = proof.compare(rows)
        self.assertTrue(result['nonempty_both'])
        self.assertFalse(result['sha_distinct'])

    def test_same_filename_required(self):
        rows = {'host': {'directory': 'E:/a', 'exists': True, 'file_count': 1, 'files': {'a': 'metadata-only-a'}},
                'guest': {'directory': 'E:/b', 'exists': True, 'file_count': 1, 'files': {'b': 'metadata-only-b'}}}
        result = proof.compare(rows)
        self.assertFalse(result['same_names'])
        self.assertFalse(result['nonempty_both'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
