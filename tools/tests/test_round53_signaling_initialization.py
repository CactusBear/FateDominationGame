import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('r53',Path(__file__).resolve().parents[1]/'diagnostics/round53_signaling_initialization.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)

class Contracts(unittest.TestCase):
    def test_explicit_exit_two_and_exact_reason(self):
        reason='ERROR: config rejected'
        self.assertTrue(r.negative_passed(2,reason,expected_exit=2,reason=reason,allowed_errors=[reason]))
        for code in [0,1,3,0xc0000005]:self.assertFalse(r.negative_passed(code,reason,expected_exit=2,reason=reason,allowed_errors=[reason]))
    def test_unknown_error_or_ready_rejected(self):
        reason='ERROR: config rejected'
        for text in [reason+'\nERROR: unrelated',reason+'\nSERVER_SIGNALING_READY {}','',reason+'\n'+reason]:
            self.assertFalse(r.negative_passed(2,text,expected_exit=2,reason=reason,allowed_errors=[reason]))
    def test_all_four_required_immediately(self):
        import json
        before='R53_NATIVE_BEFORE '+json.dumps([False]*4)+'\n'
        result={'status':0,'loaded':True,'classes':dict.fromkeys(r.METHODS,True)}
        self.assertTrue(r.native_readback(before+'R53_NATIVE_AFTER '+json.dumps(result)))
        for key in r.METHODS:
            bad={**result,'classes':{**result['classes'],key:False}}
            self.assertFalse(r.native_readback(before+'R53_NATIVE_AFTER '+json.dumps(bad)))
    def test_automatic_loading_rejected(self):
        self.assertFalse(r.native_readback('R53_NATIVE_BEFORE [true,false,false,false]'))

    def test_negative_requires_core_error_scope(self):
        text='ERROR: Parse JSON failed. Error at line 0: Unknown error getting token\n   at: parse_string (core/io/json.cpp:629)\nERROR: 信令配置不可读或包含未知 CFG 段/嵌套覆盖\n   at: push_error (core/variant/variant_utility.cpp:1023)\n       [0] _signal_fail (res://scripts/net/server/server_bootstrap.gd:217)'
        self.assertTrue(r.negative_contract({'exit':2},text))
        self.assertFalse(r.negative_contract({'exit':1},text))
        self.assertFalse(r.negative_contract({'exit':2},text.replace('core/io/json.cpp:629','unknown.cpp:629')))
        self.assertFalse(r.negative_contract({'exit':2},text+'\nERROR: unrelated'))

    def test_deployment_only_rewrites_windows_mapping(self):
        from tools.release import signaling_prepare as s
        original=(r.REPO/r.EXT).read_text()
        deployed=s.external_descriptor(original)
        self.assertIn('windows.x86_64 = "'+Path(r.DLL).name+'"',deployed)
        self.assertEqual(original.replace('"res://'+r.DLL+'"','"'+Path(r.DLL).name+'"'),deployed)
        with self.assertRaises(ValueError):s.external_descriptor('[configuration]\nentry_symbol="bad"')

    def test_actual_ready_needs_all_classes_break_and_clean_tail(self):
        import json
        from tools.release import signaling_prepare as s
        header='SERVER_SIGNALING_NATIVE_READY '+json.dumps({'status':0,'methods_verified':True,'classes':list(r.METHODS)})+'\nSERVER_SIGNALING_READY '+json.dumps({'ok':True,'pid':1,'port':1234,'roles':['relay']})+'\n'
        stop='SERVER_SIGNALING_STOP_REQUEST '+json.dumps({'pid':1,'request':2})
        receipt={'owned':[1],'exit':0,'timeout':False,'errors':[],'module_loaded':True,'details':{'ctrl_break_sender_exit':0}}
        self.assertTrue(s.production_ready(header+stop,receipt))
        self.assertFalse(s.production_ready(header,receipt))
        for bad in [{'exit':0xc0000005},{'errors':['ERROR: unknown']},{'module_loaded':False},{'timeout':True}]:
            self.assertFalse(s.production_ready(header+stop,{**receipt,**bad}))

    def test_pck_missing_is_not_empty_data_pass(self):
        from tools.release import signaling_prepare as s
        with self.assertRaises(ValueError):s.audit(Path('E:/does-not-exist-r53-package'),Path('E:/does-not-exist-r53-source'))

    def test_actual_ready_record_is_mandatory(self):
        import json
        from tools.release import signaling_prepare as s
        text='SERVER_SIGNALING_NATIVE_READY '+json.dumps({'status':0,'methods_verified':True,'classes':list(r.METHODS)})+'\nSERVER_SIGNALING_STOP_REQUEST '+json.dumps({'pid':1,'request':2})
        receipt={'owned':[1],'exit':0,'timeout':False,'errors':[],'module_loaded':True,'details':{'ctrl_break_sender_exit':0}}
        self.assertFalse(s.production_ready(text,receipt))

if __name__=='__main__':unittest.main()