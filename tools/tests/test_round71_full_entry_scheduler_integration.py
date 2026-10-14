"""Contract-only tests for full-entry scheduler wiring; no Godot or timing claim."""
import importlib.util
from pathlib import Path
import unittest

PROJECT = Path(__file__).resolve().parents[2]
ENTRY_PATH = PROJECT / 'tools/tests/test_round29_integrated_evidence.py'


def entry_module():
    spec = importlib.util.spec_from_file_location('round29_entry_scheduler_contract', ENTRY_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FullEntrySchedulerIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.entry = entry_module()

    def test_cli_defaults_serial_and_rejects_implicit_parallel_budget(self):
        serial = self.entry.round71_scheduler_options(1, None, None, None, 8192)
        self.assertEqual(serial['jobs'], 1)
        self.assertEqual(serial['mode'], 'serial_compat')
        with self.assertRaisesRegex(self.entry.runner.SafetyError, 'explicit.*budget'):
            self.entry.round71_scheduler_options(2, None, 1024, 2048, 8192)

    def test_policy_only_declares_proven_short_headless_tasks_parallel(self):
        selection = {'categories': {
            'short_headless': ['net_cards_test', 'net_move_test', 'net_locations_test'],
            'gui_required': ['local_spell_restore_test'],
            'performance': ['validation_pipeline_performance_test'],
            'long_correctness': ['net_server_gateway_restart_test'],
            'native_integration': ['assembly_publish_lifecycle_test'],
            'known_engine_negative': ['gateway_bind_failure_test'],
        }}
        options = self.entry.round71_scheduler_options(2, 4, 4096, 8192, 8192)
        parallel = self.entry.round71_parallel_resource_policy(
            'net_cards_test', 'complete', selection, options, 2)
        self.assertTrue(parallel['known_parallel'])
        self.assertEqual(parallel['exclusive'], False)
        self.assertEqual(parallel['exclusive_keys'], frozenset())
        for name in ('local_spell_restore_test', 'validation_pipeline_performance_test',
                     'net_server_gateway_restart_test', 'assembly_publish_lifecycle_test',
                     'gateway_bind_failure_test', 'unknown_suite'):
            policy = self.entry.round71_parallel_resource_policy(
                name, 'complete', selection, options, 2)
            self.assertFalse(policy['known_parallel'], name)
            self.assertTrue(policy['exclusive'], name)
        prerequisite = self.entry.round71_parallel_resource_policy(
            'net_cards_test', 'prerequisite', selection, options, 2)
        self.assertFalse(prerequisite['known_parallel'])
        self.assertTrue(prerequisite['exclusive'])

    def test_task_plan_has_unique_phase_keys_and_explicit_accounting(self):
        selection = {'categories': {'short_headless': ['net_cards_test', 'net_move_test']}}
        options = self.entry.round71_scheduler_options(2, 4, 4096, 8192, 8192)
        tasks, policies = self.entry.round71_build_scheduler_tasks(
            [('prerequisite', ['net_cards_test']), ('complete', ['net_cards_test', 'net_move_test'])],
            selection, options)
        self.assertEqual([task.key for task in tasks], [
            'prerequisite-net_cards_test', 'complete-net_cards_test', 'complete-net_move_test'])
        self.assertEqual(len({task.key for task in tasks}), len(tasks))
        self.assertFalse(tasks[0].known_parallel)
        self.assertTrue(tasks[1].known_parallel)
        self.assertTrue(all(task.resources.disk <= options['budget'].disk for task in tasks))
        self.assertEqual(policies['complete-net_cards_test']['resource_policy_version'],
                         'round71-caller-resources/v1')

    def test_fake_caller_receipts_are_not_godot_acceptance(self):
        options = self.entry.round71_scheduler_options(1, None, None, None, 100)
        tasks = [self.entry.scheduler.Task(
            'complete-fake', options['budget'], known_parallel=False,
            exclusive=True)]
        handle = self.entry._Round71CompletedHandle(
            {'suite': 'fake', 'passed': True, 'execution_status': 'fake_receipt'}, job0=True)
        report = self.entry.scheduler.run(tasks, lambda _task: handle,
                                          budget=options['budget'], jobs=1, interval=0)
        self.assertTrue(report['passed'])
        self.assertEqual(report['results'][0]['execution_status'], 'fake_receipt')
        self.assertTrue(report['results'][0]['job0'])
        self.assertNotIn('godot', report['results'][0])

    def test_accounting_keeps_scheduler_expected_executed_notrun_results(self):
        report = {
            'expected': ['complete-a', 'complete-b'],
            'executed': ['complete-a'],
            'notrun': ['complete-b'],
            'results': [{'key': 'complete-a', 'passed': False, 'job0': True}],
            'accounted': True,
            'errors': [],
        }
        row = self.entry.round71_record_scheduler_accounting({}, report)
        self.assertEqual(row['scheduler_expected'], report['expected'])
        self.assertEqual(row['scheduler_executed'], report['executed'])
        self.assertEqual(row['scheduler_notrun'], report['notrun'])
        self.assertTrue(row['scheduler_accounted'])
        self.assertEqual(row['scheduler_result_keys'], ['complete-a'])


if __name__ == '__main__':
    unittest.main()
