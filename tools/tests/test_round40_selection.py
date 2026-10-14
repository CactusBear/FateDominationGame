"""Round40 mode partition must not relabel GUI or historical evidence as PASS."""
import sys
sys.dont_write_bytecode = True
import importlib.util
from pathlib import Path
import unittest
import copy
import json
import os
import uuid

spec = importlib.util.spec_from_file_location('round40_evidence', Path(__file__).with_name('test_round29_integrated_evidence.py'))
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)

class Round40Tests(unittest.TestCase):
    def test_round43_collect_failures_preserves_failfast_and_aggregate_red(self):
        policy = getattr(e, 'round43_continue_after', None)
        self.assertTrue(callable(policy), 'explicit collect-failures policy missing')
        owned = {'exited':True,'active_owned_processes':0,'log_handles_released':True,'budget_failure':None}
        red = {'passed':False,'reasons':['nonzero_exit'],'exit':1}
        self.assertFalse(policy(red, owned), 'default remains failfast')
        self.assertTrue(policy(red, owned, collect_failures=True))
        self.assertTrue(policy(dict(red, execution_error='timeout'), dict(owned,budget_failure='timeout'), True))
        for changed in [dict(owned,budget_failure='byte_budget'),dict(owned,budget_failure='free_space_budget'),
                        dict(owned,exited=False),dict(owned,active_owned_processes=1),dict(owned,log_handles_released=False)]:
            self.assertFalse(policy(red,changed,True))
        for changed in [dict(red,frozen_drift=['x']),dict(red,parallel_drift=['x']),
                        dict(red,current_vs_frozen=['x']),dict(red,execution_error='link/reparse point: x')]:
            self.assertFalse(policy(changed,owned,True))
        rows=[]
        for name, exit_code in [('fail1',1),('pass2',0)]:
            analysis=e.analyze('RESULT checks=1 failures=[]','',exit_code)
            row=dict(analysis,suite=name,exit=exit_code)
            rows.append(row)
            if not policy(row,owned,True): break
        self.assertEqual([r['suite'] for r in rows],['fail1','pass2'])
        m={'selected_suites':['fail1','pass2'],'suites':rows,'import':{'exit':0,'errors':[]},
           'editor_transform':{'verified':True,'unauthorized_changes':[]}}
        self.assertFalse(e.summarize_current(m)['passed'], 'collect never erases fail1')
        self.assertIn('current_suite_failure',e.summarize_current(m)['reasons'])

    def test_round43_static_audit_all70_and_inherited_output_roots(self):
        audit = getattr(e, 'round43_scene_preflight', None)
        self.assertTrue(callable(audit), 'full static output/protocol/dependency audit missing')
        prior=e.load(e.PROJECT/'reports/refactoring/round42-integrated-68eeb9d161c54e47ab9e25b4fa18cc6b/manifest.json')
        selection=prior['selection']
        files=[Path(x['path']) for x in prior['source_files']]
        value=audit(selection,e.PROJECT,files)
        self.assertEqual(len(value['suites']),70)
        self.assertEqual(len({r['suite'] for r in value['suites']}),70)
        self.assertEqual(value['blockers'],[])
        self.assertTrue(all(r['protocol_sources'] and r['output_contract'] for r in value['suites']))
        broken=[p for p in files if p.as_posix()!='tests/isolated_fixture_root_contract_test.gd']
        self.assertTrue(audit(selection,e.PROJECT,broken)['blockers'])
        with self.assertRaises(ValueError): audit(dict(selection,headless=selection['headless'][:-1]),e.PROJECT,files)

    def test_round43_gui_same_hash_binding_not_headless_credit(self):
        bind=getattr(e,'round43_gui_binding',None)
        self.assertTrue(callable(bind),'same-hash independent GUI binding missing')
        prior=e.load(e.PROJECT/'reports/refactoring/round42-integrated-68eeb9d161c54e47ab9e25b4fa18cc6b/manifest.json')
        current=e.snapshot_hashes([Path(x['path']) for x in prior['source_files']],e.PROJECT)
        value=bind(current)
        self.assertTrue(value['verified'],value.get('reasons'))
        self.assertFalse(value['counts_as_headless_pass'])
        self.assertEqual(value['checks'],25)
        bad=dict(current);bad['scripts/game_scene/battle_board_v2.gd']='0'*64
        self.assertFalse(bind(bad)['verified'])

    def test_round43_summary_requires_exact70_and_worker45_prerequisite(self):
        old=e.load(e.PROJECT/'reports/refactoring/round42-integrated-68eeb9d161c54e47ab9e25b4fa18cc6b/manifest.json')
        names=old['selected_suites']
        m=dict(old,round=43,focused=[],focused_expected=[],phase_policy='complete_only_current_freeze',
               suites=[{'suite':n,'passed':True,'result':{'checks':1},'errors':[]} for n in names],
               prerequisites=[{'suite':'worker_content_environment_test','passed':True,'exit':0,'result':{'checks':45}}],
               scene_static_preflight={'passed':True,'suites':[{'suite':n} for n in names]},
               final_drift=[],pre_full_drift=[],error=None,worker_engine_errors=[],worker_scoped_negatives=[])
        good=e.summarize_round40(m)
        self.assertTrue(good.get('headless_source_candidate_PASS'),good)
        self.assertFalse(good['release_passed'])
        for changes in [{'prerequisites':[]},{'prerequisites':[dict(m['prerequisites'][0],passed=False)]},
                        {'suites':m['suites'][:-1]}, {'suites':m['suites']+[m['suites'][0]]},
                        {'suites':[dict(m['suites'][0],passed=False)]+m['suites'][1:]},
                        {'scene_static_preflight':{'passed':False,'suites':[]}}]:
            value=e.summarize_round40(dict(m,**changes))
            self.assertFalse(value['headless_source_candidate_PASS'],changes)

    def test_round43_restart_saved_artifacts_accept_native_separators(self):
        readback=getattr(e,'round43_restart_readback',None)
        self.assertTrue(callable(readback),'native-separator archived save readback missing')
        archive=e.PROJECT/'reports/refactoring/round43-integrated-9128e0d5d8bf4625a717e7034b7112ee'
        m=e.load(archive/'manifest.json')
        row=next(r for r in m['suites'] if r['suite']=='net_server_gateway_restart_test')
        value=readback(archive,m,row)
        self.assertTrue(value['verified'],value)
        self.assertEqual(len(value['saved']),1)
        self.assertEqual(value['saved'][0]['records'],194)
        m['worker_artifacts']=[dict(i,path=i['path'].replace('\\','/')) for i in m['worker_artifacts']]
        self.assertEqual(readback(archive,m,row)['saved'],value['saved'])
        m['worker_artifacts']=[dict(i,sha256='0'*64) if i['path'].endswith('round39-final-save.json') else i for i in m['worker_artifacts']]
        self.assertFalse(readback(archive,m,row)['verified'])

    def test_round43_bind_godot_log_copy_requires_exact_scope(self):
        classify=getattr(e,'round43_bind_log_negative',None)
        self.assertTrue(callable(classify),'exact per-suite Godot-log bind duplicate classifier missing')
        archive=e.PROJECT/'reports/refactoring/round43-integrated-9128e0d5d8bf4625a717e7034b7112ee'
        m=e.load(archive/'manifest.json')
        error=next(r for r in m['worker_engine_errors'] if 'godot.log' in r['path'])
        value=classify(archive,m,error)
        self.assertTrue(value['verified'],value)
        self.assertFalse(value['strict_passed'])
        for change in [dict(error,lines=error['lines']+['ERROR: another']),
                       dict(error,path=error['path'].replace('complete-65','complete-64'))]:
            self.assertFalse(classify(archive,m,change)['verified'])
        m['frozen_hashes']['tests/gateway_bind_failure_test.gd']='0'*64
        self.assertFalse(classify(archive,m,error)['verified'])

    def test_round43_reparse_one_complete_freeze_preserves_original_red(self):
        reparse=getattr(e,'round43_reparse_archive',None)
        self.assertTrue(callable(reparse),'read-only same-freeze final reparse missing')
        archive=e.PROJECT/'reports/refactoring/round43-integrated-9128e0d5d8bf4625a717e7034b7112ee'
        before=e.digest(archive/'manifest.json')
        m=reparse(archive/'manifest.json')
        self.assertEqual(e.digest(archive/'manifest.json'),before)
        self.assertEqual(m['summary']['actual_count'],70)
        self.assertEqual(m['summary']['pass_count'],69)
        self.assertEqual(m['summary']['failed'],['assembly_publish_lifecycle_test'])
        self.assertEqual(m['summary']['missing'],[])
        self.assertFalse(m['summary']['headless_source_candidate_PASS'])
        self.assertFalse(m['restart_current']['performance_passed'])
        self.assertTrue(m['restart_current']['archive_readback']['verified'])
        self.assertEqual(len(m['worker_engine_errors']),2)
        self.assertEqual(len(m['worker_scoped_negatives']),2)

    def test_round42_freezes_owner_contract_scene_without_selecting_extra_suite(self):
        includes = getattr(e, 'round42_explicit_dependencies', None)
        self.assertTrue(callable(includes), 'owner contract scene missing from explicit dependency freeze')
        self.assertEqual(includes(), ['tests/isolated_fixture_root_contract_test.gd',
                                      'tests/isolated_fixture_root_contract_test.tscn'])

    def test_round42_full_only_has_no_historical_focused_credit(self):
        m = e.load(e.PROJECT/'reports/refactoring/round42-integrated-278ce6b21ee646e9bae7ded5f6d654e7/manifest.json')
        m['phase_policy'] = 'complete_only_current_freeze'
        m['focused_expected'] = []
        m['focused'] = []
        m['full_safety_blockers'] = []
        summary = e.summarize_round40(m)
        self.assertNotIn('focused_incomplete', summary['reasons'])
        self.assertFalse(summary['passed'], 'missing current full70 never credited from old focused18')
        self.assertIn('incomplete_or_duplicate_current_suites',summary['reasons'])

    def test_round42_delegated_fixture_preflight_is_owner_hash_bound(self):
        contracts = getattr(e, 'round42_fixture_contracts', None)
        self.assertTrue(callable(contracts), 'delegated output-root owner binding missing')
        names = ['lobby_content_environment_restore_test','net_blob_concurrent_test']
        value = contracts(names, e.PROJECT)
        self.assertEqual(value['blockers'], [])
        self.assertEqual(len(value['bindings']), 4)
        self.assertTrue(all(x['matches_owner'] for x in value['bindings']))
        for name in names:
            self.assertEqual(e.round40_command('E:/engine.exe','E:/project',name,'E:/owned/out')[-2:],
                             ['--','E:/owned/out'])
        with self.assertRaises(e.runner.SafetyError):
            contracts(names, e.PROJECT, handoff=Path('E:/scratch/missing-handoff.md'))

    def test_round42_dependencies_worker_error_requires_exact_negative_binding(self):
        classify = getattr(e, 'round42_dependency_worker_negative', None)
        self.assertTrue(callable(classify), 'precise incomplete-single-card worker classification missing')
        archive = e.PROJECT/'reports/refactoring/round42-integrated-278ce6b21ee646e9bae7ded5f6d654e7'
        m = e.load(archive/'manifest.json')
        error = m['worker_engine_errors'][0]
        result = classify(archive, m, error)
        self.assertTrue(result['verified'])
        self.assertFalse(result['strict_passed'])
        for changed in [dict(error, lines=error['lines']+['ERROR: unrelated']),
                        dict(error, path='worker/focused-0/unrelated/engine.log')]:
            self.assertFalse(classify(archive,m,changed)['verified'])

    def test_round42_preflight_requires_explicit_current_probe_before_suites(self):
        preflight = getattr(e, 'round42_static_preflight', None)
        self.assertTrue(callable(preflight), 'mandatory whole-selection probe preflight missing')
        old = e.load(e.PROJECT / 'reports/refactoring/round33-integrated-b9fbd2011963493eaf6b76f02032de1e/manifest.json')
        selection = e.build_round42_selection(old)
        self.assertEqual(selection['focused'][0], 'assembly_publish_lifecycle_test')
        self.assertEqual(len(selection['focused']), 18)
        self.assertEqual(len(selection['headless']), 70)
        self.assertEqual(e.ROUND40_EXPECTED_CHECKS['assembly_publish_lifecycle_test'], 66)
        with self.assertRaises(e.runner.SafetyError):
            preflight(selection, {})

    def test_round42_prelaunch_failure_reports_exact_stage_not_business_red(self):
        summarize = getattr(e, 'round42_stop', None)
        self.assertTrue(callable(summarize), 'stage-specific prelaunch stop reason missing')
        self.assertEqual(summarize('freeze', 'SafetyError: source drift while copying: x', []),
                         {'stop_reason':'freeze_source_drift','business_suites_executed':0,'business_failed':[]})
        self.assertEqual(summarize('static_preflight', 'ProbeSafetyError: old token', [] )['stop_reason'],
                         'static_preflight_rejected')

    def test_round42_native_authorization_rejects_unsafe_before_inspection(self):
        path = e.PROJECT / 'tools/diagnostics/assembly_native_probe.py'
        self.assertTrue(path.is_file(), 'maintainable scoped native helper missing')
        spec = importlib.util.spec_from_file_location('native_probe_test', path)
        native = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(native)
        token = uuid.uuid4().hex
        owner = Path('E:/scratch') / ('isolated-' + token)
        generated = owner / 'generated'
        root = generated / 'f/focused-0'
        source = generated / 'project/data'
        scope = {'version':1, 'run_id':token, 'generated':generated.as_posix(),
                 'fixture_root':root.as_posix(), 'source_root':source.as_posix(),
                 'engine':(generated / 'Godot.exe').as_posix(), 'owner_pid':os.getpid(),
                 'owner_creation':native.process_identity(os.getpid())['creation'],
                 'helper_sha256':e.digest(path)}
        root.mkdir(parents=True)
        source.mkdir(parents=True)
        (root / 'stage').mkdir()
        try:
            native.validate_paths(scope, token, 'scan', [str(root), str(root / 'stage'), str(source)])
            for changed, request_token, paths in [
                (scope, '0'*32, [str(root), str(root / 'stage'), str(source)]),
                (scope, token, ['C:/unsafe', 'C:/unsafe/stage', str(source)]),
                (scope, token, [str(root), str(owner / 'unowned'), str(source)]),
                (scope, token, [str(root), str(root / 'stage'), 'E:/unowned/source']),
                (dict(scope, generated='E:/scratch/isolated-'+'0'*32+'/generated'), token,
                 [str(root), str(root / 'stage'), str(source)]),
            ]:
                with self.subTest(paths=paths, token=request_token):
                    with self.assertRaises(native.ProbeSafetyError):
                        native.validate_paths(changed, request_token, 'scan', paths)
            caller = {'pid':123, 'parent':456, 'image':str(generated / 'Godot.exe'), 'creation':'999', 'in_job':True}
            owner_identity = {'pid':os.getpid(), 'creation':scope['owner_creation']}
            # A foreign PID is never authorized merely because it is live or in a Job.
            with self.assertRaises(native.ProbeSafetyError):
                native.validate_caller(scope, 124, caller, owner_identity)
            with self.assertRaises(native.ProbeSafetyError):
                native.validate_caller(scope, 123, caller, owner_identity)
            caller['parent'] = os.getpid()
            self.assertEqual(native.validate_caller(scope, 123, caller, owner_identity), 123)
            with self.assertRaises(native.ProbeSafetyError):
                native.validate_caller(scope, 123, caller, dict(owner_identity, creation='stale'))
        finally:
            e.runner.no_links(owner)
            import shutil
            shutil.rmtree(owner)

    def test_partition_real_round33_names(self):
        build = getattr(e, 'build_round40_selection', None)
        self.assertTrue(callable(build), 'Round40 explicit mode partition missing')
        old = e.load(e.PROJECT / 'reports/refactoring/round33-integrated-b9fbd2011963493eaf6b76f02032de1e/manifest.json')
        selection = build(old)
        self.assertEqual(selection['original_count'], 66)
        self.assertEqual(selection['selected_count'], 70)
        self.assertEqual(len(selection['headless']), 69)
        self.assertEqual(selection['categories']['gui_required'], ['local_spell_restore_test'])
        self.assertEqual(selection['categories']['long_correctness'], ['net_server_gateway_restart_test'])
        self.assertEqual(selection['categories']['scoped_bind_negative'], ['gateway_bind_failure_test'])
        self.assertNotIn('local_spell_restore_test', selection['focused'])
        self.assertNotIn('net_server_gateway_restart_test', selection['focused'])
        self.assertIn('round39_restore_transaction_test', selection['focused'])
        self.assertEqual(set(selection['headless']) | {'local_spell_restore_test'}, set(selection['names']))
        with self.assertRaises(ValueError):
            build(dict(old, selected_suites=old['selected_suites'][:-1]))

    def test_protocol_rejects_prefix_suite_duplicate_and_check_ids(self):
        self.assertFalse(e.analyze('RESULT alpha suite="alpha" checks=1 failures=[]', '', 0)['passed'])
        self.assertFalse(e.analyze('CHECK id=1 first true\nCHECK id=1 second true\nRESULT checks=2 failures=[]', '', 0)['passed'])
        self.assertTrue(e.analyze('CHECK repeat true\nCHECK repeat true\nRESULT checks=2 failures=[]', '', 0)['passed'])

    def test_round40_summary_does_not_count_history_or_focused(self):
        summary = getattr(e, 'summarize_round40', None)
        self.assertTrue(callable(summary), 'Round40 phase-aware summary missing')
        clean = {'selected_suites':['a_test'], 'suites':[{'suite':'a_test','passed':True,'result':{'checks':1},'errors':[]}],
                 'focused_expected':['a_test'], 'focused':[{'suite':'a_test','passed':True}],
                 'import':{'exit':0,'errors':[]}, 'editor_transform':{'verified':True,'unauthorized_changes':[]},
                 'user_probes':[{'role':'main','worker_pool_max_threads':20},{'role':'worker','worker_pool_max_threads':20}],
                 'processes':[{'exited':True,'active_owned_processes':0,'log_handles_released':True}],
                 'cleanup':'generated_removed','engine_source_unchanged':True,'selection_inputs_unchanged':True,
                 'history':{'passed':True,'checks':999}, 'pre_full_drift':[], 'archive_verified':True}
        self.assertTrue(summary(clean)['headless_candidate_passed'])
        self.assertFalse(summary(clean)['release_passed'])
        for change in [{'suites':[]},{'focused':[]},{'focused':[{'suite':'a_test','passed':False}]},
                       {'pre_full_drift':['changed']},{'import':{'exit':0,'errors':['ERROR: real']}},
                       {'final_drift':['changed']},{'archive_verified':False},
                       {'full_safety_blockers':[{'suite':'unsafe'}]}]:
            self.assertFalse(summary(dict(clean,**change))['headless_candidate_passed'], change)

    def test_round40_exact_count_and_explicit_roots(self):
        analysis = getattr(e, 'analyze_round40_suite', None)
        command = getattr(e, 'round40_command', None)
        self.assertTrue(callable(analysis) and callable(command), 'Round40 contracts missing')
        for name, count in [('newspecial_spell_materialization_test',13),('command_spell_source_activation_test',54),
                            ('round39_restore_transaction_test',61),('assembly_publish_lifecycle_test',66),
                            ('client_match_inbox_contract_test',45)]:
            good = 'RESULT checks=%d failures=[]' % count
            self.assertTrue(analysis(name,good,'',0,e.PROJECT,{})['passed'])
            self.assertFalse(analysis(name,good.replace('checks=%d'%count,'checks=1'),'',0,e.PROJECT,{})['passed'])
        for name in ['net_server_gateway_test','net_server_discovery_validation_test','net_server_gateway_restart_test',
                     'round39_restore_transaction_test','assembly_publish_lifecycle_test']:
            self.assertEqual(command(Path('E:/e.exe'),Path('E:/p'),name,Path('E:/owned/root'))[-2:],['--','E:/owned/root'])
        with self.assertRaises(ValueError):
            command(Path('E:/e.exe'),Path('E:/p'),'local_spell_restore_test',Path('E:/owned/root'))

    def test_round41_selection_reader_and_safe_complete_partition(self):
        build = getattr(e, 'build_round41_selection', None)
        self.assertTrue(callable(build), 'Round41 reader/safety partition missing')
        old = e.load(e.PROJECT / 'reports/refactoring/round33-integrated-b9fbd2011963493eaf6b76f02032de1e/manifest.json')
        selection = build(old)
        self.assertEqual(selection['selected_count'], 71)
        self.assertEqual(len(selection['headless']), 70)
        self.assertEqual(selection['focused'][:2], ['net_validation_hard_timeout_test','validation_checkpoint_reader_test'])
        self.assertEqual(len(selection['focused']), 18)
        self.assertEqual(selection['categories']['gui_required'], ['local_spell_restore_test'])
        self.assertEqual(e.ROUND40_EXPECTED_CHECKS.get('net_validation_hard_timeout_test'),37)
        self.assertEqual(e.ROUND40_EXPECTED_CHECKS.get('validation_checkpoint_reader_test'),10)
        self.assertFalse(e.analyze_round40_suite('net_validation_hard_timeout_test','RESULT checks=37 failures=[]','ERROR: Parse JSON failed',0,e.PROJECT,{})['passed'])
        self.assertFalse(e.analyze_round40_suite('validation_checkpoint_reader_test','RESULT checks=9 failures=[]','',0,e.PROJECT,{})['passed'])

    def test_round41_output_contract_blocks_unowned_and_keeps_summary_red(self):
        partition = getattr(e, 'round41_runnable_partition', None)
        self.assertTrue(callable(partition), 'Round41 safe executable partition missing')
        blockers=[{'suite':'unsafe','path':'tests/unsafe.gd','source_sha256':'bound'}]
        value=partition(['safe','unsafe'],blockers)
        self.assertEqual(value,{'runnable':['safe'],'blocked':['unsafe']})
        with self.assertRaises(ValueError): partition(['safe'],blockers)
        with self.assertRaises(ValueError): partition(['safe','safe'],[])
        self.assertFalse(e.analyze('RESULT checks=1 failures=[]','ERROR: expected engine outside negative',0)['passed'])

if __name__ == '__main__':
    unittest.main(verbosity=2)
