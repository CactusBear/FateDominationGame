"""Round64 count contracts; fixture text here is unit input, never Godot evidence."""
import sys
sys.dont_write_bytecode = True
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('round64_e', Path(__file__).with_name('test_round29_integrated_evidence.py'))
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)


def wire(count):
    return '\n'.join('CHECK true id=event_%d unit event' % i for i in range(count)) + '\nRESULT checks=%d failures=[]' % count


class CountContractTests(unittest.TestCase):
    def test_added_checks_preserve_positive_legacy_floor(self):
        name = 'worker_content_environment_test'
        self.assertTrue(e.analyze_round50_suite(name, wire(46), '', 0, e.PROJECT, {})['passed'],
                        'legitimate extra check is not a coverage regression')
        self.assertFalse(e.analyze_round50_suite(name, wire(44), '', 0, e.PROJECT, {})['passed'])
        for out, err in [(wire(46).replace('CHECK true', 'CHECK false', 1), ''),
                         (wire(46), 'ERROR: extra'), (wire(46), 'SCRIPT ERROR: extra'),
                         (wire(46) + '\nRESULT checks=46 failures=[]', ''),
                         (wire(46).replace('id=event_1 ', 'id=event_0 ', 1), ''),
                         (wire(46).replace('checks=46', 'checks=47'), '')]:
            self.assertFalse(e.analyze_round50_suite(name, out, err, 0, e.PROJECT, {})['passed'])

    def test_refreshed_selection_and_real_path_api(self):
        old=e.load(e.PROJECT/e.ROUND50_BASE_MANIFEST)
        selection=e.build_round50_selection(old,e.PROJECT)
        self.assertIn('loader_error_boundary_test',selection['headless'])
        self.assertEqual(selection['headless_count'],99)
        for name,count in {'battle_board_end_command_test':46,'round28-command-migration_test':74,
                           'battle_board_activation_command_test':21,'active_choice_source_command_test':65,
                           'location_choice_source_command_test':37,'player_choice_source_command_test':65,
                           'battle_play_groups_test':56,'loader_error_boundary_test':62}.items():
            self.assertEqual(selection['mandatory_checks'][name],count)
            self.assertTrue(e.analyze_round50_suite(name,wire(count),'',0,e.PROJECT,{})['passed'])
            self.assertFalse(e.analyze_round50_suite(name,wire(count-1),'',0,e.PROJECT,{})['passed'])
        self.assertEqual(e.round50_command('E:/Godot.exe','E:/project','loader_error_boundary_test','E:/owned/out')[-3:],
                         ['--','E:/owned/out','green'])
        modes=selection['independent_loader_modes']
        self.assertEqual([x['mode'] for x in modes],['expectednegative','expectednegative_extra'])
        self.assertTrue(all(not x['counts_as_formal_scene'] and x['expected_checks']==9 for x in modes))
        self.assertFalse(any(x['mode'] in selection['names'] for x in modes))

    def test_small_preflight_only_has_seven_real_scene_closure(self):
        import inspect
        self.assertIn('contract_proof',inspect.signature(e.round50_preflight).parameters)
        from unittest.mock import patch
        with patch.object(e.runner,'execute',side_effect=AssertionError('preflight launched Godot')):
            p=e.round50_preflight(e.PROJECT,Path('E:/scratch'),contract_proof=True)
        self.assertEqual(p['selection']['headless'],['loader_error_boundary_test']+e.ROUND64_MIGRATED_SIX)
        self.assertEqual(p['selection']['program_count'],len(p['selection']['names'])+len(p['selection']['native_standalone']))
        self.assertEqual(p['business_suites_executed'],0)
        self.assertEqual(p['selection']['parent_candidate_counts']['headless'],99)
        self.assertNotIn('tests/local_spell_restore_test.gd',p['freeze_files'])
        self.assertIn('tests/worker_content_environment_test.gd',p['freeze_files'])
        self.assertIn('assets/scenes/main_menu/room_data_validation_worker.tscn',p['freeze_files'])

    def test_all_original98_floors_and_strict_negative_partition(self):
        old=e.load(Path('E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50/manifest.json'))
        selection=e.build_round50_selection(e.load(e.PROJECT/e.ROUND50_BASE_MANIFEST),e.PROJECT)
        self.assertEqual(set(old['selected_suites']),set(e.ROUND64_BASELINE_CHECKS))
        self.assertTrue(set(old['selected_suites']).issubset(selection['headless']))
        floors=selection['mandatory_checks']
        for name,count in dict(e.ROUND40_EXPECTED_CHECKS,**e.ROUND50_CURRENT_CHECKS).items():
            self.assertGreaterEqual(floors[name],count)
        for name,floor in e.ROUND64_BASELINE_CHECKS.items():
            self.assertGreater(floor,0)
            self.assertGreaterEqual(floors[name],floor)
            # Even quiet protocols cannot claim fewer original coverage checks.
            self.assertFalse(e.analyze_round50_suite(name,'RESULT checks=%d failures=[]'%(floor-1),
                                                     '',0,e.PROJECT,{})['passed'],name)
        root=Path('E:/scratch/isolated-da02984e532f43a08e445aca142ddebb')
        out=(root/'evidence/expectednegative.stdout.log').read_text(encoding='utf-8')
        err=(root/'evidence/expectednegative.stderr.log').read_text(encoding='utf-8')
        self.assertFalse(e.analyze_round50_suite('loader_error_boundary_test',out,err,0,e.PROJECT,{})['passed'])
        # Run only the actual independent analyzer definitions, never runner main.
        import ast
        source=(e.PROJECT/'tests/round62_loader_error_boundary_runner.py').read_bytes()
        tree=ast.parse(source)
        functions=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in
                   {'analyze','errors','negative','negative_control'}]
        self.assertEqual(len(functions),4)
        ns={'re':__import__('re'),'json':__import__('json'),'r':e.runner,'g':root/'generated'}
        exec(compile(ast.Module(body=functions,type_ignores=[]),'actual_round62_negative_api','exec'),ns)
        self.assertTrue(ns['negative'](out,err,0,[])['passed'])
        for changed_out,changed_err in [(out,err+'\nERROR: unknown'),
                (out,err+'\nSCRIPT ERROR: unknown'),(out,err.replace('legacy-direct/masters','wrong/masters')),
                (out+'\nRESULT loader_error_boundary checks=9 failures=[]',err),
                (out.replace('checks=9','checks=8'),err)]:
            self.assertFalse(ns['negative'](changed_out,changed_err,0,[])['passed'])
        extra_out=(root/'evidence/expectednegative_extra.stdout.log').read_text(encoding='utf-8')
        extra_err=(root/'evidence/expectednegative_extra.stderr.log').read_text(encoding='utf-8')
        rejected=ns['negative'](extra_out,extra_err,0,[])
        self.assertFalse(rejected['passed'])
        self.assertEqual(ns['errors'](extra_out+'\n'+extra_err)[-1:],["ERROR: ROUND62_UNEXPECTED_EXTRA_ERROR"])

    def test_declared_selection_omission_and_duplicate_fail_closed(self):
        from unittest.mock import patch
        old=e.load(e.PROJECT/e.ROUND50_BASE_MANIFEST)
        with patch.object(e,'ROUND50_ADDITIONS',e.ROUND50_ADDITIONS+['loader_error_boundary_test']):
            with self.assertRaises(ValueError):e.build_round50_selection(old,e.PROJECT)
        with patch.object(e,'ROUND50_ADDITIONS',[n for n in e.ROUND50_ADDITIONS if n!='net_server_relay_cfg_test']):
            selection=e.build_round50_selection(old,e.PROJECT)
            self.assertTrue(any(r['suite']=='net_server_relay_cfg_test' for r in selection['blocked_not_landed']))


