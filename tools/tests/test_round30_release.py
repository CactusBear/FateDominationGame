"""G05 候选发行链回归：只读已归档证据，不启动源码 Godot。"""
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RELEASE = ROOT / "tools" / "release"
SCRATCH = Path("E:/Caches/Hermes/cache/scratch/round30-g05-release-runtime")
sys.path.insert(0, str(RELEASE))
import runtime_audit  # noqa: E402


class Round30ReleaseTests(unittest.TestCase):
    def test_runtime_audit_requires_candidate_executable(self):
        with self.assertRaises(ValueError):
            runtime_audit.run_role(SCRATCH / "missing-package", "server", SCRATCH / "missing.json", 1)

    def test_frozen_configs_preserve_explicit_twenty_threads(self):
        for role in ("client", "server"):
            project = SCRATCH / f"{role}-frozen" / "project.godot"
            if not project.is_file():
                self.skipTest("候选冻结目录已回收；使用报告中的冻结哈希")
            text = project.read_text(encoding="utf-8")
            self.assertIn("worker_pool/max_threads=20", text)

    def test_archived_static_audits_have_no_blockers(self):
        for role in ("client", "server"):
            report = SCRATCH / f"{role}-audit.json"
            if not report.is_file():
                self.skipTest("静态审计证据不存在")
            value = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(value["status"], "STATIC_PASS_RUNTIME_PENDING")
            self.assertEqual(value["blockers"], [])
            self.assertEqual(value["data"], {"missing": [], "extra": [], "changed": []})

    def test_server_runtime_is_ready_and_legally_stopped(self):
        report = SCRATCH / "server-runtime-v2.json"
        if not report.is_file():
            self.skipTest("服务端运行证据不存在")
        value = json.loads(report.read_text(encoding="utf-8"))["runtime"]
        self.assertTrue(value["ready"])
        self.assertEqual(value["exit_code"], 0)
        self.assertEqual(value["stop_method"], "ctrl_break_shutdown")
        self.assertIn("SERVER_STOP_COMPLETE", value["lines"])

    def test_signaling_failure_is_not_relabelled_ready(self):
        failure = SCRATCH / "signaling-export.log"
        if not failure.is_file():
            self.skipTest("信令原失败日志不存在")
        text = failure.read_text(encoding="utf-8", errors="replace")
        self.assertIn("MatchPacketFragments", text)


if __name__ == "__main__":
    unittest.main()
