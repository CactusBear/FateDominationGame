"""Contract tests; fixtures are synthetic, never game data."""
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.dont_write_bytecode = True

class ContractTests(unittest.TestCase):
    def load(self):
        path = Path(__file__).with_name('round63_observer_lock_contract.py')
        self.assertTrue(path.exists(), 'missing observer scope implementation')
        spec = importlib.util.spec_from_file_location('round63_contract', path)
        m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
        return m

    def test_declared_scope_rejects_unknown_file_before_open(self):
        m = self.load()
        token = 'a'*32
        root = 'E:/scratch/isolated-'+token+'/generated/f'
        scope = {'run_id':token,'fixture_root':root,'files':[root+'/x/payload.json']}
        self.assertEqual(str(m.declared_file(scope, root+'/x/payload.json')).replace('\\','/'),root+'/x/payload.json')
        for value in [root+'/x/other.json',root+'/x/../x/payload.json','C:/scratch/payload.json',root+'/x/payload.json:stream']:
            with self.subTest(value=value), patch.object(Path, 'open', side_effect=AssertionError('unexpected open')):
                with self.assertRaises(ValueError):m.declared_file(scope,value)

    def test_monitor_refuses_undeclared_before_content_reader(self):
        m=self.load();token='b'*32;root='E:/scratch/isolated-'+token+'/generated/f'
        scope={'run_id':token,'fixture_root':root,'files':[root+'/x/payload.json']}
        calls=[]
        def reader(path):calls.append(str(path));return b'fixture'
        with self.assertRaises(ValueError):m.read_declared(scope,root+'/x/unexpected.json',reader)
        self.assertEqual(calls,[])
        self.assertEqual(m.read_declared(scope,root+'/x/payload.json',reader),b'fixture')
        self.assertEqual(len(calls),1)

    def test_api_same_thread_and_stale_success_error(self):
        m=self.load()
        begin='OBS_API_BEGIN seq=1 pid=2 tid=3 api=MoveFileW path=E:/x second=E:/y access=0 share=0 teb=0x10 return_pc=0x20 return_rva=0x30\n'
        end='OBS_API_END seq=1 pid=2 tid=3 api=MoveFileW return=1 last_error=5 teb=0x10 return_pc=0x20\n'
        rows=m.parse_api(begin+end)
        self.assertIsNone(rows[0]['failure_error'])
        with self.assertRaises(ValueError):m.parse_api(begin+end.replace('tid=3','tid=4'))
        with self.assertRaises(ValueError):m.parse_api(begin)

if __name__ == '__main__':unittest.main()
