"""最小 mock 自测：不启动 Godot、不触碰真实进程。"""
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[3]
TARGET = Path(__file__).with_name("run_server_signal_acceptance.candidate.py")
sys.path.insert(0, str(ROOT / "tests"))
spec = importlib.util.spec_from_file_location("signal_acceptance", TARGET)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FakeKernel:
    def __init__(self, state, code):
        self.state = state
        self.code = code
        self.calls = []

    def WaitForSingleObject(self, handle, timeout):
        self.calls.append(("wait", handle, timeout))
        return self.state

    def GetExitCodeProcess(self, handle, pointer):
        self.calls.append(("exit", handle))
        pointer._obj.value = self.code
        return True


class SignalEvidenceTests(unittest.TestCase):
    def test_v4a_applies_exactly_to_isolated_baseline(self):
        directory = Path(__file__).parent
        source = (directory / "baseline.py.txt").read_text(encoding="utf-8")
        patch_text = (directory / "minimal-signal-evidence.v4a").read_text(encoding="utf-8")
        chunks = patch_text.split("@@\n")[1:]
        position = 0
        for chunk in chunks:
            lines = chunk.splitlines(True)
            lines = [line for line in lines if not line.startswith("*** End Patch")]
            old = "".join(line[1:] for line in lines if line[:1] in (" ", "-"))
            new = "".join(line[1:] for line in lines if line[:1] in (" ", "+"))
            offset = source.index(old, position)
            source = source[:offset] + new + source[offset + len(old):]
            position = offset + len(new)
        self.assertEqual(source, TARGET.read_text(encoding="utf-8"))

    def test_real_handle_records_exit_without_launcher(self):
        kernel = FakeKernel(0, 17)
        evidence = module.observe_windows_process(kernel, 501)
        self.assertEqual(evidence, {"alive": False, "exit_code": 17, "exit_code_observable": True})
        self.assertEqual(kernel.calls, [("wait", 501, 0), ("exit", 501)])

    def test_live_real_handle_has_no_fake_exit_code(self):
        launcher = Mock()
        launcher.poll.return_value = 0
        self.assertEqual(launcher.poll(), 0)
        kernel = FakeKernel(258, 259)
        evidence = module.observe_windows_process(kernel, 502)
        self.assertEqual(evidence, {"alive": True, "exit_code": None, "exit_code_observable": True})

    def test_failed_wait_is_recorded_as_unknown(self):
        evidence = module.observe_windows_process(FakeKernel(0xFFFFFFFF, 0), 503)
        self.assertIsNone(evidence["alive"])
        self.assertIsNone(evidence["exit_code"])
        self.assertIn("error", evidence)

    def test_failed_exit_query_is_recorded_not_fabricated(self):
        kernel = FakeKernel(0, 0)
        kernel.GetExitCodeProcess = Mock(return_value=False)
        evidence = module.observe_windows_process(kernel, 504)
        self.assertFalse(evidence["alive"])
        self.assertIsNone(evidence["exit_code"])
        self.assertFalse(evidence["exit_code_observable"])

    def test_log_assertion_follows_process_evidence_write(self):
        source = TARGET.read_text(encoding="utf-8")
        self.assertLess(source.index('publish(root / "process-evidence.json"'), source.index("verify_shutdown_log((root / \"engine.log\")"))
        self.assertIn('"owned_launcher_pid":server.pid', source)
        self.assertIn('"process_evidence": json.loads((root / "process-evidence.json")', source)

    def test_linux_does_not_use_launcher_exit_as_engine_exit(self):
        source = TARGET.read_text(encoding="utf-8")
        linux_block = source[source.index('else:\n                            workers_evidence = []'):source.index('# 先保存真实 engine/worker 状态')]
        self.assertIn("exit_code = None", linux_block)
        self.assertNotIn("exit_code = server.poll()", linux_block)

    def test_finally_does_not_terminate_engine_or_worker(self):
        source = TARGET.read_text(encoding="utf-8")
        finally_block = source[source.index("        finally:"):source.index("\n\n\nif __name__")]
        self.assertIn('publish(root / "finally-process.json"', finally_block)
        self.assertNotIn("TerminateProcess", finally_block)
        self.assertNotIn("server.terminate", finally_block)
        self.assertNotIn("client.kill", finally_block)
        self.assertIn('"launcher": {"pid": server.pid, "exit_code": server.poll()}', finally_block)


if __name__ == "__main__":
    unittest.main(verbosity=2)
