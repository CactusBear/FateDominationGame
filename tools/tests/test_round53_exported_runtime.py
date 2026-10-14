"""G05 adapter tests; fixture results are not exported-client runtime proof."""
import copy
import unittest
from tools.diagnostics import round53_exported_runtime as runtime
from tools.release.round56_three_role_freeze import fingerprint


class StartupIdentityTests(unittest.TestCase):
    def document(self):
        files = {'project.godot': 'a' * 64}
        fp = fingerprint(files)
        return {'source_files': files, 'source_fingerprint': fp,
                'roles': {'client': {'source_fingerprint': fp,
                    'declaration': {'role': 'client', 'platform': 'windows',
                                    'executable': 'FateDomination.exe'},
                    'package_files': {'FateDomination.exe': 'b' * 64,
                                      'FateDomination.pck': 'c' * 64}}}}

    def test_exact_manifest_exe_pck_and_source_binding(self):
        identity = getattr(runtime, 'startup_identity', None)
        self.assertTrue(callable(identity), 'G05 manifest startup identity adapter missing')
        result = identity(self.document())
        self.assertEqual(result['executable'], 'FateDomination.exe')
        self.assertEqual(result['pck'], 'FateDomination.pck')
        self.assertEqual(result['exe_sha256'], 'b' * 64)
        self.assertEqual(result['pck_sha256'], 'c' * 64)
        for mutate in (
            lambda d: d['roles']['client']['package_files'].pop('FateDomination.exe'),
            lambda d: d['roles']['client']['package_files'].pop('FateDomination.pck'),
            lambda d: d['roles']['client'].update(source_fingerprint='d' * 64),
            lambda d: d.update(source_fingerprint='d' * 64),
            lambda d: d['roles']['client']['declaration'].update(executable='../Other.exe'),
        ):
            broken = copy.deepcopy(self.document()); mutate(broken)
            with self.assertRaises(ValueError): identity(broken)


class StartupEvidenceTests(unittest.TestCase):
    def test_remapped_completed_main_load_is_startup_evidence(self):
        record = {'exit_code': 0, 'exited': True, 'active_owned_processes': 0,
                  'job_attached_before_resume': True,
                  'log_resource_release': {'engine': {'exclusive_read': True}}}
        main = ("Godot Engine v4.7\n"
                "Loading resource: res://.godot/exported/133200997/export-abc-opening_background.scn\n"
                "Completed load for: 'res://assets/scenes/main_menu/opening_background.tscn' "
                "remapped 'res://.godot/exported/133200997/export-abc-opening_background.scn' at thread -1\n")
        self.assertTrue(all(runtime.startup_checks(record, {'engine': main}).values()))
        completed = main.splitlines()[-1]
        for text in (
            main.replace(completed + '\n', ''),
            main.replace('opening_background.tscn', 'another_scene.tscn'),
            main.replace('opening_background.tscn', 'opening_background.tscn.fake'),
            main.replace('Completed load for:', 'Attempted load for:'),
            main.replace('Completed load for:', 'User message: Completed load for:'),
        ):
            with self.subTest(log=text):
                self.assertFalse(runtime.startup_checks(record, {'engine': text})['official_main_load_observed'])
        for mutate in (
            lambda r: r.update(exit_code=1),
            lambda r: r.pop('exit_code'),
            lambda r: r.pop('exited'),
            lambda r: r.update(active_owned_processes=1),
            lambda r: r.update(job_attached_before_resume=False),
        ):
            broken = copy.deepcopy(record); mutate(broken)
            self.assertFalse(all(runtime.startup_checks(broken, {'engine': main}).values()))
        for error in ('SCRIPT ERROR: broken script', 'DLL old.dll could not load'):
            self.assertFalse(all(runtime.startup_checks(record, {'engine': main + error}).values()))
        direct = ("Godot Engine v4.7\nCompleted load for: "
                  "'res://assets/scenes/main_menu/opening_background.tscn' at thread 0\r\n")
        self.assertTrue(all(runtime.startup_checks(record, {'engine': direct}).values()))

    def test_startup_requires_main_loading_clean_logs_and_normal_job_exit(self):
        checks = getattr(runtime, 'startup_checks', None)
        self.assertTrue(callable(checks), 'G05 startup-only evidence checks missing')
        record = {'exit_code': 0, 'exited': True, 'active_owned_processes': 0,
                  'job_attached_before_resume': True,
                  'log_resource_release': {'stdout': {'exclusive_read': True}}}
        main = 'Godot Engine v4.7\nLoading resource: res://assets/scenes/main_menu/opening_background.tscn\n'
        self.assertTrue(all(checks(record, {'stdout': main, 'stderr': '', 'engine': main}).values()))
        for field in ('forced_termination', 'bounded_timeout', 'preserved_unsaved_or_unknown_process'):
            bad = dict(record, **{field: True})
            self.assertFalse(all(checks(bad, {'stdout': main, 'engine': main}).values()))
        self.assertFalse(all(checks(record, {'stdout': 'Godot Engine v4.7'}).values()))
        self.assertFalse(all(checks(dict(record, exit_code=0xc0000005), {'stdout': main}).values()))
        self.assertFalse(all(checks(record, {'stdout': main, 'stderr': '',
            'engine': 'ERROR: Could not load GDExtension library'}).values()))
        self.assertFalse(all(checks(record, {'stdout': main,
            'engine': 'GDExtension library not found: old.dll'}).values()))


