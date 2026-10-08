import copy
import tempfile
import unittest
from pathlib import Path
from strict_gate import reconcile,validate

class GateTests(unittest.TestCase):
    def test_log_fixtures(self):
        fixtures=[('RESULT checks=2 failures=1 [bad]',0,'FAIL'),('RESULT checks=2',0,'INCOMPLETE'),('RESULT checks=0 failures=[] window_only=true',0,'NOT_RUN'),('RESULT {"checks":2,"failures":1}',0,'FAIL'),('RESULT checks=1 failures=[bad]\nRESULT checks=1 failures=[]',0,'FAIL'),('RESULT arbitrary',0,'INCOMPLETE'),('RESULT checks=2 failures=[]',0,'PASS'),('RESULT {"checks":2,"failures":[]}',0,'PASS'),('RESULT checks=2 failures=[]\nSCRIPT ERROR: crash',0,'FAIL'),('RESULT checks=2 failures=[]','TIMEOUT','FAIL'),('RESULT checks=0 failures=[]',0,'INCOMPLETE'),('',0,'INCOMPLETE'),('RESULT {"checks":true,"failures":[]}',0,'INCOMPLETE'),('RESULT {"checks":2,"failures":-1}',0,'INCOMPLETE'),('RESULT checks=2 failures=[]\nRESULT checks=2 failures=[]',0,'INCOMPLETE')]
        for text,code,expected in fixtures:
            with self.subTest(text=text):self.assertEqual(reconcile(text,code)['status'],expected)
    def test_ledger_guard(self):
        # 仅合成夹具，不代表已取得真人或多机结果。
        manifest={'cases':[{'id':'A','layer':'lan','minimum_devices':2,'assertions':['ok'],'depends_on':[]}]}
        row={'id':'A','status':'PASS','run_id':'fixture','build_id':'fixture','operator':'synthetic','reviewer':'synthetic','assertions':{'ok':True},'evidence':['fixture.txt'],'human_input_observed':True,'real_window_observed':True,'physical_devices':['A','B'],'physical_distinct_confirmed':True,'loopback_used':False}
        ledger={'run_id':'fixture','build_id':'fixture','cases':[row]}
        root=Path(__file__).resolve().parent/'selftest-evidence'
        root.mkdir(exist_ok=True)
        (root/'fixture.txt').write_text('SYNTHETIC UNIT FIXTURE NOT RUNTIME EVIDENCE',encoding='utf-8')
        self.assertEqual(validate(manifest,ledger,root)['overall'],'PASS')
        variants=[('human_input_observed',False),('real_window_observed',False),('physical_devices',['A']),('loopback_used',True),('evidence',[]),('evidence',['missing']),('assertions',{'ok':False}),('assertions',{'ok':True,'unknown':True}),('run_id','old'),('build_id','old'),('reviewer',''),('evidence_gaps',['missing'])]
        for key,value in variants:
            changed=copy.deepcopy(ledger);changed['cases'][0][key]=value
            with self.subTest(key=key):self.assertNotEqual(validate(manifest,changed,root)['overall'],'PASS')
        for rows in [[],[row,row],[dict(row,status='NOT_RUN')],[dict(row,status='BLOCKED')]]:
            changed=copy.deepcopy(ledger);changed['cases']=rows
            self.assertNotEqual(validate(manifest,changed,root)['overall'],'PASS')
    def test_manifest_dependencies(self):
        import json
        root=Path(__file__).resolve().parent
        manifest=json.loads((root/'manifest.json').read_text(encoding='utf-8'))
        ledger=json.loads((root/'ledger-template.json').read_text(encoding='utf-8'))
        result=validate(manifest,ledger,root)
        self.assertEqual(result['overall'],'INCOMPLETE')
        self.assertEqual(result['counts']['NOT_RUN'],len(manifest['cases']))
        self.assertEqual(result['counts']['PASS'],0)

if __name__=='__main__':unittest.main(verbosity=2)
