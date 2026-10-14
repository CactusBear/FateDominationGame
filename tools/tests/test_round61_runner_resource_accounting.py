"""Small real-filesystem resource tests; no Godot/GUI in unit mode."""
import sys
sys.dont_write_bytecode = True
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
import uuid

spec = importlib.util.spec_from_file_location('r61_evidence', Path(__file__).with_name('test_round29_integrated_evidence.py'))
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)


class ResourceAccountingTests(unittest.TestCase):
    def test_three_suites_do_not_charge_exited_fixture_copies(self):
        with tempfile.TemporaryDirectory(prefix='round61-', dir='E:/scratch') as directory:
            token = uuid.uuid4().hex
            owner = Path(directory)/('isolated-'+token);owner.mkdir()
            generated = owner/'generated'; generated.mkdir()
            frozen = generated/'project'; frozen.mkdir()
            (frozen/'approved.bin').write_bytes(b'x'*65536)
            hashes = {'approved.bin':e.digest(frozen/'approved.bin')}
            (owner/'evidence').mkdir()
            m = {'run_id':token, 'generated':str(generated), 'processes':[],
                 'frozen_hashes':hashes, 'suite_runtime_owners':[]}
            quota = 170000
            for index in range(3):
                suite = 'unit%d_test' % index
                # Before the fix this deliberately retains the fixture, matching
                # full's old end-of-batch-only cleanup; suite 3 exceeds quota.
                allocate = getattr(e, 'round61_allocate_runtime', None)
                if allocate:
                    output = allocate(generated/'f', m, 'complete', index, suite)
                else:
                    output = generated/'f'/str(index); output.mkdir(parents=True)
                (output/'copied.bin').write_bytes((frozen/'approved.bin').read_bytes())
                (output/'report.json').write_bytes(b'{"ok":true}')
                proc = {'label':'complete-'+suite,'command':['unit'], 'pid':12345,
                        'exited':True,'active_owned_processes':0,'log_handles_released':True,'exit_code':0}
                m['processes'].append(proc)
                row = {'suite':suite,'phase':'complete','fixture_root':output.as_posix(),'command':['unit']}
                for role in ['stdout','stderr']:
                    (owner/'evidence'/('complete-'+suite+'.'+role+'.log')).write_bytes(b'unit raw log')
                self.assertLess(e.runner.tree_bytes(owner), quota, 'exited fixtures accumulated into suite 3 quota')
                reclaim = getattr(e, 'round61_reclaim_runtime', None)
                if reclaim:
                    e.save(owner/'manifest.json',m)
                    result = reclaim(owner,m,row,frozen)
                    self.assertEqual(result['status'],'removed')
                    self.assertFalse(output.exists())
                    self.assertTrue((frozen/'approved.bin').is_file())
                    self.assertTrue(all(e.digest(owner/x['path'])==x['sha256'] for x in result['artifacts']))


class RefusalTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='round61-refusal-', dir='E:/scratch')
        self.addCleanup(self.temp.cleanup)
        token = uuid.uuid4().hex
        self.owner = Path(self.temp.name)/('isolated-'+token);self.owner.mkdir()
        self.generated = self.owner/'generated';self.generated.mkdir()
        self.target = self.generated/'project';self.target.mkdir()
        (self.target/'input.bin').write_bytes(b'approved frozen input')
        (self.owner/'evidence').mkdir()
        self.m = {'run_id':token,'generated':str(self.generated),'processes':[],
                  'frozen_hashes':{'input.bin':e.digest(self.target/'input.bin')}}
        self.output = e.round61_allocate_runtime(self.generated/'f', self.m, 'complete', 0, 'unit_test')
        (self.output/'copy.bin').write_bytes((self.target/'input.bin').read_bytes())
        (self.output/'report.json').write_bytes(b'{"ok":true}')
        self.proc = {'label':'complete-unit_test','command':['unit'],'pid':12345,'exit_code':0,
                     'exited':True,'active_owned_processes':0,'log_handles_released':True}
        self.m['processes'].append(self.proc)
        self.row = {'suite':'unit_test','phase':'complete','fixture_root':self.output.as_posix(),'command':['unit']}
        for role in ['stdout','stderr']:
            (self.owner/'evidence'/('complete-unit_test.'+role+'.log')).write_bytes(b'raw execution log')

    def reject(self):
        e.save(self.owner/'manifest.json',self.m)
        before = (self.output/'copy.bin').read_bytes()
        with self.assertRaises((e.runner.SafetyError,OSError)):
            e.round61_reclaim_runtime(self.owner,self.m,self.row,self.target)
        self.assertEqual((self.output/'copy.bin').read_bytes(),before)
        self.assertEqual((self.output/'report.json').read_bytes(),b'{"ok":true}')

    def test_job_live(self):
        self.proc.update(exited=False,active_owned_processes=1)
        self.reject()

    def test_log_handles_not_released(self):
        self.proc['log_handles_released']=False
        self.reject()

    def test_unknown_scope(self):
        self.m['suite_runtime_owners']=[]
        self.reject()

    def test_receipt_missing(self):
        (Path(self.m['suite_runtime_owners'][0][0]['owner'])/'manifest.json').unlink()
        self.reject()

    def test_receipt_identity_mismatch(self):
        self.m['suite_runtime_owners'][0][0]['directory_identity'][1] += 1
        self.reject()

    def test_archive_fail(self):
        from unittest.mock import patch
        real = e.shutil.copyfile
        def corrupt(source,dest):
            real(source,dest)
            Path(dest).write_bytes(b'corrupted evidence')
        with patch.object(e.shutil,'copyfile',side_effect=corrupt):
            self.reject()

    def test_unknown_file_no_partial_deletion(self):
        (self.output/'unknown.data').write_bytes(b'not declared and not frozen')
        self.reject()
        self.assertEqual((self.output/'unknown.data').read_bytes(),b'not declared and not frozen')

    def test_frozen_input_drift(self):
        (self.target/'input.bin').write_bytes(b'changed')
        self.reject()

    def test_known_snapshot_cache_retained_without_delete_permission(self):
        cache=self.output/'appdata/FateDomination/game_data/stored_jsons.dat'
        cache.parent.mkdir(parents=True);cache.write_bytes(b'known snapshot cache must remain')
        e.save(self.owner/'manifest.json',self.m)
        try:
            result=e.round61_reclaim_runtime(self.owner,self.m,self.row,self.target)
        except e.runner.SafetyError as exc:
            self.fail('known cache must use smaller scope, not prevent verified-input recycling: '+str(exc))
        self.assertEqual(result['status'],'retained_protected')
        self.assertEqual(cache.read_bytes(),b'known snapshot cache must remain')
        self.assertFalse((self.output/'copy.bin').exists())
        self.assertEqual(result['quota_owner'],str(self.generated))

    def test_reparse_no_partial_deletion(self):
        import subprocess
        target = self.generated/'junction-target';target.mkdir()
        (target/'keep').write_bytes(b'other owned fixture, not authorized for recycle')
        junction = self.output/'embedded'
        result = subprocess.run(['cmd.exe','/c','mklink','/J',str(junction),str(target)],capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        try:
            self.reject()
            self.assertTrue((target/'keep').is_file())
        finally:
            os.rmdir(junction)

    def test_known_save_raw_shutdown_and_shared_freeze_preserved(self):
        from unittest.mock import patch
        records = self.output/'records';records.mkdir()
        save = records/'save.json';save.write_bytes(b'known save evidence untouched')
        key = self.output/'private_key.pem';key.write_bytes(b'unit secret must not be read')
        response = self.output/'shutdown.response.json'
        raw = b'{"ok":true,"room":"unit","pid":12345,"instance":"exact","request_id":"unit","result":{"closing":true}}\r\n'
        response.write_bytes(raw)
        (self.output/'round39-final-save.json').write_bytes(b'{"saved":true}')
        real = e.digest
        def no_secrets(path):
            self.assertNotIn('records',Path(path).parts)
            self.assertNotEqual(Path(path),key)
            return real(path)
        with patch.object(e,'digest',side_effect=no_secrets):
            e.save(self.owner/'manifest.json',self.m)
            result=e.round61_reclaim_runtime(self.owner,self.m,self.row,self.target)
        self.assertEqual(result['status'],'retained_protected')
        self.assertEqual(save.read_bytes(),b'known save evidence untouched')
        self.assertTrue(key.is_file())
        self.assertFalse((self.output/'copy.bin').exists())
        self.assertTrue((self.target/'input.bin').is_file())
        archived=[self.owner/x['path'] for x in result['artifacts'] if x['path'].endswith('shutdown.response.json')]
        self.assertEqual(len(archived),1)
        self.assertEqual(archived[0].read_bytes(),raw)
        self.assertEqual(result['quota_owner'],str(self.generated))
        self.assertTrue(all(not item['content_read'] for item in result['retained']))
        self.assertTrue(result['response_evidence'][0]['raw_bytes_preserved'])
        self.assertEqual(result['response_evidence'][0]['nonsecret_fields']['result'],{'closing':True})


if __name__ == '__main__':
    unittest.main(verbosity=2)
