"""Boundary tests for the reusable isolated runner (no game rule substitutes)."""
import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).parents[1] / 'run_isolated_godot_test.py'

class ResultTests(unittest.TestCase):
    def test_repeated_check_labels_are_not_ids(self):
        spec = importlib.util.spec_from_file_location('check_runner', MODULE)
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        for checks in ['CHECK same true\nCHECK same true', 'CHECK true same\nCHECK true same']:
            self.assertTrue(runner.analyze(checks + '\nRESULT loops checks=2 failures=[]', '', 0)['passed'])
        for checks in ['CHECK 1 same true\nCHECK 1 other true',
                       'CHECK #1 same true\nCHECK #1 other true',
                       'CHECK [1] same true\nCHECK [1] other true',
                       'CHECK true #1 same\nCHECK true #1 other',
                       'CHECK false same\nCHECK true same',
                       'CHECK true same false\nCHECK true same']:
            self.assertFalse(runner.analyze(checks + '\nRESULT loops checks=2 failures=[]', '', 0)['passed'])

    def test_strict_results(self):
        self.assertTrue(MODULE.is_file(), 'isolated runner is not implemented')
        spec = importlib.util.spec_from_file_location('isolated_runner', MODULE)
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        self.assertTrue(runner.analyze('RESULT {"checks":1,"failures":[]}', '', 0)['passed'])
        self.assertTrue(runner.analyze('RESULT refactor_text_golden checks=1 failures=[]', '', 0)['passed'])
        for output in ['RESULT any_suite checks=1 checks=2 failures=[]',
                       'RESULT any_suite checks=true failures=[]',
                       'RESULT any_suite checks=1.5 failures=[]',
                       'RESULT any_suite checks=1 failures=["bad"]',
                       'RESULT any_suite suite="duplicate" checks=1 failures=[]',
                       'RESULT any_suite checks=1 failures=[]\nCHECK bad false',
                       'RESULT any_suite checks=2 failures=[]\nCHECK only true',
                       'RESULT any_suite checks=1 failures=[]\nRESULT checks=1 failures=[]',
                       'RESULT {"ok":true,"command":"status"}']:
            self.assertFalse(runner.analyze(output, '', 0)['passed'], output)
        self.assertFalse(runner.analyze('RESULT gateway checks=1 failures=[]', 'ERROR: expected gateway error', 0)['passed'])
        for output, err, code in [('', '', 0), ('RESULT {"checks":true,"failures":[]}', '', 0),
            ('RESULT {"checks":1,"checks":2,"failures":[]}', '', 0),
            ('RESULT {"checks":1,"failures":[]}', 'SCRIPT ERROR: bad', 0),
            ('RESULT {"checks":1,"failures":[]}', '', 1),
            ('RESULT {"checks":1,"failures":[]}\nRESULT {"checks":1,"failures":[]}', '', 0),
            ('RESULT {"checks":1,"failures":["bad"]}', '', 0),
            ('RESULT {"checks":0,"failures":[]}', '', 0),
            ('RESULT checks=1 failures=[]', '', 2),
            ('RESULT checks=1 failures=[] trailing', '', 0),
            ('RESULT {"checks":1.5,"failures":[]}', '', 0),
            ('RESULT {"checks":1,"failures":[]}', 'CHECK assertion false', 0),
            ('RESULT {"checks":1,"failures":[]}\nCHECK wrong malformed', '', 0),
            ('RESULT {"checks":2,"failures":[]}\nCHECK one true', '', 0)]:
            with self.subTest(output=output, err=err, code=code):
                self.assertFalse(runner.analyze(output, err, code)['passed'])

class SafetyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('runner_boundary', MODULE)
        cls.runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.runner)

    def test_invalid_roots(self):
        with self.assertRaises(self.runner.SafetyError):
            self.runner.physical_e('C:/Users/Administrator')
        with self.assertRaises(self.runner.SafetyError):
            self.runner.contained(MODULE.parent, MODULE.parent)
        with self.assertRaises(self.runner.SafetyError):
            self.runner.contained(MODULE, MODULE.parent / 'tests')

    def test_explicit_budget_and_scene_rejections_before_allocation(self):
        import os
        import types
        import tempfile
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            root = Path(name)
            project, runs = root / 'project', root / 'runs'
            project.mkdir()
            runs.mkdir()
            (project / 'project.godot').write_text('[application]\nconfig/name="Boundary"\n')
            (project / 'test.tscn').write_text('[gd_scene format=3]\n')
            executable = project / 'fake.exe'
            executable.write_bytes(b'not executed')
            defaults = dict(root=str(runs), project=str(project), godot=str(executable),
                scene='res://test.tscn', timeout=1, max_bytes=100000, min_free_bytes=0, freeze=False, include=[])
            for changes in [{'timeout': 0}, {'timeout': float('nan')}, {'max_bytes': 0},
                            {'min_free_bytes': -1}, {'scene': 'res://../outside.tscn'},
                            {'scene': 'test.tscn'}, {'godot': 'C:/Windows/System32/cmd.exe'},
                            {'root': 'C:/Users/Administrator'}]:
                with self.subTest(changes=changes), self.assertRaises(self.runner.SafetyError):
                    self.runner.run(types.SimpleNamespace(**(defaults | changes)))
                self.assertEqual(list(runs.iterdir()), [])

    def test_unprobed_project_override_is_rejected(self):
        import os
        import tempfile
        import types
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            base = Path(name)
            project, runs = base / 'project', base / 'runs'
            project.mkdir()
            runs.mkdir()
            config = project / 'project.godot'
            config.write_text('[application]\nconfig/name="OverrideBoundary"\n')
            (project / 'test.tscn').write_text('[gd_scene format=3]\n')
            (project / 'fake.exe').write_bytes(b'not executed')
            args = types.SimpleNamespace(root=str(runs), project=str(project), godot=str(project / 'fake.exe'),
                scene='res://test.tscn', timeout=1, max_bytes=100000, min_free_bytes=0, freeze=False, include=[])
            for custom in [False, True]:
                if custom:
                    (project / 'override.cfg').unlink()
                    config.write_text('[application]\nconfig/name="OverrideBoundary"\nconfig/project_settings_override="res://custom.cfg"\n')
                else:
                    (project / 'override.cfg').write_text('[application]\nconfig/custom_user_dir_name="outside"\n')
                with self.assertRaisesRegex(self.runner.SafetyError, 'override'):
                    self.runner.run(args)
                self.assertEqual(list(runs.iterdir()), [])

    def test_probe_requires_real_worker_and_readback(self):
        with self.assertRaises(self.runner.SafetyError):
            self.runner.verify_probe('', MODULE.parent, 'token')

    def test_appdata_declaration_cannot_replace_physical_probe(self):
        import json
        import os
        import tempfile
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            generated = Path(name)
            # Synthetic negative input only; real successful probes are exercised below.
            entries = [{'role': role, 'pid': pid, 'path': 'C:/Users/Administrator', 'token': 'declared'}
                       for role, pid in [('main', 1), ('worker', 2)]]
            output = '\n'.join('USER_PROBE ' + json.dumps(x) for x in entries)
            with self.assertRaises(self.runner.SafetyError):
                self.runner.verify_probe(output, generated, 'declared')
            userdata = generated / 'userdata'
            userdata.mkdir()
            for item in entries:
                item['path'] = str(userdata)
            output = '\n'.join('USER_PROBE ' + json.dumps(x) for x in entries)
            with self.assertRaises((self.runner.SafetyError, FileNotFoundError)):
                self.runner.verify_probe(output, generated, 'declared')

    def test_copy_excludes_old_artifacts_and_refuses_traversal(self):
        import os
        import tempfile
        base = Path(os.environ['ISOLATED_TEST_ROOT'])
        with tempfile.TemporaryDirectory(dir=base) as name:
            root = Path(name)
            (root / 'source').mkdir()
            (root / 'source' / 'keep.gd').write_text('extends Node')
            (root / 'source' / 'reports').mkdir()
            (root / 'source' / 'reports' / 'old.gd').write_text('old')
            (root / 'source' / 'old.log').write_text('old')
            files = self.runner.source_files(root, ['source'])
            self.assertEqual(files, [Path('source/keep.gd')])
            for include in ['../outside', 'reports', 'C:/outside']:
                with self.assertRaises(self.runner.SafetyError):
                    self.runner.source_files(root, [include])

    def test_cleanup_requires_ownership_receipt(self):
        import os
        import tempfile
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            owner = Path(name)
            generated = owner / 'generated'
            generated.mkdir()
            save = generated / 'formal-save.txt'
            save.write_text('unowned')
            with self.assertRaises(self.runner.SafetyError):
                self.runner.delete_owned(generated, owner)
            self.assertEqual(save.read_text(), 'unowned')

    def test_junction_cleanup_fails_closed(self):
        import os
        import subprocess
        import tempfile
        if os.name != 'nt':
            self.skipTest('Windows junction')
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            root = Path(name)
            target = root / 'formal-save'
            target.mkdir()
            sentinel = target / 'save.txt'
            sentinel.write_text('do not delete')
            generated = root / 'generated'
            generated.mkdir()
            link = generated / 'alias'
            result = subprocess.run(['cmd.exe', '/c', 'mklink', '/J', str(link), str(target)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            try:
                with self.assertRaises(self.runner.SafetyError):
                    self.runner.delete_owned(generated, root)
                self.assertEqual(sentinel.read_text(), 'do not delete')
                self.assertTrue(generated.exists())
            finally:
                os.rmdir(link)  # remove only our junction itself, never its target

    def test_owned_job_lives_until_descendant_exit(self):
        import os
        import sys
        import tempfile
        if os.name != 'nt':
            self.skipTest('Windows ownership job')
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            root = Path(name)
            generated = root / 'generated'
            evidence = root / 'evidence'
            generated.mkdir()
            evidence.mkdir()
            records = []
            command = [sys.executable, '-c', 'import subprocess,sys; subprocess.Popen([sys.executable,"-c","import time;time.sleep(30)"])']
            with self.assertRaises(self.runner.SafetyError):
                self.runner.execute(command, os.environ.copy(), generated, evidence, 'child',
                    {'seconds': 0.5, 'bytes': 1000000, 'min_free': 0}, records)
            self.assertTrue(records[0]['exited'])
            self.assertEqual(records[0]['active_owned_processes'], 0)

    def test_owned_job_waits_for_natural_descendant_exit(self):
        import os
        import sys
        import tempfile
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            root = Path(name)
            generated, evidence = root / 'generated', root / 'evidence'
            generated.mkdir()
            evidence.mkdir()
            records = []
            child = 'import time;from pathlib import Path;time.sleep(0.7);Path("natural.txt").write_text("child completed")'
            command = [sys.executable, '-c', 'import subprocess,sys;subprocess.Popen([sys.executable,"-c",' + repr(child) + '])']
            _, _, code = self.runner.execute(command, os.environ.copy(), generated, evidence, 'natural',
                {'seconds': 10, 'bytes': 1000000, 'min_free': 0}, records)
            self.assertEqual(code, 0)
            self.assertEqual((generated / 'natural.txt').read_text(), 'child completed')
            self.assertIsNone(records[0]['budget_failure'])
            self.assertEqual(records[0]['active_owned_processes'], 0)
            self.assertTrue(records[0]['exited'])
            self.assertTrue(records[0]['log_handles_released'])

    def test_monitored_free_space_budget(self):
        import os
        import sys
        import shutil
        import tempfile
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            root = Path(name)
            generated, evidence = root / 'generated', root / 'evidence'
            generated.mkdir()
            evidence.mkdir()
            records = []
            with self.assertRaisesRegex(self.runner.SafetyError, 'free_space_budget'):
                self.runner.execute([sys.executable, '-c', 'import time;time.sleep(5)'], os.environ.copy(), generated, evidence, 'space',
                    {'seconds': 10, 'bytes': 1000000, 'min_free': shutil.disk_usage(root).total + 1}, records)
            self.assertTrue(records[0]['exited'])
            self.assertEqual(records[0]['active_owned_processes'], 0)

    def test_cleanup_preserves_siblings_and_refuses_unexited_owner(self):
        import os
        import json
        import uuid
        import tempfile
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            base = Path(name)
            token = uuid.uuid4().hex
            owner = base / ('isolated-' + token)
            generated = owner / 'generated'
            generated.mkdir(parents=True)
            sentinel = base / 'formal.txt'
            sentinel.write_text('preserved')
            (owner / 'evidence').mkdir()
            receipt = {'run_id': token, 'generated': str(generated), 'processes': [{'exited': False, 'active_owned_processes': 1}]}
            manifest = owner / 'manifest.json'
            manifest.write_text(json.dumps(receipt))
            with self.assertRaisesRegex(self.runner.SafetyError, 'exit not proven'):
                self.runner.delete_owned(generated, owner)
            self.assertTrue(generated.exists())
            receipt['processes'] = [{'exited': True, 'active_owned_processes': 0}]
            manifest.write_text(json.dumps(receipt))
            self.runner.delete_owned(generated, owner)
            self.assertFalse(generated.exists())
            self.assertEqual(sentinel.read_text(), 'preserved')
            self.assertTrue(manifest.is_file())
            self.assertTrue((owner / 'evidence').is_dir())

    def test_job_close_terminates_only_owned_root(self):
        import subprocess
        import sys
        import os
        if os.name != 'nt':
            self.skipTest('Windows ownership job')
        job = self.runner.OwnedJob()
        process = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(30)'], creationflags=4)
        try:
            job.attach_resume(process)
            job.close()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.fail('closing ownership job did not terminate root')
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)

    def test_monitored_byte_budget(self):
        import os
        import sys
        import tempfile
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            root = Path(name)
            generated, evidence = root / 'generated', root / 'evidence'
            generated.mkdir()
            evidence.mkdir()
            records = []
            command = [sys.executable, '-c', 'from pathlib import Path; import time; Path("large").write_bytes(b"x"*200000);time.sleep(5)']
            with self.assertRaisesRegex(self.runner.SafetyError, 'byte_budget'):
                self.runner.execute(command, os.environ.copy(), generated, evidence, 'bytes',
                    {'seconds': 10, 'bytes': 100000, 'min_free': 0}, records)
            self.assertTrue(records[0]['exited'])

    def test_real_godot_scene_freeze_and_failure(self):
        import os
        import json
        import subprocess
        import sys
        import tempfile
        executable = os.environ.get('ISOLATED_GODOT')
        if not executable:
            self.skipTest('set ISOLATED_GODOT to explicit approved E executable')
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            base = Path(name)
            project, runs = base / 'project', base / 'runs'
            project.mkdir()
            runs.mkdir()
            (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="IsolationFixture"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="IsolationFixture"\n[threading]\nworker_pool/max_threads=20\n')
            (project / 'small.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://small.gd" id="1"]\n[node name="Small" type="Node"]\nscript = ExtResource("1")\n')
            script = 'extends Node\nfunc _ready():\n var f = FileAccess.open("user://owned-small.txt", FileAccess.WRITE)\n f.store_string("actual Godot")\n f.close()\n print("CHECK actual_write ", FileAccess.get_file_as_string("user://owned-small.txt") == "actual Godot")\n print("CHECK thread_config ", ProjectSettings.get_setting("threading/worker_pool/max_threads") == 20)\n print(\'RESULT refactor_text_golden checks=2 failures=[]\')\n get_tree().quit()\n'
            (project / 'small.gd').write_text(script)
            (project / 'test').mkdir()
            (project / 'test' / 'old.bin').write_bytes(b'old product')
            command = [sys.executable, '-B', str(MODULE), '--project', str(project), '--scene', 'res://small.tscn',
                       '--root', str(runs), '--godot', executable, '--timeout', '30', '--max-bytes', '10000000', '--min-free-bytes', '0']
            for freeze, fail in [(True, False), (False, False), (True, True), (True, 'missing_dependency')]:
                with self.subTest(freeze=freeze, fail=fail):
                    (project / 'small.gd').write_text(script.replace('failures=[]', 'failures=["deliberate"]') if fail is True else script)
                    cmd = command + (['--freeze'] if freeze else []) + (['--include', 'small.gd'] if freeze and fail != 'missing_dependency' else [])
                    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
                    summary = json.loads(result.stdout)
                    manifest = json.loads(Path(summary['manifest']).read_text(encoding='utf-8'))
                    # Keep evidence even when the assertion detects a RED regression.
                    archive = Path(os.environ['ISOLATED_TEST_ROOT']) / ('verification-' + manifest['run_id'])
                    import shutil
                    shutil.copytree(Path(summary['manifest']).parent, archive)
                    print('VERIFIED_MANIFEST', archive / 'manifest.json')
                    self.assertEqual(result.returncode, 1 if fail else 0, result.stdout + result.stderr)
                    self.assertEqual(manifest['passed'], not fail)
                    self.assertEqual(manifest['cleanup'], 'generated_removed')
                    self.assertFalse((Path(summary['manifest']).parent / 'generated').exists())
                    self.assertEqual(len(manifest['user_probes']), 2)
                    self.assertTrue(all(x.get('worker_pool_max_threads') == 20 for x in manifest['user_probes']))
                    self.assertTrue(all(x['active_owned_processes'] == 0 for x in manifest['processes']))
                    if fail == 'missing_dependency':
                        self.assertIn('missing frozen scene dependencies', manifest.get('error', ''))
                        self.assertIn('small.gd', manifest['error'])
                        self.assertIn('--include', manifest['error'])
                    if freeze:
                        self.assertEqual({x['path'] for x in manifest['source_files']}, {'project.godot', 'small.tscn'} | ({'small.gd'} if fail != 'missing_dependency' else set()))
                    if fail:
                        self.assertTrue((Path(summary['manifest']).parent / 'evidence' / 'failure').is_dir())
                        self.assertTrue((Path(summary['manifest']).parent / 'evidence' / 'failure' / 'target' / 'small.tscn').is_file())
                    self.assertEqual((project / 'test' / 'old.bin').read_bytes(), b'old product')


class FilesystemMonitorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('filesystem_microbench',
            MODULE.parent / 'diagnostics/filesystem_monitor_microbench.py')
        cls.bench = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.bench)
        cls.runner = cls.bench.runner

    def test_no_links_one_metadata_query_per_ancestor(self):
        import os
        import tempfile
        with tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT']) as name:
            leaf = Path(name) / 'one' / 'two' / 'file'
            leaf.parent.mkdir(parents=True)
            leaf.write_bytes(b'fixture')
            with self.bench.metadata_calls() as counts:
                self.assertEqual(self.runner.no_links(leaf), leaf)
            self.assertEqual(sum(counts.values()), len((leaf, *leaf.parents)))
            self.assertEqual(counts['stat_follow'], 0)

    def temporary_tree(self):
        import os
        import tempfile
        return tempfile.TemporaryDirectory(dir=os.environ['ISOLATED_TEST_ROOT'])

    def test_ordinary_missing_paths_and_tree_totals_match_legacy(self):
        with self.temporary_tree() as name:
            root = Path(name)
            leaf = root / 'one' / 'two' / 'file'
            leaf.parent.mkdir(parents=True)
            leaf.write_bytes(b'fixture')
            (root / 'other').write_bytes(b'123')
            for path in (root, leaf, leaf.parent / 'missing' / 'leaf'):
                self.assertEqual(self.runner.no_links(path), self.bench.legacy_no_links(path))
            # statwalk must not acquire content handles, even for synthetic files.
            from unittest.mock import patch
            with patch.object(Path, 'open', side_effect=AssertionError('content handle')), \
                 patch.object(Path, 'read_bytes', side_effect=AssertionError('content read')):
                self.assertEqual(self.runner.tree_bytes(root), 10)
                self.assertEqual(self.runner.tree_bytes(root), self.bench.legacy_tree_bytes(root))
            unknown = root / 'unknown' / 'leaf'
            self.assertEqual(self.runner.no_links(unknown), unknown)
            with self.assertRaises(FileNotFoundError):
                self.runner.contained(unknown, root)

    def test_permission_and_unknown_metadata_errors_fail_closed(self):
        from unittest.mock import patch
        with self.temporary_tree() as name:
            root = Path(name)
            leaf = root / 'file'
            leaf.write_bytes(b'preserved')
            original = Path.lstat
            for error in (PermissionError(13, 'denied'), OSError(5, 'unknown IO failure')):
                for function in (self.runner.no_links, self.bench.legacy_no_links):
                    def failed(path, original=original):
                        if path == leaf:
                            raise error
                        return original(path)
                    with patch.object(Path, 'lstat', failed), self.assertRaises(type(error)):
                        function(leaf)
                with patch.object(Path, 'lstat', failed):
                    with self.assertRaises(type(error)):
                        self.runner.tree_bytes(root)
                    with self.assertRaises(type(error)):
                        self.runner.delete_owned(root, root.parent)
                self.assertEqual(leaf.read_bytes(), b'preserved')
            with self.assertRaises((ValueError, OSError)):
                self.runner.no_links(str(root / 'invalid') + '\x00')

    def test_actual_rename_between_path_observation_and_lstat(self):
        import os
        import threading
        from unittest.mock import patch
        with self.temporary_tree() as name:
            root = Path(name)
            for function in (self.runner.no_links, self.bench.legacy_no_links):
                leaf, renamed = root / 'file', root / 'renamed'
                leaf.write_bytes(b'fixture')
                requested, completed = threading.Event(), threading.Event()
                errors = []
                def rename():
                    try:
                        if not requested.wait(2):
                            raise AssertionError('rename not requested')
                        os.replace(leaf, renamed)
                    except Exception as exc:
                        errors.append(exc)
                    finally:
                        completed.set()
                original = Path.lstat
                def interleaved(path):
                    if path == leaf:
                        requested.set()
                        if not completed.wait(2):
                            raise AssertionError('rename did not finish')
                    return original(path)
                thread = threading.Thread(target=rename)
                thread.start()
                try:
                    with patch.object(Path, 'lstat', interleaved):
                        self.assertEqual(function(leaf), leaf)
                finally:
                    requested.set()
                    thread.join(3)
                self.assertFalse(thread.is_alive())
                self.assertEqual(errors, [])
                self.assertFalse(leaf.exists())
                self.assertEqual(renamed.read_bytes(), b'fixture')
                renamed.unlink()

    def test_tree_stat_missing_after_validation_remains_normal(self):
        import os
        from unittest.mock import patch
        with self.temporary_tree() as name:
            root = Path(name)
            for function in (self.runner.tree_bytes, self.bench.legacy_tree_bytes):
                leaf, renamed = root / 'file', root / 'renamed'
                leaf.write_bytes(b'fixture')
                original = os.stat
                def disappearing(path, *args, **kwargs):
                    if Path(path) == leaf and kwargs.get('follow_symlinks', True):
                        os.replace(leaf, renamed)
                    return original(path, *args, **kwargs)
                with patch('os.stat', disappearing):
                    self.assertEqual(function(root), 0)
                self.assertEqual(renamed.read_bytes(), b'fixture')
                renamed.unlink()

    def test_non_symlink_reparse_attribute_is_rejected(self):
        import stat
        import types
        from unittest.mock import patch
        with self.temporary_tree() as name:
            root = Path(name)
            original = Path.lstat
            def reparse(path):
                if path == root:
                    return types.SimpleNamespace(st_mode=stat.S_IFDIR, st_file_attributes=0x400)
                return original(path)
            with patch.object(Path, 'lstat', reparse):
                for function in (self.runner.no_links, self.bench.legacy_no_links):
                    with self.assertRaises(self.runner.SafetyError):
                        function(root / 'missing' / 'leaf')

    def test_real_junction_ancestor_missing_leaf_and_tree_rejection(self):
        import os
        import subprocess
        if os.name != 'nt':
            self.skipTest('Windows junction only')
        with self.temporary_tree() as name:
            root = Path(name)
            target, scan = root / 'target', root / 'scan'
            target.mkdir()
            scan.mkdir()
            sentinel = target / 'sentinel'
            sentinel.write_bytes(b'preserved')
            link = scan / 'junction'
            result = subprocess.run(['cmd.exe', '/c', 'mklink', '/J', str(link), str(target)], capture_output=True)
            if result.returncode:
                self.skipTest('junction creation denied/unavailable: ' + repr(result.stderr))
            try:
                for path in (link, link / 'sentinel', link / 'missing' / 'leaf'):
                    for function in (self.runner.no_links, self.bench.legacy_no_links):
                        with self.assertRaises(self.runner.SafetyError):
                            function(path)
                for function in (self.runner.tree_bytes, self.bench.legacy_tree_bytes):
                    with self.assertRaises(self.runner.SafetyError):
                        function(scan)
                with self.assertRaises(self.runner.SafetyError):
                    self.runner.delete_owned(scan, root)
                self.assertTrue(scan.exists())
                self.assertEqual(sentinel.read_bytes(), b'preserved')
            finally:
                os.rmdir(link)  # only this exact link, never follow into target

    def test_real_symlink_and_dangling_symlink_rejected(self):
        import os
        with self.temporary_tree() as name:
            root = Path(name)
            target = root / 'target'
            target.mkdir()
            link = root / 'symlink'
            try:
                os.symlink(target, link, target_is_directory=True)
            except OSError as exc:
                self.skipTest('symlink privilege unavailable: ' + str(exc))
            try:
                for path in (link, link / 'missing' / 'leaf'):
                    for function in (self.runner.no_links, self.bench.legacy_no_links):
                        with self.assertRaises(self.runner.SafetyError):
                            function(path)
                target.rmdir()  # now dangling: exists=False must not hide it
                for function in (self.runner.no_links, self.bench.legacy_no_links):
                    with self.assertRaises(self.runner.SafetyError):
                        function(link)
            finally:
                link.unlink()


if __name__ == '__main__':
    unittest.main()
