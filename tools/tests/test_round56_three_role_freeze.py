"""Python-only gates: temporary files are synthetic fixtures, not runtime proof."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
MODULE = REPO / 'tools/release/round56_three_role_freeze.py'


class FreezeGateTests(unittest.TestCase):
    def setUp(self):
        # Own a checked physical E fixture root; never inherit host TMPDIR.
        scratch = self.module().checked(Path('E:/scratch'))
        if scratch.drive.upper() != 'E:':
            raise ValueError('PHYSICAL_APPROVED_E_ROOT_REQUIRED')
        self.scratch = Path(self.enterContext(tempfile.TemporaryDirectory(
            prefix='round56-freeze-', dir=scratch)))

    def module(self):
        spec = importlib.util.spec_from_file_location('round56_gate_test', MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def fixture(self, base):
        source = base / 'source'; source.mkdir()
        names = {
            'project.godot': '[application]\nrun/main_scene="res://assets/scenes/main_menu/server_bootstrap.tscn"\n[threading]\nworker_pool/max_threads=20\n',
            'export_presets.cfg': '[preset.0]\nname="FateServer Windows"\nplatform="Windows Desktop"\n',
            'icon.svg': '<svg/>', 'icon.svg.import': '',
            'assets/config/server.cfg': '[data]\nrandom_sim_enabled = true\nrandom_sim_budget_sec = 15.0\n',
            'addons/fate_server_signals/fate_server_signals.gdextension': '[libraries]\nwindows.release.x86_64="res://addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll"\n',
            'addons/webrtc_native/webrtc_native.gdextension': '[libraries]\nwindows.release.x86_64="res://addons/webrtc_native/lib/libwebrtc_native.windows.template_release.x86_64.dll"\n',
            'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll': 'OLD_DLL_FIXTURE',
            'addons/webrtc_native/lib/libwebrtc_native.windows.template_release.x86_64.dll': 'WEBRTC_FIXTURE',
            'addons/fate_server_signals/SConstruct': 'contract',
            'addons/fate_server_signals/src/process_owner_binding.cpp': 'new tree_observe',
        }
        for rel in (
            'scripts/net/server/server_console_channel.gd', 'scripts/io/native_capability_view.gd',
            'scripts/net/server/server_bootstrap.gd', 'scripts/net/server/server_cli.gd',
            'scripts/net/server/server_room_manager.gd', 'scripts/net/server/server_shutdown.gd',
            'scripts/game_scene/battle_board_v2.gd', 'scripts/net/ui/v2_view_presenter.gd',
            'scripts/net/ui/room_data_panel.gd', 'scripts/net/server/server_data_approval.gd',
            'scripts/net/server/server_process_signals.gd', 'scripts/net/p2p/p2p_signal_server.gd',
            'scripts/net/p2p/p2p_invite.gd', 'scripts/net/transport/webrtc_link.gd',
            'assets/scenes/main_menu/server_bootstrap.tscn',
        ): names[rel] = 'fixture only, not executable Godot proof'
        for rel, text in names.items():
            p=source/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text,encoding='utf-8')
        m=self.module()
        for rel in m.TOOLS:
            p=source/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_bytes((REPO/rel).read_bytes())
        self.assertTrue(callable(getattr(m,'current_inventory',None)), 'current-source/dependency/native preflight not implemented')
        inventory=m.current_inventory(source)
        approval=base/'approved'; approval.mkdir()
        deps={}
        for name in m.DEPENDENCIES:
            report=base/(name+'.json')
            data={'source_files':inventory['source_files'],'exit_code':0,'errors':[], 'complete':True}
            if name == 'current_headless':
                data['steps']={key:{'exit_code':0,'errors':[],'freeze':'fixture-freeze'} for key in ('selection_ready','required')}
            if name == 'native_compile':
                artifact=base/'new-compiled-fixture.dll'; artifact.write_bytes(b'NEW_DLL_FIXTURE_NOT_NATIVE_PROOF')
                commands=[]
                for stage in ('compile-process_owner_binding','plugin-link'):
                    log=base/(stage+'.raw.log'); log.write_bytes(b'UNIT_FIXTURE_NOT_COMPILER_OUTPUT')
                    commands.append({'stage':stage,'exit':0,'raw_sha256':m.sha(log)})
                data.update(dll={'path':str(artifact),'sha256':m.sha(artifact),'checks':{'pe_x64':True}},
                            output=str(base),
                            translation_units=[str(source/'addons/fate_server_signals/src/process_owner_binding.cpp')],
                            commands=commands)
            report.write_text(json.dumps(data),encoding='utf-8')
            deps[name]={'path':str(report),'sha256':m.sha(report),'source_pointer':'/source_files',
                         'checks':[{'pointer':'/exit_code','equals':0},{'pointer':'/errors','equals':[]},{'pointer':'/complete','equals':True}]}
            if name == 'current_headless':
                deps[name]['headless_steps']={key:{'exit_pointer':'/steps/'+key+'/exit_code',
                    'errors_pointer':'/steps/'+key+'/errors','freeze_pointer':'/steps/'+key+'/freeze'} for key in ('selection_ready','required')}
            if name == 'native_compile':
                deps[name].update(compile_steps={'addons/fate_server_signals/src/process_owner_binding.cpp':0},link_step=1)
        token={'schema':1,'approved_by':'main','freeze_ready':True,'source':str(source.resolve()),
               'source_fingerprint':inventory['source_fingerprint'],'approved_root':str(approval.resolve()),
               'root':str((approval/'new').resolve()), 'claim_new_job':False,'dependencies':deps}
        tokenpath=base/'ready.json'; tokenpath.write_text(json.dumps(token),encoding='utf-8')
        return m,source,approval,tokenpath,token

    def check_fixture(self, mutate=None, error=None):
        scratch=self.scratch
        with tempfile.TemporaryDirectory(prefix='round56-unit-',dir=scratch) as temp:
            m,source,approval,path,token=self.fixture(Path(temp))
            if mutate: mutate(m,source,approval,path,token)
            path.write_text(json.dumps(token),encoding='utf-8')
            if error:
                with self.assertRaisesRegex(ValueError,error):
                    m.preflight(source,path,approval/'new',approval)
            else:
                result=m.preflight(source,path,approval/'new',approval)
                self.assertTrue(result['allow_build']); self.assertFalse((approval/'new').exists())
                self.assertTrue(result['native']['production_blocked'])
                self.assertEqual(result['runtime']['status'],'NOTIMPLEMENTED')

    def test_good_preflight_only_never_creates_root(self):
        self.check_fixture()

    def test_wrong_source_hash(self):
        self.check_fixture(lambda m,s,a,p,t:t.update(source_fingerprint='0'*64),'SOURCE_FINGERPRINT_MISMATCH')

    def test_old_dll_cannot_claim_new_job(self):
        self.check_fixture(lambda m,s,a,p,t:t.update(claim_new_job=True),'NEW_NATIVE_PRODUCTION_BLOCKED')

    def test_unread_status_report(self):
        self.check_fixture(lambda m,s,a,p,t:Path(t['dependencies']['runtime_observation']['path']).unlink(),'DEPENDENCY_UNREADABLE: runtime_observation')

    def test_missing_shutdown_handoff_report(self):
        self.check_fixture(lambda m,s,a,p,t:t['dependencies'].pop('shutdown_handoff'),'MISSING_DEPENDENCY: shutdown_handoff')

    def test_old_failcache_root_refused(self):
        self.check_fixture(lambda m,s,a,p,t:(a/'new').mkdir(),'FRESH_ROOT_REQUIRED')

    def test_mandatory_native_asset_missing(self):
        self.check_fixture(lambda m,s,a,p,t:(s/'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll').unlink(),'MANDATORY_NATIVE_ASSET')

    def test_changed_declared_report_hash(self):
        self.check_fixture(lambda m,s,a,p,t:t['dependencies']['gui'].update(sha256='0'*64),'DEPENDENCY_HASH_MISMATCH: gui')

    def test_stale_shutdown_source(self):
        def mutate(m,s,a,p,t):
            dep=t['dependencies']['shutdown_handoff']; report=Path(dep['path']); data=json.loads(report.read_text())
            data['source_files']['scripts/net/server/server_shutdown.gd']='0'*64
            report.write_text(json.dumps(data)); dep['sha256']=m.sha(report)
        self.check_fixture(mutate,'DEPENDENCY_SOURCE_MISMATCH: shutdown_handoff')

    def test_gui_failure_is_not_export_excuse(self):
        def mutate(m,s,a,p,t):
            dep=t['dependencies']['gui']; report=Path(dep['path']); data=json.loads(report.read_text()); data['exit_code']=1
            report.write_text(json.dumps(data)); dep['sha256']=m.sha(report)
        self.check_fixture(mutate,'DEPENDENCY_CHECK_FAILED: gui')

    def test_headless_requires_both_same_freeze_steps(self):
        def mutate(m,s,a,p,t):
            dep=t['dependencies']['current_headless']; report=Path(dep['path']); data=json.loads(report.read_text())
            data['steps']['required']['freeze']='another-freeze'
            report.write_text(json.dumps(data)); dep['sha256']=m.sha(report)
        self.check_fixture(mutate,'HEADLESS_STEP_FREEZE_MISMATCH')

    def test_native_compile_report_without_real_output_refused(self):
        def mutate(m,s,a,p,t):
            dep=t['dependencies']['native_compile']; report=Path(dep['path']); data=json.loads(report.read_text())
            data.pop('dll',None); report.write_text(json.dumps(data)); dep['sha256']=m.sha(report)
        self.check_fixture(mutate,'NATIVE_COMPILE_OUTPUT_UNPROVEN')

    def test_build_plan_same_fingerprint_and_supported_signaling(self):
        scratch=self.scratch
        with tempfile.TemporaryDirectory(prefix='round56-plan-',dir=scratch) as temp:
            m,s,a,p,t=self.fixture(Path(temp)); approved=m.preflight(s,p,a/'new',a)
            self.assertTrue(callable(getattr(m,'build_plan',None)), 'same-source three-role build plan missing')
            plan=m.build_plan(approved)
            self.assertEqual(set(plan['roles']),{'client','server','signaling'})
            self.assertEqual({r['source_fingerprint'] for r in plan['roles'].values()},{approved['source_fingerprint']})
            self.assertEqual(plan['roles']['signaling']['preparer'],'tools.release.signaling_prepare.prepare')
            self.assertEqual(plan['roles']['signaling']['native_deployment'],'external-supported-runtime')
            self.assertFalse(plan['formal_runtime_implemented'])
            self.assertFalse((a/'new').exists())

    def test_existing_build_api_signatures_without_processes(self):
        import inspect
        from unittest.mock import patch
        with patch('subprocess.Popen', side_effect=AssertionError('Python-only verification must not spawn')):
            from tools.tests import round52_current_role_candidates as runner
            from tools.release import signaling_prepare as signaling
            from tools.release import package_audit, release_contract, freeze_prepare
            inspect.signature(runner.run).bind(Path('E:/new'),{},'label',[],Path('E:/new'),timeout=180)
            inspect.signature(runner.transformed_presets).bind(Path('E:/snapshot'),'client',[])
            inspect.signature(signaling.prepare).bind(Path('E:/sample'),Path('E:/snapshot'))
            inspect.signature(signaling.audit).bind(Path('E:/package'),Path('E:/sample'))
            inspect.signature(package_audit.audit).bind(Path('E:/project'),Path('E:/package'),Path('E:/audit.json'),'preset','windows','server')
            inspect.signature(release_contract.copy_runtime).bind(Path('E:/project'),Path('E:/package'),'preset','windows','server')
            inspect.signature(freeze_prepare.transform).bind(Path('E:/snapshot'),None,[])

    def test_missing_ready_token_refuses_without_build(self):
        if not MODULE.exists():
            self.fail('round56 preflight missing: no explicit ready-token rejection')
        spec = importlib.util.spec_from_file_location('round56_gate_test', MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with self.assertRaisesRegex(ValueError, 'READY_TOKEN_REQUIRED'):
            module.preflight(REPO, None, Path('E:/FateCandidates/new-uncreated'), Path('E:/FateCandidates'))


if __name__ == '__main__':
    unittest.main()
