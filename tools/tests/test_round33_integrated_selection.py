"""Round33 selection guards; production/game tests remain read-only."""
import sys
sys.dont_write_bytecode = True
import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).with_name('test_round29_integrated_evidence.py')
spec = importlib.util.spec_from_file_location('evidence', PATH)
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)

class SelectionTests(unittest.TestCase):
    def test_one_selection_from_old39_and_missing13(self):
        old = {'selected_suites':['a_test','b_test','c_test'],
               'suites':[{'suite':'a_test'},{'suite':'b_test'}]}
        supplement = {'selected_suites':['b_test','c_test'], 'passed':True}
        select = getattr(evidence, 'build_integrated_selection', None)
        self.assertTrue(callable(select), 'explicit integrated selection function is missing')
        result = select(old, supplement, ['d_test','d_test'])
        self.assertEqual(result['names'], ['a_test','b_test','c_test','d_test'])
        self.assertEqual(result['missing_from_old_selection'], [])
        self.assertEqual(result['old_actual_count'], 2)
        self.assertEqual(result['selected_count'], 4)

    def test_bind_error_has_only_suite_local_exact_allowance(self):
        scoped = getattr(evidence, 'analyze_integrated_suite', None)
        self.assertTrue(callable(scoped), 'scoped negative classifier is missing')
        out = '\n'.join('CHECK event%d true' % n for n in range(7)) + '\nRESULT checks=7 failures=[]'
        err = '\n'.join([
            "ERROR: Couldn't create an ENet host.",
            'at: _create (modules/enet/enet_connection.cpp:319)',
            'GDScript backtrace (most recent call first):',
            '[0] listen (res://scripts/net/transport/enet_transport.gd:44)',
            '[1] listen (res://scripts/net/server/server_gateway.gd:51)',
            '[2] run (res://tests/gateway_bind_failure_test.gd:13)'])
        text = (evidence.PROJECT / 'tests/gateway_bind_failure_test.gd').read_text(encoding='utf-8')
        hashes = evidence.snapshot_hashes([Path('tests/gateway_bind_failure_test.gd')], evidence.PROJECT)
        row = scoped('gateway_bind_failure_test', out, err, 0, evidence.PROJECT, hashes)
        self.assertTrue(row['passed'], row)
        self.assertFalse(row['strict_passed'])
        self.assertFalse(evidence.analyze(out, err, 0)['passed'])
        for name, output, error, frozen in [
            ('gateway_relisten_acceptance_test',out,err,hashes),
            ('gateway_bind_failure_test',out,err+'\nSCRIPT ERROR: unexpected',hashes),
            ('gateway_bind_failure_test',out+'\nRESULT checks=7 failures=[]',err,hashes),
            ('gateway_bind_failure_test',out,err,{'tests/gateway_bind_failure_test.gd':'wrong'}),
            ('gateway_bind_failure_test',out.replace('checks=7','checks=6'),err,hashes)]:
            self.assertFalse(scoped(name,output,error,0,evidence.PROJECT,frozen)['passed'])

    def test_integrated_summary_rejects_missing_probe_process_and_import(self):
        summary = getattr(evidence, 'summarize_integrated', None)
        self.assertTrue(callable(summary), 'integrated stage summary is missing')
        clean = {'selected_suites':['a_test'],
                 'suites':[{'suite':'a_test','passed':True,'result':{'checks':1},'errors':[]}],
                 'import':{'exit':0,'errors':[]},
                 'editor_transform':{'verified':True,'unauthorized_changes':[]},
                 'user_probes':[{'role':'main','worker_pool_max_threads':20},
                                {'role':'worker','worker_pool_max_threads':20}],
                 'processes':[{'exited':True,'active_owned_processes':0,'log_handles_released':True}],
                 'cleanup':'generated_removed','generated_exists_after_cleanup':False,
                 'engine_source_unchanged':True,'selection_inputs_unchanged':True}
        self.assertTrue(summary(clean)['passed'])
        for change in [ {'user_probes':[]}, {'processes':[]},
            {'processes':[{'exited':False,'active_owned_processes':1,'log_handles_released':True}]},
            {'import':{'exit':0,'errors':['ERROR: real']}}, {'final_drift':['scripts/changed.gd']},
            {'cleanup':'retained'}, {'selection_inputs_unchanged':False}, {'suites':[]} ]:
            self.assertFalse(summary(dict(clean,**change))['passed'],change)

    def test_explicit_fixture_argument_for_restart_inherited_contract(self):
        command = getattr(evidence, 'suite_command', None)
        self.assertTrue(callable(command), 'explicit suite fixture command builder is missing')
        for name in ['net_server_gateway_restart_test','room_data_preparation_consumer_test',
                     'room_data_preparation_dependencies_test']:
            cmd = command(Path('E:/owned/Godot.exe'),Path('E:/owned/project'),name,Path('E:/owned/fixtures'))
            self.assertEqual(cmd[-2:], ['--','E:/owned/fixtures'])
            self.assertIn('res://tests/'+name+'.tscn',cmd)
        cmd = command(Path('E:/owned/Godot.exe'),Path('E:/owned/project'),'gateway_bind_failure_test',Path('E:/owned/fixtures'))
        self.assertNotIn('--',cmd)

if __name__ == '__main__':
    unittest.main(verbosity=2)
