"""Static inventory contract only; never launches Godot."""
import importlib.util
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
PROJECT = Path(__file__).resolve().parents[2]


class InventoryContract(unittest.TestCase):
    def test_real_selection_inventory_matches_entry_and_parallel_policy(self):
        path = PROJECT / 'tools/generate_regression_plan_inventory.py'
        self.assertTrue(path.is_file(), 'new static inventory adapter is missing')
        spec = importlib.util.spec_from_file_location('inventory_adapter', path)
        adapter = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(adapter)
        entry = adapter.load_entry()
        prior = entry.load(PROJECT / entry.ROUND50_BASE_MANIFEST)
        selection = entry.build_round50_selection(prior, PROJECT, current_approved=True)
        entry.round71_validate_selection(selection)
        rows = adapter.inventory_rows(entry, selection)
        self.assertEqual([r['suite'] for r in rows], selection['names'])
        for row in rows:
            name = row['suite']
            category = next(k for k, group in selection['categories'].items() if name in group)
            self.assertEqual(row['category'], category)
            self.assertEqual(row['scene'], 'res://tests/' + name + '.tscn')
            self.assertTrue((PROJECT / row['scene'][6:]).is_file())
            self.assertEqual(row['is_long_suite'], category == 'long_correctness')
            self.assertEqual(row['parallel_allowed'], category == 'short_headless' and name in entry.ROUND71_CALLER_PARALLEL_SAFE)
            self.assertEqual(row['status'], 'planned')
            self.assertEqual(row['execution_status'], 'notrun')
            self.assertFalse(any(k in row for k in ('passed', 'result', 'exit_code')))

    def test_new_plan_path_checks_parent_without_requiring_file(self):
        spec = importlib.util.spec_from_file_location('inventory_adapter', PROJECT / 'tools/generate_regression_plan_inventory.py')
        adapter = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(adapter)
        entry = adapter.load_entry()
        root = Path('E:/scratch')
        path = root / 'nonexistent-static-inventory-path-validation.json'
        self.assertFalse(path.exists())
        self.assertTrue(hasattr(adapter, 'new_plan_path'), 'safe new-file path adapter missing')
        self.assertEqual(adapter.new_plan_path(entry, path, root), path)
        with self.assertRaises(entry.runner.SafetyError):
            adapter.new_plan_path(entry, PROJECT / 'docs' / path.name, root)
    def test_z_static_guard_rejects_all_other_process_commands(self):
        import subprocess
        spec = importlib.util.spec_from_file_location('inventory_adapter', PROJECT / 'tools/generate_regression_plan_inventory.py')
        adapter = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(adapter)
        events = adapter.install_static_guard()
        result = subprocess.run([sys.executable, '-B', '-c', 'import ctypes,json,sys; print(sys.executable)'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(events, [Path(sys.executable).name.lower()])
        with self.assertRaisesRegex(RuntimeError, 'static-only'):
            subprocess.run([sys.executable, '-B', '-c', 'raise SystemExit(99)'], capture_output=True)


if __name__ == '__main__':
    unittest.main()