def audit(approved_root):
    """Read original/raw RESULT bytes; counts are historical evidence, no PASS credit."""
    import re, uuid
    from collections import Counter
    root=e.runner.physical_e(approved_root)/('round64-contract-audit-'+uuid.uuid4().hex)
    root.mkdir()
    original=Path('E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50')
    old=e.load(original/'manifest.json'); original_sha=e.digest(original/'manifest.json')
    selection=e.build_round50_selection(e.load(e.PROJECT/e.ROUND50_BASE_MANIFEST),e.PROJECT)
    refresh={}
    six=Path('E:/scratch/round60-fixture-f8a66eb3fde84cabb78eae5ee64eb735')
    six_m=e.load(six/'manifest.json')
    for row in six_m['suites']:
        name=row['suite']; out=(six/'evidence'/ (name+'.stdout.log')).read_text(encoding='utf-8')
        err=(six/'evidence'/ (name+'.stderr.log')).read_text(encoding='utf-8')
        parsed=e.analyze_round50_suite(name,out,err,0,e.PROJECT,{})
        rel='tests/'+name+'.gd'
        old_source=(original/'evidence/frozen-inputs'/rel).read_text(encoding='utf-8')
        current=(e.PROJECT/rel).read_text(encoding='utf-8')
        calls=lambda text:Counter(line.strip() for line in text.splitlines() if re.match(r'^\s*check\(',line))
        missing=list((calls(old_source)-calls(current)).elements())
        if missing:raise AssertionError('original assertions lost: '+name+repr(missing))
        refresh[name]={'checks':parsed['result']['checks'],'observed':parsed['observed_checks'],
            'reparsed_pass':parsed['passed'],'manifest':str(six/'manifest.json'),
            'manifest_sha256':e.digest(six/'manifest.json'),'source_sha256':six_m['source_hashes'][rel],
            'current_source_matches':six_m['source_hashes'][rel]==e.digest(e.PROJECT/rel),'missing_original_check_calls':missing}
    loader=Path('E:/scratch/isolated-da02984e532f43a08e445aca142ddebb')
    loader_m=e.load(loader/'manifest.json')
    item=loader_m['suites']['loader_error_boundary']
    refresh['loader_error_boundary_test']={'checks':item['analysis']['result']['checks'],
        'manifest':str(loader/'manifest.json'),'manifest_sha256':e.digest(loader/'manifest.json'),
        'source_sha256':loader_m['source_before']['tests/loader_error_boundary_test.gd']}
    group=Path('E:/scratch/round60-play-groups-final/isolated-712950fb4ee8428f99c67381c531b90c')
    group_m=e.load(group/'manifest.json')
    for row in group_m['suites']:
        if row['mode']=='headless':
            refresh['battle_play_groups_test']={'checks':row['analysis']['result']['checks'],
                'manifest':str(group/'manifest.json'),'manifest_sha256':e.digest(group/'manifest.json'),
                'source_sha256':group_m['source_hashes']['tests/battle_play_groups_test.gd']}
    rows=[]
    for name in old['selected_suites']:
        row=next(x for x in old['suites'] if x['suite']==name)
        out=(original/'evidence'/('complete-'+name+'.stdout.log')).read_text(encoding='utf-8')
        err=(original/'evidence'/('complete-'+name+'.stderr.log')).read_text(encoding='utf-8')
        original_parsed=e.analyze(out,err,row['exit'])
        rows.append({'suite':name,'original_declared_checks':(original_parsed['result'] or {}).get('checks'),
            'original_observed_checks':original_parsed['observed_checks'],'original_pass':row['passed'],
            'legacy_minimum':e.ROUND64_BASELINE_CHECKS[name],'current_mandatory':selection['mandatory_checks'][name],
            'new_current_special_evidence':refresh.get(name),'new_execution_status':'not_run_in_this_audit'})
    p=e.round50_preflight(e.PROJECT,Path(approved_root))
    result={'original_count':len(rows),'original_actual':len(old['suites']),
        'original_pass':sum(r['passed'] for r in old['suites']),
        'original_red':sum(not r['passed'] for r in old['suites']),
        'original_manifest_sha256':original_sha,'original_unchanged':e.digest(original/'manifest.json')==original_sha,
        'rows':rows,'new_loader':refresh['loader_error_boundary_test'],
        'six_actual_declared_checks':sum(refresh[n]['checks'] for n in e.ROUND64_MIGRATED_SIX),
        'selection_counts':{'formal':selection['selected_count'],'headless':selection['headless_count'],
            'programs':selection['program_count'],'modes':{k:len(v) for k,v in selection['categories'].items()},
            'required_harness':selection['required_harness_count'],'independent_loader_modes':len(selection['independent_loader_modes'])},
        'preflight_status':p['status'],'preflight_blockers':p['blockers'],
        'dependency_count':len(p['freeze_files']),'dependency_hashes':p['freeze_hashes'],
        'sourcePASS':False,'releasePASS':False,'business_suites_executed':0}
    assert len(rows)==len({r['suite'] for r in rows})==98 and result['six_actual_declared_checks']==308
    e.save(root/'audit.json',result);e.save(root/'preflight.json',p)
    (root/'source-dependencies.txt').write_text('\n'.join(p['freeze_files'])+'\n',encoding='utf-8')
    print(__import__('json').dumps({'audit':str(root/'audit.json'),
        'selection_counts':result['selection_counts'],'status':p['status'],
        'original_actual':result['original_actual'],'original_pass':result['original_pass'],
        'original_red':result['original_red'],'six_checks':result['six_actual_declared_checks'],
        'dependency_count':result['dependency_count']},ensure_ascii=False))


