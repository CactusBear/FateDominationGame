import sys, unittest
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'release'))
import runtime_audit as audit

class StrictRuntimeVerdict(unittest.TestCase):
    def test_unknown_error_after_ready_is_not_pass(self):
        value={'role':'signaling','ready':True,'ready_payload':{'ok':True},'exit_code':0,'stop_method':'ctrl_break','lines':['SERVER_SIGNALING_READY {"ok":true}', 'ERROR: unknown failure']}
        self.assertFalse(audit.runtime_passed(value))
    def test_zero_error_legal_stop_passes(self):
        value={'role':'signaling','ready':True,'ready_payload':{'ok':True},'exit_code':0,'stop_method':'ctrl_break','lines':['SERVER_SIGNALING_READY {"ok":true}']}
        self.assertTrue(audit.runtime_passed(value))
    def test_exit_two_or_av_is_not_missing_config_pass(self):
        for code in (2,3221225477,-1073741819):
            self.assertFalse(audit.missing_config_passed('signaling',code,'ERROR: 信令配置不可读或包含未知 CFG 段/嵌套覆盖'))
    def test_exact_exit_one_known_reason_passes(self):
        self.assertTrue(audit.missing_config_passed('signaling',1,'ERROR: 信令配置不可读或包含未知 CFG 段/嵌套覆盖'))
    def test_unknown_error_beside_known_reason_is_not_pass(self):
        self.assertFalse(audit.missing_config_passed('signaling',1,'ERROR: 信令配置不可读或包含未知 CFG 段/嵌套覆盖\nERROR: another'))
    def test_exit_one_without_reason_is_not_pass(self):
        self.assertFalse(audit.missing_config_passed('signaling',1,''))
    def test_forced_shutdown_is_not_pass(self):
        self.assertFalse(audit.runtime_passed({'role':'signaling','ready':True,'ready_payload':{'ok':True},'exit_code':0,'stop_method':'forced_kill_after_signal_failure','lines':[]}))

if __name__=='__main__':unittest.main()
