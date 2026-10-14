"""Standalone real Win32 Job lease verification; no Godot, DLL or cleanup wiring."""
import hashlib
import json
import os
import pathlib
import subprocess
import unittest
import uuid

REPO = pathlib.Path(__file__).resolve().parents[2]
CORE = REPO / "addons/fate_server_signals/src/process_tree_owner_core.cpp"
HEADER = CORE.with_suffix(".hpp")
PROBE = pathlib.Path(__file__).with_name("process_tree_owner_core_probe.cpp")


class ProcessTreeOwnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.name != "nt":
            raise unittest.SkipTest("real Windows required")
        cls.root = pathlib.Path("E:/") / ("FateProcessTreeProof-" + uuid.uuid4().hex)
        cls.root.mkdir()
        for p in [cls.root, *cls.root.parents, REPO, *REPO.parents]:
            if p.stat(follow_symlinks=False).st_file_attributes & 0x400:
                raise AssertionError(f"reparse test path: {p}")
        print("EVIDENCE_ROOT=" + str(cls.root), flush=True)
        cls.evidence = []
        cls.addClassCleanup(cls.finish_evidence)
        cls.exe = cls.root / "process_tree_owner_core_probe.exe"
        cls.fault_exe = cls.root / "process_tree_owner_core_fault_probe.exe"
        if not CORE.is_file() or not HEADER.is_file():
            raise AssertionError("WindowsJobLease primitive missing: no exact Job active-zero proof")
        vcvars = pathlib.Path(os.environ.get("FATE_TREE_VCVARS", "D:/VS2022/VC/Auxiliary/Build/vcvars64.bat"))
        if not vcvars.is_file():
            raise AssertionError(f"MSVC unavailable: {vcvars}")
        flags = f'/nologo /std:c++17 /EHsc /W4 /WX /MT /D_WIN32_WINNT=0x0A00 /I"{CORE.parent}"'
        hooked_obj = cls.root / "process_tree_owner_core_fault.obj"
        cmd = (f'call "{vcvars}" >nul && '
               f'cl {flags} "{PROBE}" "{CORE}" /Fe:"{cls.exe}" /link >"{cls.root / "build.raw.log"}" 2>&1 && '
               f'cl {flags} /DFATE_LEASE_CORE_HOOK /FI"{PROBE}" /c "{CORE}" /Fo:"{hooked_obj}" >>"{cls.root / "build.raw.log"}" 2>&1 && '
               f'cl {flags} "{PROBE}" "{hooked_obj}" /Fe:"{cls.fault_exe}" /link >>"{cls.root / "build.raw.log"}" 2>&1')
        batch = cls.root / "build.cmd"
        batch.write_text("@echo off\n" + cmd + "\n", encoding="utf-8")
        env = dict(os.environ, TMP=str(cls.root), TEMP=str(cls.root), TMPDIR=str(cls.root))
        result = subprocess.run(["cmd.exe", "/d", "/c", str(batch)], cwd=cls.root, env=env, timeout=90)
        cls.evidence.append({"build_exit": result.returncode})
        if result.returncode:
            raise AssertionError((cls.root / "build.raw.log").read_bytes().decode("mbcs", errors="replace"))

    @classmethod
    def finish_evidence(cls):
        hashes = {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in [CORE, HEADER, PROBE, pathlib.Path(__file__)] if p.is_file()}
        (cls.root / "evidence.json").write_text(json.dumps({"sources": hashes, "runs": cls.evidence}, indent=2), encoding="utf-8")
        # Only own generated build outputs; never external process/file cleanup.
        for name in ["process_tree_owner_core_probe.exe", "process_tree_owner_core_fault_probe.exe",
                     "process_tree_owner_core_probe.obj", "process_tree_owner_core.obj", "process_tree_owner_core_fault.obj"]:
            (cls.root / name).unlink(missing_ok=True)

    def call(self, mode):
        env = dict(os.environ, TMP=str(self.root), TEMP=str(self.root), TMPDIR=str(self.root))
        binary = self.fault_exe if mode in {"bindings", "invalid"} else self.exe
        p = subprocess.run([str(binary), mode], cwd=self.root, env=env, capture_output=True, timeout=45)
        text = p.stdout.decode("utf-8", errors="replace")
        (self.root / (mode + ".stdout.log")).write_bytes(p.stdout)
        (self.root / (mode + ".stderr.log")).write_bytes(p.stderr)
        rows = [json.loads(line) for line in text.splitlines()]
        self.evidence.append({"mode": mode, "exit": p.returncode, "rows": rows})
        self.assertEqual(p.returncode, 0, (text, p.stderr.decode("utf-8", errors="replace")))
        self.assertTrue(rows)
        return {r["case"]: r for r in rows}

    def test_root_exit_live_descendants_block_release(self):
        rows = self.call("tree")
        self.assertTrue(rows["assigned_before_resume"]["ok"])
        self.assertEqual(rows["assigned_before_resume"]["active"], 1)
        self.assertTrue(rows["root_exit_child_running"]["root_exited"])
        self.assertEqual(rows["root_exit_child_running"]["active"], 2)
        self.assertFalse(rows["root_exit_child_running"]["release_complete"])
        self.assertEqual(rows["final_release"]["active"], 0)
        self.assertTrue(rows["final_release"]["release_complete"])
        self.assertTrue(rows["handles_closed"]["ok"])
        self.assertEqual(rows["handles_closed"]["handle_count_before"], rows["handles_closed"]["handle_count_after"] + 2)
        self.assertEqual(rows["final_active_zero_readback"]["active"], 0)
        self.assertTrue(rows["final_active_zero_readback"]["active_known"])
        self.assertFalse(rows["after_release_unknown"]["release_complete"])

    def test_stale_binding_duplicate_and_unknown_fail_closed(self):
        rows = self.call("bindings")
        for name in ["stale_token", "stale_pid", "stale_creation", "duplicate_claim", "reassign", "unknown", "query_unknown"]:
            self.assertFalse(rows[name]["ok"], rows[name])
            self.assertFalse(rows[name]["release_complete"], rows[name])
        self.assertEqual(rows["duplicate_claim"]["stage"], "duplicate_root_claim")
        self.assertTrue(rows["valid_after_stale"]["ok"])
        self.assertEqual(rows["query_unknown"]["error"], 5)
        self.assertFalse(rows["query_unknown"]["active_known"])
        self.assertEqual(rows["bindings_zero_before_query_denial"]["active"], 0)
        self.assertTrue(rows["still_owned_after_unknown"]["ok"])
        self.assertTrue(rows["bindings_final_release"]["release_complete"])

    def test_root_crash_does_not_hide_live_tree_or_claim_saved(self):
        rows = self.call("crash")
        self.assertEqual(rows["crashed_root_live_tree"]["root_exit_code"], 73)
        self.assertEqual(rows["crashed_root_live_tree"]["active"], 2)
        self.assertFalse(rows["crashed_root_live_tree"]["release_complete"])
        self.assertTrue(rows["crash_final_release"]["release_complete"])
        self.assertEqual(rows["crash_final_release"]["active"], 0)

    def test_destructor_never_kills_unreleased_workers(self):
        rows = self.call("abandon")
        self.assertTrue(rows["descendants_alive_after_destructor"]["ok"])
        self.assertFalse(rows["duplicate_after_abandon"]["ok"])
        self.assertTrue(rows["owned_descendants_naturally_exited"]["ok"])
        self.assertEqual(rows["abandoned_root_tombstone"]["stage"], "duplicate_root_claim")

    def test_invalid_ownership_native_assign_denied_and_real_nested_job(self):
        rows = self.call("invalid")
        for name in ["missing_ownership", "wrong_identity", "invalid_handle", "native_assign_denied"]:
            self.assertFalse(rows[name]["ok"], rows[name])
            self.assertFalse(rows[name]["release_complete"], rows[name])
        self.assertTrue(rows["no_resume_on_failure"]["ok"])
        self.assertEqual(rows["native_assign_denied"]["error"], 5)
        self.assertFalse(rows["failed_assign_unknown"]["release_complete"])
        self.assertTrue(rows["compatible_nested_job"]["ok"])
        self.assertEqual(rows["nested_final_zero"]["active"], 0)
        self.assertTrue(rows["nested_final_release"]["release_complete"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
