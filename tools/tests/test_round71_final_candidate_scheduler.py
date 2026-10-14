"""Scheduler boundary units; synthetic wire data is never Godot PASS evidence."""
import sys
sys.dont_write_bytecode = True
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('round71_e', Path(__file__).with_name('test_round29_integrated_evidence.py'))
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)


class FrozenSchedulerTests(unittest.TestCase):
    def test_variable_screenshot_output_is_not_a_static_input(self):
        resolver = getattr(e, 'round71_declared_outputs', None)
        self.assertTrue(callable(resolver), 'explicit variable output resolver missing')
        code = 'func shot():\n\tvar path := "res://tests/runtime_reports/red.png"\n\timage.save_png(path)\n'
        self.assertEqual(resolver(code), {'tests/runtime_reports/red.png'})
        self.assertEqual(resolver(code.replace('save_png(path)', 'load(path)')), set())
        self.assertEqual(resolver(code.replace('image.save_png(path)', 'pass\nfunc unrelated():\n\timage.save_png(path)')), set())

    def test_prepare_serializable_hash_contract_and_notready_slots(self):
        prepare = getattr(e, 'round71_prepare', None)
        self.assertTrue(callable(prepare), 'staged frozen-input adapter missing')
        with tempfile.TemporaryDirectory(prefix='round71-unit-', dir='E:/scratch') as directory:
            root = Path(directory)
            (root/'producer.gd').write_text('stable producer', encoding='utf-8')
            hashes = {'producer.gd':e.digest(root/'producer.gd')}
            p = {'status':'selection_ready','blockers':[], 'source_root':str(root), 'approved_root':str(root),
                 'freeze_files':list(hashes), 'freeze_hashes':hashes,
                 'parent_source_fingerprint':e.round50_source_fingerprint(hashes),
                 'selection':{'names':['stable_test'],'headless':['stable_test'],'selected_count':1,'headless_count':1,
                              'program_count':1,'categories':{'short_headless':['stable_test']},'native_standalone':[],
                              'mandatory_checks':{'stable_test':7},'required_harness_steps':[]}}
            plan = prepare(p)
            self.assertEqual(plan['schema'],'round71-frozen-candidate/v1')
            self.assertEqual(plan['preflight']['freeze_hashes'],hashes)
            self.assertEqual([x['status'] for x in plan['integration_dependencies']],['NOTREADY','NOTREADY'])
            self.assertFalse(plan['ready_for_full'])
            self.assertEqual(plan['preflight']['selection']['mandatory_checks']['stable_test'],7)
            self.assertEqual(e.round71_validate_prepared(plan,proof=True)['freeze_hashes'],hashes)
            with self.assertRaises(e.runner.SafetyError):e.round71_validate_prepared(plan)
            (root/'producer.gd').write_text('parallel write',encoding='utf-8')
            with self.assertRaises(e.runner.SafetyError):e.round71_validate_prepared(plan,proof=True)

    def test_approved_newtests_contracts_are_wired_not_name_pass(self):
        with tempfile.TemporaryDirectory(prefix='round71-approved-',dir='E:/scratch') as directory:
            root=Path(directory)
            paths={path:'func producer():\n\tpass\n' for group in e.ROUND71_INTEGRATION_PRODUCERS.values() for path in group}
            paths['tests/stable_test.gd']='extends Node\n'
            paths['tests/stable_test.tscn']='[gd_scene format=3]\n'
            for rel,text in paths.items():
                (root/rel).parent.mkdir(parents=True,exist_ok=True);(root/rel).write_text(text,encoding='utf-8')
            hashes={rel:e.digest(root/rel) for rel in paths}
            p={'status':'selection_ready','blockers':[],'source_root':str(root),'approved_root':str(root),
               'freeze_hashes':hashes,'freeze_files':sorted(hashes),'parent_source_fingerprint':e.round50_source_fingerprint(hashes),
               'selection':{'names':['stable_test'],'headless':['stable_test'],'selected_count':1,'headless_count':1,'program_count':1,
                            'categories':{'short_headless':['stable_test'],'gui_required':[]},'native_standalone':[],
                            'mandatory_checks':{'stable_test':7},'required_harness_steps':[]}}
            approved={'schema':'round71-approved-inputs/v1','dependency_hashes':dict(hashes),'integrations':[]}
            for index,(identity,producers) in enumerate(e.ROUND71_INTEGRATION_PRODUCERS.items()):
                suite='owned_'+identity+'_test';script='newtests/'+suite+'.gd';scene='newtests/'+suite+'.tscn'
                (root/script).parent.mkdir(exist_ok=True)
                (root/script).write_text('extends Node\nfunc finish():\n\tprint("RESULT checks=7 failures=[]")\n',encoding='utf-8')
                (root/scene).write_text('[gd_scene format=3]\n[ext_resource type="Script" path="res://'+script+'" id="1"]\n',encoding='utf-8')
                deps={rel:e.digest(root/rel) for rel in [script,scene]}
                approved['dependency_hashes'].update(deps)
                approved['integrations'].append({'id':identity,'suite':suite,'mode':'short_headless' if index else 'gui_required',
                    'scene':scene,'script':script,'minimum_checks':7,'dependency_hashes':deps,
                    'producer_hashes':{rel:hashes[rel] for rel in producers}})
            prepare=getattr(e,'round71_prepare',None)
            plan=prepare(p,approved)
            self.assertTrue(plan['ready_for_full'])
            self.assertTrue(all(row['execution_status']=='not_run' for row in plan['integration_dependencies']))
            result=e.round71_validate_prepared(plan)
            self.assertEqual(result['selection']['selected_count'],3)
            self.assertEqual(result['selection']['headless_count'],2)
            self.assertEqual(result['selection']['mandatory_checks']['owned_cardback_privacy_test'],7)
            command=e.round71_suite_command('E:/Godot.exe',root,'owned_cardback_privacy_test',root,result['selection'])
            self.assertIn('res://newtests/owned_cardback_privacy_test.tscn',command)
            good='\n'.join(['CHECK true unit']*7)+'\nRESULT checks=7 failures=[]'
            self.assertTrue(e.round71_analyze_suite('owned_cardback_privacy_test',good,'',0,root,{},result['selection'])['passed'])
            self.assertFalse(e.round71_analyze_suite('owned_cardback_privacy_test',good.replace('checks=7','checks=6'),'',0,root,{},result['selection'])['passed'])
            bad=copy.deepcopy(approved);bad['integrations'][0]['producer_hashes'][producers[0]]='a'*64
            with self.assertRaises(e.runner.SafetyError):prepare(p,bad)
            bad=copy.deepcopy(approved);bad['integrations'].append(bad['integrations'][0])
            with self.assertRaises(e.runner.SafetyError):prepare(p,bad)
            bad=copy.deepcopy(approved);bad['integrations'][0]['minimum_checks']=1
            with self.assertRaises(e.runner.SafetyError):prepare(p,bad)
            bad=copy.deepcopy(approved);bad['integrations'][0]['scene']='newtests/not_landed.tscn'
            absent=prepare(p,bad)
            self.assertFalse(absent['ready_for_full'])
            self.assertEqual(absent['integration_dependencies'][0]['status'],'NOTREADY')

    def test_execution_uses_existing_scheduler_and_single_attempt_receipt(self):
        execute=getattr(e,'round71_execute_prepared',None)
        self.assertTrue(callable(execute),'prepared CLI execution adapter missing')
        with tempfile.TemporaryDirectory(prefix='round71-once-',dir='E:/scratch') as directory:
            root=Path(directory)
            p={'approved_root':str(root),'selection':{'headless':['stable_test']}}
            plan={'plan_id':'a'*32}
            with patch.object(e,'round71_validate_prepared',return_value=p), patch.object(e,'run_round50_full',return_value=1) as run:
                self.assertEqual(execute(plan,proof=True),1)
                run.assert_called_once_with(p,False,True,False)
                with self.assertRaises(e.runner.SafetyError):execute(plan,proof=True)
                self.assertEqual(run.call_count,1,'started failed run was retried')

    def test_negative_stale_package_duplicate_counts_and_unknown_error(self):
        old=e.load(e.PROJECT/e.ROUND50_BASE_MANIFEST)
        selection=e.build_round50_selection(old,e.PROJECT)
        with tempfile.TemporaryDirectory(prefix='round71-negatives-',dir='E:/scratch') as directory:
            root=Path(directory);producer='scripts/match/view_builder.gd'
            (root/producer).parent.mkdir(parents=True);(root/producer).write_text('unit producer',encoding='utf-8')
            hashes={producer:e.digest(root/producer)}
            p={'status':'selection_ready','blockers':[],'source_root':str(root),'approved_root':str(root),
               'freeze_hashes':hashes,'freeze_files':list(hashes),'parent_source_fingerprint':e.round50_source_fingerprint(hashes),
               'selection':selection}
            plan=e.round71_prepare(p)
            for change in ['duplicate','program_count','mandatory','forged_ready']:
                bad=copy.deepcopy(plan)
                selected=bad['preflight']['selection']
                if change=='duplicate':selected['headless'].append(selected['headless'][0])
                if change=='program_count':selected['program_count']+=1
                if change=='mandatory':selected['mandatory_checks']['worker_content_environment_test']=1
                if change=='forged_ready':
                    bad['ready_for_full']=True
                    for row in bad['integration_dependencies']:row['status']='READY'
                with self.assertRaises(e.runner.SafetyError):e.round71_validate_prepared(bad,proof=True)
            with self.assertRaises(e.runner.SafetyError):
                e.round71_prepare(p,{'schema':'package/v1','packageartifacthash':'a'*64})
            approved={'schema':'round71-approved-inputs/v1','dependency_hashes':dict(hashes),'integrations':[]}
            approved['dependency_hashes'][producer]='a'*64
            with self.assertRaises(e.runner.SafetyError):e.round71_prepare(p,approved)
        for error in ['ERROR: unknown','SCRIPT ERROR: unknown','SHADER ERROR: unknown']:
            out='\n'.join(['CHECK true stable']*45)+'\nRESULT checks=45 failures=[]'
            self.assertFalse(e.analyze_round50_suite('worker_content_environment_test',out,error,0,e.PROJECT,{})['passed'])
        self.assertEqual(selection['mandatory_checks']['worker_content_environment_test'],45)

    def test_resource_proof_recomputes_counts_and_drops_other_tests(self):
        narrow=getattr(e,'round71_resource_preflight',None)
        self.assertTrue(callable(narrow),'two-scene source closure adapter missing')
        p=e.round50_preflight(e.PROJECT,Path('E:/scratch'))
        q=narrow(p)
        e.round71_validate_selection(q['selection'])
        self.assertEqual(q['selection']['names'],['net_server_relay_cfg_test'])
        self.assertEqual(q['selection']['headless_count'],1)
        self.assertEqual(q['selection']['program_count'],1)
        self.assertEqual(q['selection']['parent_candidate_counts'],{'headless':99,'formal':101,'programs':103})
        self.assertNotIn('tests/battle_play_groups_test.gd',q['freeze_hashes'])
        self.assertIn('tests/worker_content_environment_test.gd',q['freeze_hashes'])
        self.assertEqual(q['selection']['mandatory_checks']['worker_content_environment_test'],45)

    def test_preparation_copy_verifies_each_dependency_and_retains_input(self):
        freeze=getattr(e,'round71_freeze_prepared',None)
        self.assertTrue(callable(freeze),'explicit input freeze missing')
        with tempfile.TemporaryDirectory(prefix='round71-copy-',dir='E:/scratch') as directory:
            root=Path(directory);source=root/'source';source.mkdir()
            (source/'input.gd').write_bytes(b'unit input')
            baseline=source/e.ROUND50_BASE_MANIFEST;baseline.parent.mkdir(parents=True);baseline.write_text('{}',encoding='utf-8')
            hashes={'input.gd':e.digest(source/'input.gd')}
            p={'status':'selection_ready','blockers':[],'source_root':str(source),'approved_root':str(root),
               'freeze_files':list(hashes),'freeze_hashes':hashes,'parent_source_fingerprint':e.round50_source_fingerprint(hashes),
               'baseline_manifest_sha256':e.digest(baseline),'excluded_test_hashes':{},
               'selection':{'names':['stable_test'],'headless':['stable_test'],'selected_count':1,'headless_count':1,'program_count':1,
                            'categories':{'short_headless':['stable_test']},'native_standalone':[],
                            'mandatory_checks':{'stable_test':7},'required_harness_steps':[]}}
            plan=e.round71_prepare(p);saved=freeze(plan)
            self.assertNotEqual(saved['preflight']['source_root'],str(source))
            self.assertTrue(saved['input_copy_verified'])
            self.assertEqual(e.digest(Path(saved['preflight']['source_root'])/'input.gd'),hashes['input.gd'])
            (source/'input.gd').write_bytes(b'parallel source write after freeze')
            self.assertEqual(e.round71_validate_prepared(saved,proof=True)['freeze_hashes'],hashes)
            fresh=e.round71_prepare(dict(p,freeze_hashes={'input.gd':e.digest(source/'input.gd')},
                parent_source_fingerprint=e.round50_source_fingerprint({'input.gd':e.digest(source/'input.gd')})))
            real=e.shutil.copyfile
            def corrupt(a,b):
                real(a,b);Path(b).write_bytes(b'corrupted copy')
            with patch.object(e.shutil,'copyfile',side_effect=corrupt):
                with self.assertRaises(e.runner.SafetyError):freeze(fresh)

    def test_unknown_scope_preservation_safety_and_quota(self):
        preserve=getattr(e,'round73_preserve_unknown_scope',None)
        self.assertTrue(callable(preserve),'unknown retention continuation gate missing')
        spec=importlib.util.spec_from_file_location('round73_resource_unit',Path(__file__).with_name('test_round61_runner_resource_accounting.py'))
        mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
        case=mod.RefusalTests('test_unknown_file_no_partial_deletion');case.setUp()
        try:
            case.m['retain_unknown_no_delete']=True
            unknown=case.output/'unknown.data';unknown.write_bytes(b'unknown original bytes')
            e.save(case.owner/'manifest.json',case.m)
            real=e.digest
            def no_unknown_read(path):
                self.assertNotEqual(Path(path),unknown,'unknown contents must not be read')
                return real(path)
            with patch.object(e,'digest',side_effect=no_unknown_read):
                with self.assertRaises(e.runner.SafetyError) as caught:e.round61_reclaim_runtime(case.owner,case.m,case.row,case.target)
                case.row['runtime_reclamation']={'status':'blocked_no_deletion','error':str(caught.exception)}
                e.save(case.owner/'manifest.json',case.m)
                result=preserve(case.owner,case.m,case.row,case.target)
            self.assertEqual(result['status'],'retained_unknown_scope')
            self.assertEqual(unknown.read_bytes(),b'unknown original bytes')
            self.assertTrue(e.round43_continue_after({'passed':True,'runtime_reclamation':result},case.proc,True))
            next_scope=e.round61_allocate_runtime(case.generated/'f',case.m,'complete',1,'next_test')
            self.assertTrue(next_scope.is_dir())
            e.save(case.owner/'manifest.json',case.m)
            with self.assertRaises(e.runner.SafetyError):preserve(case.owner,case.m,case.row,case.target,byte_budget=1)
            case.proc['active_owned_processes']=1;e.save(case.owner/'manifest.json',case.m)
            with self.assertRaises(e.runner.SafetyError):preserve(case.owner,case.m,case.row,case.target)
            case.proc['active_owned_processes']=0
            case.m['suite_runtime_owners'][0][0]['directory_identity'][1]+=1;e.save(case.owner/'manifest.json',case.m)
            with self.assertRaises(e.runner.SafetyError):preserve(case.owner,case.m,case.row,case.target)
            case.m['suite_runtime_owners'][0][0]['directory_identity'][1]-=1;e.save(case.owner/'manifest.json',case.m)
            import subprocess,os
            junction=case.output/'linked';destination=case.generated/'other';destination.mkdir()
            cmd=subprocess.run(['cmd.exe','/c','mklink','/J',str(junction),str(destination)],capture_output=True)
            self.assertEqual(cmd.returncode,0)
            try:
                with self.assertRaises(e.runner.SafetyError):preserve(case.owner,case.m,case.row,case.target)
            finally:os.rmdir(junction)
        finally:case.doCleanups()

    def test_retained_continuation_selects_only_never_started(self):
        select=getattr(e,'round73_continuation_names',None)
        self.assertTrue(callable(select),'retained same-freeze continuation selector missing')
        m={'selected_suites':['a','b','c'],'suites':[{'suite':'a','passed':False}],
            'processes':[{'label':'complete-a','exited':True,'active_owned_processes':0,'log_handles_released':True}],
            'archive_verified':True,'final_drift':[]}
        self.assertEqual(select(m),['b','c'])
        for bad in [dict(m,processes=m['processes']+[dict(m['processes'][0],label='complete-b')]),
                    dict(m,final_drift=['dependency']),dict(m,archive_verified=False)]:
            with self.assertRaises(e.runner.SafetyError):select(bad)

    def test_producer_retention_does_not_whitelist_other_json(self):
        policy=getattr(e,'round73_producer_retained',None)
        self.assertTrue(callable(policy),'explicit producer retention policy missing')
        contracts={'control_ipc':{'producer':'scripts/net/server/server_console_channel.gd','sha256':e.digest(e.PROJECT/'scripts/net/server/server_console_channel.gd')},
            'tag_cache':{'producer':'scripts/system/global/load_game.gd','sha256':e.digest(e.PROJECT/'scripts/system/global/load_game.gd')}}
        for rel in ['gateway-26644-4720398/console/control.json','gateway-26644-4720398/workers/79757e4c582c7bcb0ff2fd7f67303550/data/tag_list.json']:
            self.assertFalse(policy(rel,{}))
            self.assertTrue(policy(rel,contracts))
        for rel in ['unrelated.json','console/other.json','other/control.json','other/tag_list.json']:
            self.assertFalse(policy(rel,contracts))

    def test_native_gate_uses_explicit_headless_scope_not_gui(self):
        gate=getattr(e,'round73_native_preflight',None)
        self.assertTrue(callable(gate),'native prerequisite scope adapter missing')
        selection={'names':['logic_test','gui_test'],'headless':['logic_test'],'execution_scope':'current_headless_only'}
        with patch.object(e,'round42_static_preflight',return_value={'passed':True}) as actual:
            gate(selection,{},e.PROJECT)
            self.assertEqual(actual.call_args.args[0]['names'],['logic_test'])
        self.assertEqual(selection['names'],['logic_test','gui_test'])

    def test_origin_drift_is_not_hidden_by_immutable_input(self):
        drift=getattr(e,'round73_origin_drift',None)
        self.assertTrue(callable(drift),'original source hash verification missing')
        with tempfile.TemporaryDirectory(prefix='round73-origin-',dir='E:/scratch') as directory:
            root=Path(directory);(root/'included.gd').write_bytes(b'initial')
            p={'origin_source_root':root.as_posix(),'freeze_hashes':{'included.gd':e.digest(root/'included.gd')},
               'excluded_test_hashes':{'gui.gd':'a'*64}}
            self.assertEqual(drift(p),[])
            (root/'gui.gd').write_bytes(b'excluded GUI owner update')
            self.assertEqual(drift(p),[])
            (root/'included.gd').write_bytes(b'new candidate')
            self.assertEqual(drift(p),['included.gd'])

    def test_headless_scope_does_not_forge_gui_readiness(self):
        p=e.round71_current_preflight(e.PROJECT,Path('E:/scratch'))
        scope=getattr(e,'round73_headless_preflight',None)
        self.assertTrue(callable(scope),'explicit current headless scope missing')
        q=scope(p)
        plan=e.round71_prepare(q)
        self.assertTrue(plan['ready_for_headless'])
        self.assertFalse(plan['ready_for_full'])
        modal=next(r for r in plan['integration_dependencies'] if r['id']=='modal_regression')
        self.assertEqual(modal['status'],'NOTREADY')
        self.assertFalse(modal['required_for_execution'])
        self.assertEqual(q['selection']['headless'],p['selection']['headless'])
        self.assertEqual(q['selection']['names'],p['selection']['names'])
        self.assertIn('tests/local_spell_restore_test.gd',q['excluded_test_hashes'])
        self.assertNotIn('tests/local_spell_restore_test.gd',q['freeze_hashes'])
        checked=e.round71_validate_prepared(plan)
        self.assertEqual(checked['selection']['execution_scope'],'current_headless_only')
        bad=copy.deepcopy(plan);bad['preflight']['selection']['semantic_contracts']['match_view_test']['loop_maximum']=4000
        with self.assertRaises(e.runner.SafetyError):e.round71_validate_prepared(bad)

    def test_match_view_224_semantics_not_random_total(self):
        # A historical raw trace supplies labels only; altered wire is unit input,
        # never credited as a real current Godot execution.
        raw=(Path('E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50/evidence/complete-match_view_test.stdout.log')).read_text(encoding='utf-8')
        events=[x for x in raw.splitlines() if x.startswith('CHECK ') and not x.startswith('CHECK loopback step ')]
        terminal=events.pop()
        loops=['CHECK loopback step %d true'%i for i in range(1,224-len(events))]
        def wire(items):return '\n'.join(items)+'\nRESULT checks=%d failures=[]'%len(items)
        items=events+loops+[terminal]
        self.assertEqual(len(items),224)
        good=e.analyze_round50_suite('match_view_test',wire(items),'',0,e.PROJECT,{})
        self.assertTrue(good['passed'],good['reasons'])
        variants={
            'privacy_missing':[x for i,x in enumerate(items) if i!=items.index('CHECK private fields absent true')],
            'loop_gap':[x for x in items if x!='CHECK loopback step 2 true'],
            'terminal_false':items[:-1]+[terminal.replace(' true',' false')],
            'terminal_missing':items[:-1],
        }
        for name,bad in variants.items():
            with self.subTest(name=name):self.assertFalse(e.analyze_round50_suite('match_view_test',wire(bad),'',0,e.PROJECT,{})['passed'])
        self.assertFalse(e.analyze_round50_suite('match_view_test',wire(items).replace('checks=224','checks=226'),'',0,e.PROJECT,{})['passed'])
        self.assertFalse(e.analyze_round50_suite('match_view_test',wire(items),'ERROR: extra',0,e.PROJECT,{})['passed'])

    def test_round70_current_candidate_is_required_and_monotonic(self):
        current=getattr(e,'round71_current_preflight',None)
        self.assertTrue(callable(current),'approved round70 candidate wiring missing')
        p=current(e.PROJECT,Path('E:/scratch'))
        selection=p['selection']
        self.assertEqual(selection['headless_count'],len(selection['headless']))
        self.assertEqual(selection['selected_count'],len(selection['names']))
        self.assertEqual(selection['program_count'],len(selection['names'])+len(selection['native_standalone']))
        for name,minimum in {'round70_declared_card_backs_test':320,'view_builder_non_card_objects_test':11,
                'match_view_privacy_test':137,'mirror_spell_negative_test':94}.items():
            self.assertIn(name,selection['headless'])
            self.assertEqual(selection['mandatory_checks'][name],minimum)
            for suffix in ['.gd','.tscn']:self.assertIn('tests/'+name+suffix,p['freeze_hashes'])
            out='\n'.join(['CHECK true unit']*minimum)+'\nRESULT checks=%d failures=[]'%minimum
            self.assertTrue(e.round71_analyze_suite(name,out,'',0,e.PROJECT,{},selection)['passed'])
            self.assertFalse(e.round71_analyze_suite(name,out.replace('checks=%d'%minimum,'checks=%d'%(minimum-1)),'',0,e.PROJECT,{},selection)['passed'])
        self.assertEqual(selection['historical_nonmandatory_checks']['match_view_test'],226)
        self.assertEqual(selection['semantic_contracts']['match_view_test'],e.round73_match_view_contract(e.PROJECT))
        self.assertTrue(selection['round70_cardback_required'])
        plan=e.round71_prepare(p)
        cardback=next(r for r in plan['integration_dependencies'] if r['id']=='cardback_privacy')
        self.assertEqual(cardback['status'],'READY')
        self.assertEqual(cardback['execution_status'],'not_run')
        self.assertFalse(plan['ready_for_full'],'modal still NOTREADY')
        bad=copy.deepcopy(p);bad['freeze_hashes']['scripts/match/view_builder.gd']='a'*64
        with self.assertRaises(e.runner.SafetyError):e.round71_prepare(bad)


if __name__ == '__main__':
    unittest.main(verbosity=2)
