"""FAKEJOBS only: scheduler policy, not Godot or performance evidence."""
import importlib.util
from pathlib import Path
import sys
import unittest

PATH = Path(__file__).with_name('regression_parallel_scheduler.py')


def module():
    spec = importlib.util.spec_from_file_location('parallel_scheduler_under_test', PATH)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


class FakeJob:
    """Explicit fake completion handle, no process/runtime correctness claim."""
    def __init__(self, name, active, peaks, ticks=2, passed=True):
        self.name, self.active, self.peaks = name, active, peaks
        self.ticks, self.passed = ticks, passed
        active.add(name)
        peaks.append(len(active))
        self.cancelled = False

    def poll(self):
        self.ticks -= 1
        return self.ticks <= 0

    def cancel(self):
        self.cancelled = True
        self.ticks = 0

    def finish(self):
        self.active.remove(self.name)
        return {'passed': self.passed and not self.cancelled, 'job0': True,
                'cancelled': self.cancelled}


class SchedulerTests(unittest.TestCase):
    def test_fakejobs_default_serial_and_explicit_parallel(self):
        self.assertTrue(PATH.is_file(), 'bounded scheduler missing')
        s = module()
        for jobs, peak in [(1, 1), (2, 2), (4, 4)]:
            active, peaks = set(), []
            tasks = [s.Task(str(i), s.Resources(1, 10, 10), known_parallel=True) for i in range(4)]
            report = s.run(tasks, lambda task: FakeJob(task.key, active, peaks),
                           budget=s.Resources(4, 40, 40), jobs=jobs, interval=0)
            self.assertTrue(report['passed'])
            self.assertEqual(max(peaks), peak)
            self.assertEqual(report['expected'], report['executed'])
            self.assertEqual(report['notrun'], [])
            self.assertEqual([row['key'] for row in report['results']], report['expected'])
            self.assertFalse(active)

    def test_fakejobs_unknown_capability_and_key_barriers(self):
        s = module()
        for middle in [s.Task('barrier', s.Resources(1, 10, 10)),
                       s.Task('barrier', s.Resources(1, 10, 10), True, exclusive=True)]:
            active, peaks, overlaps = set(), [], []
            tasks = [s.Task('a', s.Resources(1, 10, 10), True), middle,
                     s.Task('c', s.Resources(1, 10, 10), True)]
            def launch(task):
                overlaps.append((task.key, set(active)))
                return FakeJob(task.key, active, peaks)
            report = s.run(tasks, launch, budget=s.Resources(3, 30, 30), jobs=4, interval=0)
            self.assertTrue(report['passed'])
            self.assertTrue(all(not seen for _, seen in overlaps))
        for keys, expected_peak in [([{'port'}, {'port'}], 1), ([{'x'}, {'y'}], 2)]:
            active, peaks = set(), []
            tasks = [s.Task(str(i), s.Resources(1, 10, 10), True, frozenset(k)) for i, k in enumerate(keys)]
            report = s.run(tasks, lambda t: FakeJob(t.key, active, peaks),
                           budget=s.Resources(4, 40, 40), jobs=2, interval=0)
            self.assertTrue(report['passed'])
            self.assertEqual(max(peaks), expected_peak)

    def test_fakejobs_global_resource_admission(self):
        s = module()
        for budget in [s.Resources(1, 40, 40), s.Resources(4, 10, 40), s.Resources(4, 40, 10)]:
            active, peaks = set(), []
            tasks = [s.Task(str(i), s.Resources(1, 10, 10), True) for i in range(3)]
            self.assertTrue(s.run(tasks, lambda t: FakeJob(t.key, active, peaks),
                                 budget=budget, jobs=4, interval=0)['passed'])
            self.assertEqual(max(peaks), 1)

    def test_fakejobs_collect_failures_but_stop_unproven_job0(self):
        s = module()
        for unsafe in [False, True]:
            active, peaks = set(), []
            tasks = [s.Task(str(i), s.Resources(1, 10, 10), True) for i in range(3)]
            class Failed(FakeJob):
                def finish(self):
                    return super().finish() | {'passed': False, 'job0': not unsafe}
            def launch(t):
                return (Failed if t.key == '0' else FakeJob)(t.key, active, peaks)
            report = s.run(tasks, launch, budget=s.Resources(4, 40, 40), jobs=1, interval=0)
            self.assertFalse(report['passed'])
            self.assertEqual(report['executed'], ['0'] if unsafe else ['0', '1', '2'])
            self.assertEqual(report['notrun'], ['1', '2'] if unsafe else [])

    def test_fakejobs_cancel_no_new_launch_and_balanced_accounting(self):
        s = module()
        active, peaks, handles = set(), [], []
        tasks = [s.Task(str(i), s.Resources(1, 10, 10), True) for i in range(4)]
        def launch(t):
            handle = FakeJob(t.key, active, peaks, ticks=10)
            handles.append(handle)
            return handle
        report = s.run(tasks, launch, budget=s.Resources(4, 40, 40), jobs=2,
                       cancelled=lambda: len(handles) >= 2, interval=0)
        self.assertFalse(report['passed'])
        self.assertEqual(report['stop_reason'], 'user_cancel')
        self.assertEqual(report['executed'], ['0', '1'])
        self.assertEqual(report['notrun'], ['2', '3'])
        self.assertEqual(set(report['expected']), set(report['executed']) | set(report['notrun']))
        self.assertFalse(set(report['executed']) & set(report['notrun']))
        self.assertTrue(all(h.cancelled for h in handles))
        self.assertFalse(active)
    def test_fakejobs_callback_errors_preserve_all_owned_handles(self):
        s = module()
        for error_at in ['monitor', 'poll', 'finish', 'launch']:
            active, peaks, handles = set(), [], []
            tasks = [s.Task(str(i), s.Resources(1, 10, 10), True) for i in range(4)]
            class Broken(FakeJob):
                def poll(self):
                    if error_at == 'poll': raise RuntimeError('poll root cause')
                    return super().poll()
                def finish(self):
                    row = super().finish()
                    if error_at == 'finish': raise RuntimeError('finish root cause')
                    return row
            def launch(t):
                if error_at == 'launch' and t.key == '1': raise RuntimeError('launch root cause')
                handle = Broken(t.key, active, peaks)
                handles.append(handle)
                return handle
            def monitor():
                if error_at == 'monitor' and len(handles) >= 2: raise RuntimeError('monitor root cause')
            report = s.run(tasks, launch, budget=s.Resources(4, 40, 40), jobs=2,
                           monitor=monitor, interval=0)
            self.assertFalse(report['passed'])
            self.assertFalse(active)
            self.assertTrue(report['errors'])
            self.assertEqual(set(report['expected']), set(report['executed']) | set(report['notrun']))

    def test_fakejobs_invalid_plan_and_resource_types_fail_before_launch(self):
        s = module()
        for resources in [(True, 1, 1), (0, 1, 1), (1, 1.5, 1)]:
            with self.assertRaises(ValueError): s.Resources(*resources)
        task = s.Task('same', s.Resources(1, 10, 10), True)
        with self.assertRaises(ValueError):
            s.Task('bad', s.Resources(1, 1, 1), known_parallel='yes')
        with self.assertRaises(ValueError):
            s.Task('bad', s.Resources(1, 1, 1), exclusive_keys={'mutable'})
        for invalid_interval in [-1, float('nan')]:
            with self.assertRaises(ValueError):
                s.run([task], lambda _: self.fail('must not launch'),
                      budget=s.Resources(4, 40, 40), interval=invalid_interval)
        for tasks, budget, jobs in [([task, task], s.Resources(4, 40, 40), 2),
                                     ([task], s.Resources(4, 1, 40), 2),
                                     ([task], s.Resources(4, 40, 40), 3)]:
            with self.assertRaises(ValueError):
                s.run(tasks, lambda _: self.fail('must not launch'), budget=budget, jobs=jobs)
    def test_adapter_entry_exists_without_result_parser_fork(self):
        adapter = Path(__file__).with_name('regression_parallel_smoke.py')
        self.assertTrue(adapter.is_file(), 'isolated process adapter missing')
        text = adapter.read_text(encoding='utf-8')
        self.assertNotIn('def parse_result', text)
        self.assertNotIn('os.chdir(', text)
        self.assertNotIn('os.environ[', text)
    def test_fakejobs_aggregate_monitor_stops_active_and_queued(self):
        s = module()
        active, peaks, handles = set(), [], []
        tasks = [s.Task(str(i), s.Resources(1, 10, 10), True) for i in range(4)]
        def launch(t):
            h = FakeJob(t.key, active, peaks, ticks=10)
            handles.append(h)
            return h
        report = s.run(tasks, launch, budget=s.Resources(4, 40, 40), jobs=2, interval=0,
                       monitor=lambda: 'global_disk_budget' if len(handles) == 2 else None)
        self.assertEqual(report['stop_reason'], 'global_disk_budget')
        self.assertEqual(report['executed'], ['0', '1'])
        self.assertEqual(report['notrun'], ['2', '3'])
        self.assertFalse(active)
        self.assertTrue(report['accounted'])

    def test_real_windows_cancel_owned_descendants_and_isolated_environment(self):
        import os
        if os.name != 'nt': self.skipTest('Windows owned process test')
        approved = os.environ.get('PARALLEL_TEST_ROOT')
        if not approved: self.skipTest('explicit PARALLEL_TEST_ROOT physical E root required')
        import tempfile
        import types
        import json
        import time
        adapter_path = Path(__file__).with_name('regression_parallel_smoke.py')
        sys.path.insert(0, str(adapter_path.parent))
        try:
            spec = importlib.util.spec_from_file_location('process_adapter_test', adapter_path)
            adapter = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(adapter)
            s = sys.modules['regression_parallel_scheduler']
            raw = (Path(__file__).parents[1] / 'run_isolated_godot_test.py').read_bytes()
            generic = types.ModuleType('frozen_cancel_test_generic')
            exec(compile(raw, '<frozen-cancel-test-generic>', 'exec'), generic.__dict__)
            generic.physical_e(approved)
            with tempfile.TemporaryDirectory(dir=approved) as directory:
                root = Path(directory)
                parent_cwd, parent_env = os.getcwd(), os.environ.copy()
                resources = s.Resources(1, 268435456, 10485760)
                tasks = [s.Task(str(i), resources, True) for i in range(4)]
                records, handles = [], []
                started = time.monotonic()
                def launch(task):
                    case = root / task.key
                    case.mkdir()
                    evidence = case / 'evidence'
                    evidence.mkdir()
                    env = os.environ.copy()
                    for field in ('APPDATA', 'LOCALAPPDATA', 'TMP', 'TEMP', 'TMPDIR'):
                        path = case / field
                        path.mkdir()
                        env[field] = str(path)
                    child = ('import os,json,time;from pathlib import Path;'
                             'Path("child.json").write_text(json.dumps({"pid":os.getpid(),'
                             '"cwd":os.getcwd(),"env":{k:os.environ[k] for k in '
                             '["APPDATA","LOCALAPPDATA","TMP","TEMP","TMPDIR"]}}));time.sleep(30)')
                    code = ('import subprocess,sys,time;subprocess.Popen([sys.executable,"-c",'
                            + repr(child) + ']);time.sleep(30)')
                    record = {'label': task.key}
                    records.append(record)
                    handle = adapter.OwnedProcess(generic, [sys.executable, '-c', code], env,
                        case, evidence, resources, 10, record, lambda exit_code: {'passed': exit_code == 0})
                    handles.append(handle)
                    return handle
                def cancel_ready():
                    return len(handles) == 2 and all((root / str(i) / 'child.json').exists() for i in range(2))
                report = s.run(tasks, launch, budget=s.Resources(2, 536870912, 20971520), jobs=2,
                    cancelled=cancel_ready, monitor=lambda: 'fixture_deadline' if time.monotonic() - started > 8 else None,
                    interval=0.01)
                self.assertEqual(report['stop_reason'], 'user_cancel', report)
                self.assertEqual(report['executed'], ['0', '1'])
                self.assertEqual(report['notrun'], ['2', '3'])
                self.assertTrue(all(r['job0'] and not r['passed'] for r in report['results']))
                self.assertTrue(all(r['active_owned_processes'] == 0 and r['log_handles_released'] for r in records))
                for i in range(2):
                    receipt = json.loads((root / str(i) / 'child.json').read_text())
                    self.assertEqual(Path(receipt['cwd']), root / str(i))
                    self.assertTrue(all(Path(value).is_relative_to(root / str(i)) for value in receipt['env'].values()))
                self.assertEqual(os.getcwd(), parent_cwd)
                self.assertEqual(dict(os.environ), parent_env)
                print('REAL_OWNED_CANCEL two roots + descendants Job0; distinct E env; queued=2 notrun')
        finally:
            sys.path.pop(0)
    def test_fixture_partial_runner_stdout_keeps_root_cause_logs(self):
        import os
        import tempfile
        import types
        import json
        sys.path.insert(0, str(Path(__file__).parent))
        try:
            import regression_parallel_smoke as adapter
            raw = (Path(__file__).parents[1] / 'run_isolated_godot_test.py').read_bytes()
            generic = types.ModuleType('frozen_archive_test_generic')
            exec(compile(raw, '<frozen-archive-test-generic>', 'exec'), generic.__dict__)
            with tempfile.TemporaryDirectory(dir=os.environ.get('PARALLEL_TEST_ROOT', os.environ.get('TMPDIR'))) as directory:
                root = Path(directory)
                evidence = root / 'outer-evidence'
                evidence.mkdir()
                inner = root / 'runs' / ('isolated-' + 'a' * 32) / 'evidence'
                inner.mkdir(parents=True)
                raw_log = b'FIXTURE root cause before cancelled final summary\n'
                (inner / 'scene.stderr.log').write_bytes(raw_log)
                (evidence / 'runner.stdout.log').write_bytes(b'partial stdout')
                with self.assertRaises(json.JSONDecodeError):
                    adapter.scene_result(generic, root, evidence, 125)
                self.assertEqual((evidence / ('retained-isolated-' + 'a' * 32) / 'evidence' / 'scene.stderr.log').read_bytes(), raw_log)
        finally:
            sys.path.pop(0)
    def test_fakejobs_final_evidence_is_charged_before_success(self):
        s = module()
        active, peaks, handles = set(), [], []
        def launch(t):
            handle = FakeJob(t.key, active, peaks, ticks=1)
            handles.append(handle)
            return handle
        report = s.run([s.Task('last', s.Resources(1, 10, 10), True)], launch,
                       budget=s.Resources(1, 10, 10), interval=0,
                       monitor=lambda: 'retained_evidence_over_budget' if handles and not active else None)
        self.assertFalse(report['passed'])
        self.assertEqual(report['stop_reason'], 'retained_evidence_over_budget')
        self.assertTrue(report['accounted'])

    def test_fakejobs_finish_failure_still_cancels_its_live_owned_handle(self):
        s = module()
        active, peaks, handles = set(), [], []
        class BrokenFinish(FakeJob):
            def finish(self):
                if not self.cancelled: raise RuntimeError('original finish root cause')
                return super().finish()
        def launch(t):
            handle = BrokenFinish(t.key, active, peaks, ticks=1)
            handles.append(handle)
            return handle
        report = s.run([s.Task('broken', s.Resources(1, 10, 10), True)], launch,
                       budget=s.Resources(1, 10, 10), interval=0)
        self.assertFalse(report['passed'])
        self.assertFalse(active, 'finish raised before ownership cleanup; must cancel this handle too')
        self.assertTrue(handles[0].cancelled)
        self.assertTrue(any('original finish root cause' in e['error'] for e in report['errors']))


if __name__ == '__main__':
    unittest.main()