from pathlib import Path
import tempfile
from unittest.mock import patch


class StartupAdapterTests(StartupIdentityTests):
    def test_single_case_reuses_runner_without_auxiliary_script_and_never_retries(self):
        adapter = getattr(runtime, 'ClientStartupRunner', None)
        self.assertTrue(callable(adapter), 'G05 explicit-manifest runner missing')
        base = Path('E:/Caches/Hermes/cache/scratch')
        with tempfile.TemporaryDirectory(dir=base, prefix='g05-unit-') as temporary:
            document = self.document()
            package = Path(temporary) / 'package'; package.mkdir()
            source = Path(temporary) / 'source'; source.mkdir()
            document['source'] = str(source)
            document['roles']['client']['package'] = str(package)
            manifest = Path(temporary) / 'manifest.json'
            import json
            manifest.write_text(json.dumps(document), encoding='utf-8')
            current = {'source_files': document['source_files'],
                       'source_fingerprint': document['source_fingerprint']}
            root = Path(temporary) / 'runtime'
            with patch('tools.release.round56_three_role_freeze.current_inventory', return_value=current), \
                 patch('tools.release.round56_three_role_freeze.validate_artifact', return_value={}):
                runner = adapter(root, manifest, runtime.sha(manifest), old_artifact=True)
                command = runner.command('client', ['--quit-after', '180'])
                self.assertEqual(command[0], str(package / 'FateDomination.exe'))
                self.assertIn('--headless', command)
                self.assertNotIn('--main-pack', command)
                self.assertEqual(runner.identity['pck'], 'FateDomination.pck')
                for forbidden in ('--script', '--path', '--scene', '--server-gateway', '--server-room-worker'):
                    self.assertNotIn(forbidden, command)
                with self.assertRaises(ValueError): runner.command('server', [])
                with self.assertRaises((ValueError, FileExistsError)):
                    adapter(root, manifest, runtime.sha(manifest), old_artifact=True)
                with self.assertRaises(ValueError):
                    adapter(Path(temporary) / 'wrong-sha', manifest, 'e' * 64, old_artifact=True)
                # Saved evidence root must never be inside a read-only artifact package.
                with self.assertRaises(ValueError):
                    adapter(package / 'unsafe-runtime', manifest, runtime.sha(manifest), old_artifact=True)