def verify_proof(manifest):
    path=e.runner.contained(Path(manifest),e.runner.physical_e('E:/scratch'))
    m=e.load(path);owner=path.parent;target=Path(m['generated'])/'project'
    actual=[]
    for row in m['suites']:
        name=row['suite'];label='complete-'+name
        out=(owner/'evidence'/(label+'.stdout.log')).read_text(encoding='utf-8')
        err=(owner/'evidence'/(label+'.stderr.log')).read_text(encoding='utf-8')
        parsed=e.analyze_round50_suite(name,out,err,row['exit'],target,m['frozen_hashes'])
        actual.append({'suite':name,'exit':row['exit'],'declared':parsed['result']['checks'],
                       'observed':parsed['observed_checks'],'strict_pass':parsed['passed']})
    logs_ok=all(e.digest(owner/x['path'])==x['sha256'] for x in m['logs'])
    frozen_drift=[rel for rel,sha in m['frozen_hashes'].items() if e.digest(target/rel)!=sha]
    current_drift=[rel for rel,sha in m['freeze_before'].items() if e.digest(e.PROJECT/rel)!=sha]
    reports=[]
    for art in m['worker_artifacts']:
        p=owner/art['path']
        if p.name!='report.json':continue
        value=e.load(p)
        if {'masters','servants','random_simulation'}.issubset(value):
            reports.append({'path':art['path'],'ok':value.get('ok'),'masters':value['masters'],
                'servants':value['servants'],'errors':value.get('errors'),'simulation':value['random_simulation']})
    old=Path('E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50/manifest.json')
    result={'manifest':str(path),'manifest_sha256':e.digest(path),'rows':actual,
        'actual':len(actual),'unique':len({r['suite'] for r in actual}),
        'checks':sum(r['observed'] for r in actual),'declared':sum(r['declared'] for r in actual),
        'strict_passes':sum(r['strict_pass'] for r in actual),'archive_verified':logs_ok,
        'frozen_drift':frozen_drift,'current_drift_after_execution':current_drift,
        'executed_final_drift':m['final_drift'],'own_job_active_sum':sum(p['active_owned_processes'] for p in m['processes']),
        'all_owned_exited_and_handles_released':all(p['exited'] and p['log_handles_released'] for p in m['processes']),
        'process_count':len(m['processes']),'bytes_still_in_owner':e.runner.tree_bytes(owner),
        'byte_budget':8589934592,'no_runtime_deletion':all(r['runtime_reclamation']['status']=='retained_no_reclamation'
            for r in m['prerequisites']+m['suites']),
        'worker_engine_errors':m['worker_engine_errors'],'actual_worker_reports':reports,
        'freeze_input_count':len(m['freeze_before']),'engine_sha256':m['engine_sha256'],
        'dll_sha256':m['freeze_before']['addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll'],
        'original98_manifest_sha256':e.digest(old),'sourcePASS':False,'releasePASS':False}
    assert result['actual']==result['unique']==result['strict_passes']==7 and result['checks']==result['declared']==370
    assert logs_ok and not frozen_drift and result['own_job_active_sum']==0
    assert result['all_owned_exited_and_handles_released'] and not result['worker_engine_errors']
    assert result['no_runtime_deletion'] and not result['executed_final_drift']
    e.save(owner/'round64-verification-readback.json',result)
    print(__import__('json').dumps(result,ensure_ascii=False))


if __name__ == '__main__':
    if '--verify-proof' in sys.argv:
        verify_proof(sys.argv[sys.argv.index('--verify-proof')+1])
    elif '--audit' in sys.argv:
        audit(sys.argv[sys.argv.index('--audit')+1])
    else:
        unittest.main(verbosity=2)
