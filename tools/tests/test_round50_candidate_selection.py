"""Read-only candidate contracts; never launch Godot or reuse historical PASS."""
import sys
sys.dont_write_bytecode = True
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('candidate_evidence', Path(__file__).with_name('test_round29_integrated_evidence.py'))
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)


class CandidateSelectionTests(unittest.TestCase):
    def test_real_selection_preserves_old70_and_partitions_modes(self):
        build = getattr(e, 'build_round50_selection', None)
        self.assertTrue(callable(build), 'Round50 actual-file candidate builder missing')
        old = e.load(e.PROJECT / 'reports/refactoring/round42-integrated-68eeb9d161c54e47ab9e25b4fa18cc6b/manifest.json')
        selection = build(old, e.PROJECT)
        self.assertTrue(set(old['selected_suites']).issubset(selection['headless']))
        self.assertEqual(selection['selected_count'], len(selection['names']))
        self.assertEqual(selection['program_count'],len(selection['names'])+len(selection['native_standalone']))
        self.assertEqual(selection['supplementary_gui_invocation_count'],1)
        self.assertEqual(len(selection['names']), len(set(selection['names'])))
        categories = selection['categories']
        modes = [n for group in categories.values() for n in group]
        self.assertEqual(sorted(modes), sorted(selection['names']))
        self.assertEqual(len(modes), len(set(modes)))
        self.assertIn('server_validation_countdown_test', categories['gui_required'])
        self.assertIn('validation_stage_timing_test', categories['performance'])
        self.assertIn('round47_public_test_observer_test', selection['headless'])
        self.assertIn('round50_validation_launch_route_test', selection['headless'])
        self.assertIn('round50_finished_lobby_receipt_test', selection['names'])
        self.assertIn('round47_host_lifecycle_board_test', selection['names'])
        self.assertEqual(selection['formal_scene_checks'], {
            'round50_finished_lobby_receipt_test':16,
            'round47_host_lifecycle_board_test':14,
        })
        self.assertNotIn('round50_finished_lobby_tight_test', selection['names'])
        self.assertEqual(selection['blocked_extracted_harness'], [])
        self.assertEqual(len(selection['required_harness_steps']), 1)
        self.assertEqual(selection['required_harness_steps'][0]['execution_status'], 'not_run')
        contract = selection['extracted_harness_contracts'][0]
        self.assertTrue(contract['archive_hash_required'])
        self.assertEqual(contract['parent'], 'scripts/net/session/lobby_session.gd')
        self.assertEqual(selection['mandatory_checks']['assembly_publish_lifecycle_test'], 66)
        self.assertEqual(selection['default_simulation_seconds'], 15)
        self.assertEqual(selection['worker_pool_max_threads'], 20)
        for name in selection['names']:
            for suffix in ['.gd', '.tscn']:
                self.assertTrue((e.PROJECT / ('tests/' + name + suffix)).is_file())
        bad = copy.deepcopy(old)
        bad['selected_suites'].append(bad['selected_suites'][0])
        with self.assertRaises(ValueError): build(bad, e.PROJECT)
        bad = copy.deepcopy(old)
        bad['selection']['headless'] = bad['selection']['headless'][:-1]
        with self.assertRaises(ValueError): build(bad, e.PROJECT)


    def test_preflight_real_closure_excludes_records_and_never_launches_godot(self):
        preflight = getattr(e, 'round50_preflight', None)
        self.assertTrue(callable(preflight), 'preflight-only entry missing')
        value = preflight(e.PROJECT, Path('E:/scratch'))
        self.assertFalse(value['sourcePASS'])
        self.assertFalse(value['releasePASS'])
        self.assertEqual(value['godot_launch_count'], 0)
        self.assertEqual(value['cold_import_count'], 0)
        self.assertEqual(value['business_suites_executed'], 0)
        self.assertEqual(len(value['scenes']), value['selection']['selected_count'])
        files = value['freeze_files']
        self.assertIn('tests/round47_public_test_observer.gd', files)
        self.assertIn('tests/round47_host_lifecycle_lobby.tscn', files)
        self.assertIn('addons/fate_server_signals/fate_server_signals.gdextension', files)
        self.assertTrue(any(n.endswith('.dll') for n in files))
        self.assertTrue(any(n.startswith('scripts/') for n in files))
        self.assertFalse(any(e.round50_excluded(n) for n in files))
        self.assertNotIn('tests/round47_host_lifecycle_baseline_test.gd', files)
        self.assertIn(value['status'], {'selection_ready', 'selection_blocked'})
        self.assertTrue(value['native_preflight']['authorization_plan_valid'])
        self.assertFalse(value['native_preflight']['actual_main_worker_user_probe_executed'])
        with self.assertRaises(e.runner.SafetyError): preflight(e.PROJECT, Path('C:/unsafe-root'))

    def test_command_preserves_approved_roots_config_and_modes(self):
        command = getattr(e, 'round50_command', None)
        self.assertTrue(callable(command), 'mode-aware authorized command missing')
        self.assertEqual(command('E:/Godot.exe','E:/project','net_blob_concurrent_test','E:/owned/out')[-2:],
                         ['--','E:/owned/out'])
        gui = command('E:/Godot.exe','E:/project','server_validation_countdown_test','E:/owned/out',window=True,
                      user_root='E:/owned/out/appdata/FateDomination')
        self.assertNotIn('--headless', gui)
        self.assertEqual(gui[-3:], ['--','--config','E:/owned/out/appdata/FateDomination/countdown.cfg'])
        with self.assertRaises(ValueError):
            command('E:/Godot.exe','E:/project','server_validation_countdown_test','E:/owned/out')
        for name in ['records/private.json','assets/.env','assets/private_key.pem','secrets/token.json',
                     'tests/runtime_reports/previous.json','.godot/cache','data/identity_registry.json']:
            self.assertTrue(e.round50_excluded(name), name)
        owned={'exited':True,'active_owned_processes':0,'log_handles_released':True}
        red={'passed':False}
        self.assertFalse(e.round43_continue_after(red,owned))
        self.assertTrue(e.round43_continue_after(red,owned,True))
        self.assertFalse(e.round43_continue_after(dict(red,frozen_drift=['x']),owned,True))
        self.assertFalse(e.summarize_current({'selected_suites':['a','b'],
            'suites':[{'suite':'a','passed':False},{'suite':'b','passed':True}],
            'import':{'exit':0,'errors':[]}, 'editor_transform':{'verified':True}})['passed'])


    def test_full_entry_refuses_current_blockers_before_freeze(self):
        execute = getattr(e, 'run_round50_full', None)
        self.assertTrue(callable(execute), 'guarded full candidate entry missing')
        # Inject a refusal into a real read-only snapshot; never fabricate success.
        result = e.round50_preflight(e.PROJECT, Path('E:/scratch'))
        result = dict(result, status='selection_blocked', blockers=[{'reason':'unit deliberately unapproved root'}])
        self.assertEqual(execute(result, collect_failures=True), 1)
        self.assertEqual(result['godot_launch_count'], 0)

    def test_not_landed_additions_are_blocked_not_selected(self):
        old=e.load(e.PROJECT/e.ROUND50_BASE_MANIFEST)
        value=e.build_round50_selection(old,Path('E:/scratch/round50-deliberately-not-landed'))
        self.assertEqual(value['names'],old['selection']['names'])
        self.assertEqual(len(value['blocked_not_landed']),len(e.ROUND50_ADDITIONS))
        self.assertTrue(all(row['missing'] for row in value['blocked_not_landed']))
        self.assertEqual(value['mandatory_checks']['assembly_publish_lifecycle_test'],66)

    def test_config_and_native_definitions_are_actual_not_aliases(self):
        value=e.round50_preflight(e.PROJECT,Path('E:/scratch'))
        rows={r['suite']:r for r in value['scenes']}
        self.assertEqual(rows['net_server_identity_cli_test']['configuration_writer'],'tests/net_server_identity_cli_test.gd')
        self.assertEqual(rows['net_server_cfg_test']['configuration_writer'],'tests/net_server_cfg_test.gd')
        self.assertEqual(rows['net_server_cli_p2p_test']['configuration_writer'],'tests/net_server_cli_test.gd')
        self.assertTrue(all(r['definition_exists'] and len(r['source_hashes'])==3 for r in value['native_standalone']))
        self.assertNotIn('effective legacy JSON CLI config writer',str(value['blockers']))

    def test_formal_green_requires_current_harness_and_archive(self):
        summarize = getattr(e, 'summarize_round50_harnesses', None)
        self.assertTrue(callable(summarize), 'required harness aggregation missing')
        preflight = e.round50_preflight(e.PROJECT, Path('E:/scratch'))
        self.assertFalse(preflight['sourcePASS'])
        self.assertTrue(preflight['harness_preflight'][0]['callable_verified'])
        self.assertNotIn('tight_session.gd', preflight['freeze_files'])
        m = {'selection':preflight['selection'], 'parent_source_fingerprint':'a'*64,
             'required_harness_steps':[]}
        value = summarize(m)
        self.assertFalse(value['passed'])
        self.assertEqual(value['not_run'], ['round50_finished_lobby_tight_test'])
        step = {'suite':'round50_finished_lobby_tight_test','execution_status':'executed',
                'passed':True,'archive_verified':True,'same_freeze_verified':True,
                'parent_source_fingerprint':'a'*64}
        m['required_harness_steps'] = [step]
        self.assertTrue(summarize(m)['passed'])
        for change in [{'passed':False}, {'archive_verified':False},
                       {'parent_source_fingerprint':'b'*64}, {'same_freeze_verified':False},
                       {'execution_status':'not_run'}]:
            m['required_harness_steps'] = [dict(step, **change)]
            self.assertFalse(summarize(m)['passed'], change)

    def test_real_runner_extraction_callable_and_bad_archive(self):
        adapter = getattr(e, 'round50_extraction_callable', None)
        self.assertTrue(callable(adapter), 'caller-side actual runner extraction missing')
        source = (e.PROJECT/'tests/round50_finished_lobby_receipt_runner.py').read_bytes()
        extract, contract = adapter(source)
        self.assertTrue(callable(extract))
        self.assertEqual(contract['api_kind'], 'caller_adapter_actual_tight_branch')
        import tempfile

        with tempfile.TemporaryDirectory(prefix='r55-harness-', dir='E:/scratch') as root:
            root = Path(root)
            freeze, archive = root/'project', root/'archive'
            (freeze/'scripts/net/session').mkdir(parents=True)
            archive.mkdir()
            parent = e.PROJECT/'scripts/net/session/lobby_session.gd'
            (freeze/'scripts/net/session/lobby_session.gd').write_bytes(parent.read_bytes())
            extract(freeze, archive)
            self.assertEqual(e.digest(freeze/'tight_session.gd'), e.digest(archive/'tight_session_extracted.gd'))
            self.assertNotEqual(e.digest(parent), e.digest(freeze/'tight_session.gd'))
            index = [{'path':'tight_session_extracted.gd','sha256':e.digest(archive/'tight_session_extracted.gd')}]
            self.assertTrue(e.round50_verify_harness_archive(archive, index))
            (archive/'tight_session_extracted.gd').write_text('bad archive', encoding='utf-8')
            self.assertFalse(e.round50_verify_harness_archive(archive, index))
            self.assertFalse(e.round50_verify_harness_archive(archive, [{'path':'../outside','sha256':'a'*64}]))
        with self.assertRaises(e.runner.SafetyError):
            adapter(source.replace(b"if args.suite == 'tight':", b"if args.suite == 'other':"))
        with self.assertRaises(e.runner.SafetyError):
            adapter(source.replace(b"freeze / 'tight_session.gd'", b"freeze / '../escaped_session.gd'"))

    def test_preflight_launch_guard(self):
        from unittest.mock import patch
        with patch.object(e.runner, 'execute', side_effect=AssertionError('Godot launched')):
            value = e.round50_preflight(e.PROJECT, Path('E:/scratch'))
        self.assertEqual(value['godot_launch_count'], 0)
        self.assertEqual(value['harness_preflight'][0]['execution_status'], 'not_run')

    def test_final_aggregation_formal_green_harness_fail_overall_false(self):
        summarize = getattr(e, 'summarize_round50_current', None)
        self.assertTrue(callable(summarize), 'actual final required-step aggregation missing')
        owned={'exited':True,'active_owned_processes':0,'log_handles_released':True}
        selection={'required_harness_steps':[{'suite':'round50_finished_lobby_tight_test'}]}
        step={'suite':'round50_finished_lobby_tight_test','execution_status':'executed',
              'passed':True,'archive_verified':True,'same_freeze_verified':True,
              'parent_source_fingerprint':'a'*64}
        m={'selection':selection,'parent_source_fingerprint':'a'*64,'required_harness_steps':[step],
           'selected_suites':['formal_test'],'suites':[{'suite':'formal_test','passed':True}],
           'prerequisites':[{'suite':'worker_content_environment_test','passed':True}],
           'processes':[owned],'selection_inputs_unchanged':True,
           'user_probes':[{'role':'main','worker_pool_max_threads':20},{'role':'worker','worker_pool_max_threads':20}],
           'import':{'exit':0,'errors':[]},'editor_transform':{'verified':True},
           'worker_engine_errors':[],'worker_scoped_negatives':[]}
        self.assertTrue(e.summarize_integrated(m)['passed'])
        self.assertTrue(summarize(m)['passed'])
        for change in [{'passed':False},{'archive_verified':False},{'execution_status':'not_run'},
                       {'parent_source_fingerprint':'b'*64}]:
            value=copy.deepcopy(m)
            value['required_harness_steps']=[dict(step,**change)]
            self.assertTrue(e.summarize_integrated(value)['passed'])
            self.assertFalse(summarize(value)['passed'],change)
        value=copy.deepcopy(m);value['required_harness_steps']=[]
        self.assertFalse(summarize(value)['passed'])
        self.assertEqual(summarize(value)['required_harness']['not_run'],['round50_finished_lobby_tight_test'])

    def test_generation_input_drift_is_not_run_and_never_launches(self):
        import tempfile
        from unittest.mock import patch
        import os
        with tempfile.TemporaryDirectory(prefix='r55-drift-', dir='E:/scratch') as root:
            root=Path(root);generated=root/'generated';target=generated/'project';evidence=root/'evidence'
            (target/'scripts/net/session').mkdir(parents=True);evidence.mkdir()
            parent='scripts/net/session/lobby_session.gd'
            (target/parent).write_bytes((e.PROJECT/parent).read_bytes())
            with patch.object(e.runner,'execute',side_effect=AssertionError('must not launch')):
                row=e.run_round50_harness(target,generated/'Godot.exe',os.environ.copy(),generated,
                    evidence,{'seconds':180,'bytes':1,'min_free':1},[],{parent:'a'*64})
            self.assertFalse(row['passed'])
            self.assertEqual(row['execution_status'],'not_run')
            self.assertIn('harness frozen input drift',str(row['reasons']))


    def test_continuation_only_unlaunched_same_source_never_retries_broken(self):
        p=e.round50_preflight(e.PROJECT,Path('E:/scratch'))
        requested=p['selection']['categories']['performance']+list(e.ROUND50_CURRENT_CHECKS)
        done=[n for n in p['selection']['headless'] if n not in requested]
        owned={'exited':True,'active_owned_processes':0,'log_handles_released':True}
        m={'round':50,'selected_suites':p['selection']['headless'],'freeze_before':p['freeze_hashes'],
           'parent_source_fingerprint':p['parent_source_fingerprint'],'final_drift':[],
           'cleanup':'generated_removed','archive_verified':True,
           'suites':[{'suite':n,'passed':False} for n in done],
           'processes':[dict(owned,label='complete-'+n) for n in done]}
        self.assertEqual(e.round50_missing_plan(p,m),requested)
        original=copy.deepcopy(m)
        for change in ['broken','drift','source','owner']:
            bad=copy.deepcopy(m)
            if change=='broken':bad['processes'].append(dict(owned,label='complete-'+requested[0]))
            if change=='drift':bad['final_drift']=['scripts/net/server/server_shutdown.gd']
            if change=='source':bad['parent_source_fingerprint']='b'*64
            if change=='owner':bad['processes'][0]['active_owned_processes']=1
            with self.assertRaises(e.runner.SafetyError):e.round50_missing_plan(p,bad)
        self.assertEqual(m,original)

    def test_hot_reload_dll_is_generated_not_formal_input(self):
        value=e.round50_preflight(e.PROJECT,Path('E:/scratch'))
        transient='addons/fate_server_signals/bin/~libfate_server_signals.windows.template_release.x86_64.dll'
        formal=transient.replace('/~','/')
        self.assertTrue(e.round50_excluded(transient))
        self.assertFalse(e.round50_excluded(formal))
        self.assertNotIn(transient,value['freeze_files'])
        self.assertIn(formal,value['freeze_files'])
        self.assertIn(transient,value['excluded_files'])
        self.assertFalse(any(Path(n).name.startswith('~') and n.endswith('.dll') for n in value['freeze_files']))

    def test_current_shutdown_closure_and_checks_are_mandatory(self):
        value=e.round50_preflight(e.PROJECT,Path('E:/scratch'))
        self.assertEqual(value['status'],'selection_ready',value['blockers'])
        self.assertEqual(value['selection']['headless_count'],99)
        self.assertEqual(value['selection']['selected_count'],101)
        self.assertEqual(sum(e.ROUND50_CURRENT_CHECKS.values()),283)
        for name,checks in e.ROUND50_CURRENT_CHECKS.items():
            self.assertIn(name,value['selection']['headless'])
            self.assertEqual(value['selection']['mandatory_checks'][name],checks)
            self.assertIn('tests/'+name+'.gd',value['freeze_files'])
            output='\n'.join(['CHECK true unit event']*checks)+f'\nRESULT checks={checks} failures=[]'
            self.assertTrue(e.analyze_round50_suite(name,output,'',0,e.PROJECT,{})['passed'])
            self.assertFalse(e.analyze_round50_suite(name,output.replace(f'checks={checks}',f'checks={checks-1}'),'',0,e.PROJECT,{})['passed'])
            self.assertFalse(e.analyze_round50_suite(name,output,'SCRIPT ERROR: unit rejection',0,e.PROJECT,{})['passed'])
        self.assertIn('server_data_status_inbox_approval_test',value['selection']['headless'])


    def test_byte_budget_is_still_a_safety_stop_with_collect_failures(self):
        owned={'exited':True,'active_owned_processes':0,'log_handles_released':True,
               'budget_failure':'byte_budget'}
        self.assertFalse(e.round43_continue_after({'passed':False,'execution_error':'byte_budget'},owned,True))
        self.assertFalse(e.round43_continue_after({'passed':True},owned,True))

    def test_actual_dependency_worker_error_scope_is_not_relaxed(self):
        root=Path('E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50')
        before=e.digest(root/'manifest.json')
        m=e.load(root/'manifest.json')
        errors=[item for item in m['worker_engine_errors']
                if 'work-5' in item['path'] and any('无法读取角色目录' in line for line in item['lines'])]
        self.assertEqual(len(errors),1)
        original=copy.deepcopy(errors[0])
        self.assertFalse(e.round42_dependency_worker_negative(root,m,original)['verified'])
        extra=copy.deepcopy(original);extra['lines'].append('ERROR: unexpected extra unit sentinel')
        self.assertFalse(e.round42_dependency_worker_negative(root,m,extra)['verified'])
        self.assertFalse(e.analyze('CHECK true unit\nRESULT checks=1 failures=[]',
                                  '\n'.join(extra['lines']),0)['passed'])
        self.assertEqual(e.digest(root/'manifest.json'),before)


if __name__ == '__main__':
    unittest.main(verbosity=2)