class StartupReceiptTests(StartupIdentityTests):
    def test_receipt_consumer_rejects_old_for_current_and_changed_logs_or_scope(self):
        validate = getattr(runtime, 'validate_client_startup_receipt', None)
        self.assertTrue(callable(validate), 'G05 caller receipt validator missing')
        base = Path('E:/Caches/Hermes/cache/scratch')
        with tempfile.TemporaryDirectory(dir=base, prefix='g05-receipt-unit-') as temporary:
            import json
            document = self.document()
            document['source'] = str(Path(temporary) / 'source')
            document['roles']['client']['package'] = str(Path(temporary) / 'package')
            manifest = Path(temporary) / 'manifest.json'
            manifest.write_text(json.dumps(document), encoding='utf-8')
            root = Path(temporary) / 'runtime'
            runner = runtime.ClientStartupRunner(root, manifest, runtime.sha(manifest), old_artifact=True)
            main = ("Godot Engine v4.7\n"
                    "Loading resource: res://.godot/exported/99/export-abc-opening_background.scn\n"
                    "Completed load for: 'res://assets/scenes/main_menu/opening_background.tscn' "
                    "remapped 'res://.godot/exported/99/export-abc-opening_background.scn' at thread -1\n")
            logs = root / 'logs'; logs.mkdir()
            evidence = {}
            for stream, text in [('stdout', main), ('stderr', ''), ('engine', main)]:
                path = logs / ('client-startup.' + stream + '.log')
                path.write_text(text, encoding='utf-8')
                evidence[stream] = {'path': path.as_posix(), 'sha256': runtime.sha(path)}
            record = {'label': 'client-startup', 'role': 'client', 'pid': 1,
                'exit_code': 0, 'exited': True, 'active_owned_processes': 0,
                'job_attached_before_resume': True, 'timeout_seconds': 180,
                'log_resource_release': {v['path']: {'exclusive_read': True} for v in evidence.values()},
                'command': runner.command('client', ['--verbose', '--fixed-fps', '60', '--quit-after', '180',
                    '--log-file', str(logs / 'client-startup.engine.log')]),
                'env_root': (root / 'users/client-startup/appdata').as_posix()}
            runner.state['runs'] = [record]
            runner.environment('client-startup')
            runner.state['source_bound_run'] = {
                'artifact_manifest_sha256': runtime.sha(manifest), **runner.identity,
                'native_files': document['roles']['client'].get('native_files', {}),
                'pid': 1, 'active_owned_processes': 0}
            for suffix in ('before', 'after'):
                runner.state.setdefault('package_verifications', {})['client-startup-' + suffix] = {
                    'exact_client_package_verified': True, 'manifest_sha256': runtime.sha(manifest), **runner.identity}
                runner.state['source_observations']['client-startup-' + suffix] = {
                    'frozen_source_fingerprint': runner.identity['source_fingerprint'],
                    'current_source_fingerprint': runner.identity['source_fingerprint'],
                    'matches_artifact': True, 'differences': {'added': [], 'removed': [], 'changed': {}}}
            checks = runtime.startup_checks(record, {'stdout': main, 'stderr': '', 'engine': main})
            checks.update(package_verified_before_and_after=True,
                          source_identity_recorded_before_and_after=True,
                          runner_completed_without_exception=True)
            runner.state['stages']['client-startup'] = {'status': 'PASS', 'exit_code': 0, 'checks': checks,
                                                       'logs': evidence, 'first_cause': None}
            runner.state['exit_code'] = 0
            with patch('tools.release.round56_three_role_freeze.validate_artifact', return_value={}):
                self.assertFalse(validate(runner.state, manifest, runtime.sha(manifest))['eligible_for_current_candidate'])
                with self.assertRaises(ValueError): validate(runner.state, manifest, runtime.sha(manifest), require_current=True)
                current = copy.deepcopy(runner.state); current['old_artifact'] = False
                self.assertTrue(validate(current, manifest, runtime.sha(manifest), require_current=True)['eligible_for_current_candidate'])
                for mutate in (
                    lambda r: r.update(nonfinal=False),
                    lambda r: r['stages'].update(save={'status': 'PASS'}),
                    lambda r: r['runs'][0].update(forced_termination=True),
                    lambda r: r['runs'][0]['command'].extend(['--script', 'fake.gd']),
                    lambda r: r['source_bound_run'].update(active_owned_processes=1),
                    lambda r: r['source_bound_run'].update(exe_sha256='e' * 64),
                    lambda r: r['source_bound_run'].update(pck_sha256='e' * 64),
                    lambda r: r['isolated_environment'].update(TMP='C:/outside'),
                    lambda r: r['source_observations']['client-startup-after'].update(matches_artifact=False),
                    lambda r: r['runs'][0].update(exit_code=1),
                    lambda r: r['runs'][0].pop('exit_code'),
                    lambda r: r['runs'][0].pop('exited'),
                    lambda r: r.update(runs=[]),
                    lambda r: r['runs'][0].update(active_owned_processes=1),
                    lambda r: r['source_bound_run'].update(native_files={'old.dll': 'e' * 64}),
                    lambda r: r['stages']['client-startup'].update(status='FAIL'),
                    lambda r: r['stages']['client-startup'].update(exit_code=1),
                ):
                    bad = copy.deepcopy(current); mutate(bad)
                    with self.assertRaises(ValueError): validate(bad, manifest, runtime.sha(manifest), require_current=True)
                with self.assertRaisesRegex(ValueError, 'MANIFEST_HASH_MISMATCH'):
                    validate(current, manifest, 'e' * 64)
                bad = copy.deepcopy(current)
                bad['stages']['client-startup']['logs']['engine']['sha256'] = 'e' * 64
                with self.assertRaisesRegex(ValueError, 'LOG_HASH_MISMATCH'):
                    validate(bad, manifest, runtime.sha(manifest))
                # Keep the remapped Loading line but remove Completed: no main proof.
                missing_completed = ''.join(main.splitlines(keepends=True)[:-1])
                # Refresh fixture log hashes to prove content rejection, not just SHA drift.
                for case, text in (
                    ('remapped_completed_line_missing', missing_completed),
                    ('banner_only', 'Godot Engine v4.7\n'),
                    ('script_error', main + 'SCRIPT ERROR: broken script\n'),
                    ('dll_error', main + 'DLL old.dll could not load\n'),
                ):
                    with self.subTest(case=case):
                        bad = copy.deepcopy(current)
                        for stream in ('stdout', 'engine'):
                            path = logs / ('client-startup.' + stream + '.log')
                            path.write_text(text, encoding='utf-8')
                            bad['stages']['client-startup']['logs'][stream]['sha256'] = runtime.sha(path)
                        with self.assertRaisesRegex(ValueError, 'CHECK_READBACK_MISMATCH'):
                            validate(bad, manifest, runtime.sha(manifest))
                for stream in ('stdout', 'engine'):
                    (logs / ('client-startup.' + stream + '.log')).write_text(main, encoding='utf-8')
                (logs / 'client-startup.engine.log').write_text(main + 'ERROR: old DLL', encoding='utf-8')
                with self.assertRaises(ValueError): validate(current, manifest, runtime.sha(manifest))
            # Exercise the real artifact verifier: plausible checks cannot bypass it.
            (logs / 'client-startup.engine.log').write_text(main, encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'PHYSICAL_E_PACKAGE_REQUIRED'):
                validate(current, manifest, runtime.sha(manifest))
            package = Path(document['roles']['client']['package']); package.mkdir()
            for name in document['roles']['client']['package_files']:
                (package / name).write_bytes(b'UNIT_FIXTURE_NOT_AN_EXPORTED_ARTIFACT')
            with self.assertRaisesRegex(ValueError, 'PACKAGE_HASH_DRIFT'):
                validate(current, manifest, runtime.sha(manifest))


