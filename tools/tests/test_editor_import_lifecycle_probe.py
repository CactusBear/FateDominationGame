"""Exclusive round40 diagnostic tests; never a release acceptance gate."""
import importlib
import unittest


class LifecycleProbeTest(unittest.TestCase):
    def test_iteration_count_is_not_completion_contract(self):
        probe = importlib.import_module("tools.diagnostics.editor_import_lifecycle_probe")
        self.assertEqual(probe.mode_arguments("iterations", 2), "--quit-after 2")
        self.assertEqual(probe.mode_arguments("import", 2), "--import")
        with self.assertRaises(ValueError):
            probe.mode_arguments("iterations", 0)
        with self.assertRaises(ValueError):
            probe.mode_arguments("unknown", 2)
        result = probe.assess_observation("EXIT pid=1 code=0x00000000 timedout=0\n")
        self.assertFalse(result["completion_contract_proven"])
        self.assertEqual(result["status"], "BLOCKED_NO_PUBLIC_DOC_COMPLETION_CONTRACT")
        # Synthetic unit input: callback ENTRY is not callback completion.
        observed = probe.assess_observation(
            "TRACE rva=0x1792840 watch_rva=0x66dcc10 value=0x1000\n"
            "TRACE rva=0x17aba60 watch_rva=0x66dcc10 value=0x1000\n"
            "EXIT pid=1 code=0x00000000 timedout=0\n"
        )
        self.assertTrue(observed["callback_entry_before_cleanup_observed"])
        self.assertFalse(observed["completion_contract_proven"])

    def test_actual_normal_quit_capture_does_not_prove_doc_completion(self):
        from pathlib import Path
        probe = importlib.import_module("tools.diagnostics.editor_import_lifecycle_probe")
        text = (Path(__file__).parent / "fixtures/round40_editor_fs_quit_capture.txt").read_text(encoding="utf-8")
        result = probe.assess_observation(text)
        self.assertTrue(result["filesystem_completion_observed"])
        self.assertTrue(result["normal_quit_requested"])
        self.assertFalse(result["callback_entry_before_cleanup_observed"])
        self.assertFalse(result["callback_entry_doc_nonnull"])
        self.assertEqual(result["events"]["child_exit_hex"], "0xc0000005")
        self.assertFalse(result["completion_contract_proven"])
        self.assertEqual(result["events"]["second_chance"][0]["pid"], 35120)

    def test_debugger_and_fresh_root_safety(self):
        from pathlib import Path
        probe = importlib.import_module("tools.diagnostics.editor_import_lifecycle_probe")
        source = probe.debugger_source()
        self.assertIn("argc==7 ? argv[6]", source)
        self.assertIn("DEBUG_ONLY_THIS_PROCESS", source)
        self.assertNotIn("DebugActiveProcess(", source)
        self.assertIn("TerminateProcess(pi.hProcess", source)
        self.assertNotIn("--import\";", source)
        with self.assertRaises(ValueError):
            probe.require_fresh_e(Path("C:/Users/Administrator/round40-forbidden"))
        with self.assertRaises(ValueError):
            probe.require_fresh_e(Path(__file__).parent)


if __name__ == "__main__":
    unittest.main()