class StartupPublicApiTests(StartupIdentityTests):
    def test_environment_and_failed_attempt_keep_source_bound_receipt(self):
        base = Path('E:/Caches/Hermes/cache/scratch')
        with tempfile.TemporaryDirectory(dir=base, prefix='g05-bound-unit-') as temporary:
            import json
            document = self.document()
            document['source'] = str(Path(temporary) / 'source')
            document['roles']['client']['package'] = str(Path(temporary) / 'package')
            document['roles']['client']['native_files'] = {'old.dll': 'd' * 64}
            manifest = Path(temporary) / 'manifest.json'
            manifest.write_text(json.dumps(document), encoding='utf-8')
            runner = runtime.ClientStartupRunner(Path(temporary) / 'runtime', manifest,
                                                  runtime.sha(manifest), old_artifact=True)
            env = runner.environment('client-startup')
            self.assertEqual(runner.state.get('isolated_environment'), {
                key: env[key] for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR')})
            with patch.object(runner, 'start', side_effect=ValueError('preflight refusal')):
                with self.assertRaises(RuntimeError): runner.client_startup()
            bound = runner.state['source_bound_run']
            self.assertEqual(bound['artifact_manifest_sha256'], runtime.sha(manifest))
            self.assertEqual(bound['pck_sha256'], 'c' * 64)
            self.assertEqual(bound['native_files'], {'old.dll': 'd' * 64})
            self.assertIsNone(bound['active_owned_processes'])
            self.assertEqual(runner.state['stages']['client-startup']['status'], 'FAIL')

    def test_public_api_persists_failure_receipt_without_retry(self):
        run = getattr(runtime, 'run_client_startup', None)
        self.assertTrue(callable(run), 'G05 stable run_client_startup caller API missing')
        with patch.object(runtime, 'ClientStartupRunner') as runner_type:
            runner = runner_type.return_value
            runner.state = {'stages': {'client-startup': {'status': 'FAIL'}}, 'runs': []}
            runner.client_startup.side_effect = RuntimeError('first native AV; no continuation')
            result = run('root', 'manifest', 'a' * 64, old_artifact=True)
            self.assertIs(result, runner.state)
            self.assertEqual(result['exit_code'], 1)
            self.assertEqual(result['failures'][0]['first_cause'], 'first native AV; no continuation')
            runner.client_startup.assert_called_once_with()
            runner.save.assert_called_once_with()


if __name__ == '__main__':
    unittest.main()
