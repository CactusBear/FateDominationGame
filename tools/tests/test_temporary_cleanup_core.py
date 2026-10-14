"""Real Win32 core probe; all generated inputs/output stay on physical E:."""
import ctypes
import hashlib
import json
import os
import pathlib
import queue
import subprocess
import sys
import threading
import unittest
import uuid

REPO = pathlib.Path(__file__).resolve().parents[2]
CORE = REPO / "addons/fate_server_signals/src/temporary_cleanup_core.cpp"
HEADER = CORE.with_suffix(".hpp")
PROBE = pathlib.Path(__file__).with_name("temporary_cleanup_core_probe.cpp")
EVIDENCE = []


class OwnedProcess:
    """Job contains only children launched by this harness, never enumerated PIDs."""
    def __init__(self, args, cwd, launcher=False):
        from ctypes import wintypes as w
        k = ctypes.WinDLL("kernel32", use_last_error=True)
        k.CreateJobObjectW.argtypes = [ctypes.c_void_p, w.LPCWSTR]
        k.CreateJobObjectW.restype = w.HANDLE
        k.AssignProcessToJobObject.argtypes = [w.HANDLE, w.HANDLE]
        k.AssignProcessToJobObject.restype = w.BOOL
        k.TerminateJobObject.argtypes = [w.HANDLE, w.UINT]
        k.CloseHandle.argtypes = [w.HANDLE]
        k.SetInformationJobObject.argtypes = [w.HANDLE, ctypes.c_int, ctypes.c_void_p, w.DWORD]
        k.SetInformationJobObject.restype = w.BOOL
        class BasicLimits(ctypes.Structure):
            _fields_ = [("ProcessTime", ctypes.c_int64), ("JobTime", ctypes.c_int64),
                        ("Flags", w.DWORD), ("MinWorkingSet", ctypes.c_size_t),
                        ("MaxWorkingSet", ctypes.c_size_t), ("ActiveProcesses", w.DWORD),
                        ("Affinity", ctypes.c_size_t), ("Priority", w.DWORD), ("Scheduling", w.DWORD)]
        class IoCounters(ctypes.Structure):
            _fields_ = [(field, ctypes.c_uint64) for field in
                        ["ReadOps", "WriteOps", "OtherOps", "ReadBytes", "WriteBytes", "OtherBytes"]]
        class ExtendedLimits(ctypes.Structure):
            _fields_ = [("Basic", BasicLimits), ("Io", IoCounters),
                        ("ProcessMemory", ctypes.c_size_t), ("JobMemory", ctypes.c_size_t),
                        ("PeakProcessMemory", ctypes.c_size_t), ("PeakJobMemory", ctypes.c_size_t)]
        self.k, self.job = k, k.CreateJobObjectW(None, None)
        if not self.job:
            raise ctypes.WinError(ctypes.get_last_error())
        limits = ExtendedLimits()
        limits.Basic.Flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if not k.SetInformationJobObject(self.job, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
            error = ctypes.get_last_error()
            k.CloseHandle(self.job)
            raise ctypes.WinError(error)
        if launcher:
            args = [sys.executable, "-c", "import subprocess,sys; assert input()=='GO'; sys.exit(subprocess.run(sys.argv[1:]).returncode)", *args]
        env = dict(os.environ, TMP=str(cwd), TEMP=str(cwd), TMPDIR=str(cwd))
        self.p = subprocess.Popen(args, cwd=cwd, env=env, stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                  encoding="utf-8", errors="replace", bufsize=1)
        if not k.AssignProcessToJobObject(self.job, int(self.p._handle)):
            self.p.kill()  # exact child handle only
            self.p.wait()
            k.CloseHandle(self.job)
            raise ctypes.WinError(ctypes.get_last_error())
        self.lines = queue.Queue()
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        self.send("GO")

    def _read(self):
        for line in self.p.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def send(self, line):
        self.p.stdin.write(line + "\n")
        self.p.stdin.flush()

    def line(self):
        line = self.lines.get(timeout=15)
        if line is None:
            raise AssertionError(f"probe closed stdout, exit={self.p.poll()}")
        return json.loads(line)

    def finish(self, command=None, expected=0):
        if command is not None:
            self.send(command)
        rc = self.p.wait(timeout=30)
        self.reader.join(timeout=5)
        self.p.stdin.close()
        self.p.stdout.close()
        self.k.TerminateJobObject(self.job, 95)  # only this harness's assigned descendants
        self.k.CloseHandle(self.job)
        self.job = None
        if expected is not None and rc != expected:
            raise AssertionError(f"owned child exit {rc}, expected {expected}")
        return rc

    def abort(self):
        if self.job:
            self.k.TerminateJobObject(self.job, 96)
            self.p.wait(timeout=15)
            self.reader.join(timeout=5)
            self.p.stdin.close()
            self.p.stdout.close()
            self.k.CloseHandle(self.job)
            self.job = None


def no_reparse(path):
    for part in [path, *path.parents]:
        if part.exists() and part.stat(follow_symlinks=False).st_file_attributes & 0x400:
            raise AssertionError(f"test path is reparse: {part}")


class TemporaryCleanupCoreTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.name != "nt":
            raise unittest.SkipTest("Win32 real execution required")
        no_reparse(REPO)
        cls.root = pathlib.Path("E:/") / ("FateCleanupCoreScratch-" + uuid.uuid4().hex)
        cls.root.mkdir()
        no_reparse(cls.root)
        cls.addClassCleanup(cls.clean_outputs)
        cls.exe = cls.root / "temporary_cleanup_core_probe.exe"
        vcvars = pathlib.Path(os.environ.get("FATE_CLEANUP_VCVARS", "D:/VS2022/VC/Auxiliary/Build/vcvars64.bat"))
        if not vcvars.is_file():
            raise AssertionError(f"MSVC environment unavailable: {vcvars}")
        cls.assert_sources()
        command = f'call "{vcvars}" >nul && cl /nologo /std:c++17 /EHsc /W4 /WX /MT /D_WIN32_WINNT=0x0A00 /I"{CORE.parent}" "{PROBE}" "{CORE}" /Fe:"{cls.exe}" /link bcrypt.lib >"{cls.root / "build.raw.log"}" 2>&1'
        batch = cls.root / "build.cmd"
        batch.write_text("@echo off\n" + command + "\n", encoding="utf-8")
        proc = OwnedProcess(["cmd.exe", "/d", "/c", str(batch)], cls.root, launcher=True)
        try:
            rc = proc.finish(expected=None)
            log = []
            while not proc.lines.empty():
                line = proc.lines.get()
                if line is not None:
                    log.append(line)
            (cls.root / "build.log").write_text("".join(log), encoding="utf-8")
            if rc:
                native = cls.root / "build.raw.log"
                details = native.read_bytes().decode("mbcs", errors="replace") if native.is_file() else "".join(log)
                raise AssertionError(f"native build failed ({rc}): {details}")
        finally:
            proc.abort()
        print("EVIDENCE_ROOT=" + str(cls.root), flush=True)

    @classmethod
    def assert_sources(cls):
        if not HEADER.is_file() or not CORE.is_file():
            raise AssertionError("exclusive same-HANDLE cleanup core is missing")

    @classmethod
    def tearDownClass(cls):
        (cls.root / "evidence.json").write_text(json.dumps(EVIDENCE, indent=2), encoding="utf-8")

    @classmethod
    def clean_outputs(cls):
        # Keep diagnostics and refused files; reclaim only owned compiler outputs.
        for name in ["temporary_cleanup_core_probe.exe", "temporary_cleanup_core_probe.obj", "temporary_cleanup_core.obj"]:
            (cls.root / name).unlink(missing_ok=True)

    def start(self, args):
        p = OwnedProcess([str(self.exe), *map(str, args)], self.root)
        self.addCleanup(p.abort)
        return p

    def call(self, args):
        p = self.start(args)
        r = p.line()
        p.finish()
        EVIDENCE.append({"args": list(map(str, args)), "result": r})
        return r

    def identity(self, path):
        i = self.call(["inspect", path])
        return [i["volume"], i["file_index"]]

    def request(self, name, data=b"explicit owned temporary\x00bytes", root=None):
        parent = self.root / name
        parent.mkdir()
        path = parent / "artifact.tmp"
        path.write_bytes(data)
        root = root or self.root
        return [root, path, *self.identity(root), *self.identity(parent),
                *self.identity(path), len(data), hashlib.sha256(data).hexdigest(), "temporary", "end"], data

    def test_delete_and_readback(self):
        request, _ = self.request("valid")
        result = self.call(["delete", *request])
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["removed_bytes"], request[8])
        self.assertFalse(pathlib.Path(request[1]).exists())
        with self.assertRaises(FileNotFoundError):
            pathlib.Path(request[1]).read_bytes()


    def test_core_sources_present(self):
        self.assertTrue(HEADER.is_file(), "exclusive same-HANDLE cleanup core is missing")
        self.assertTrue(CORE.is_file(), "exclusive same-HANDLE cleanup implementation is missing")

    def retained(self, request, data, expected_stage=None):
        r = self.call(["delete", *request])
        self.assertFalse(r["ok"], r)
        self.assertEqual(r["removed_bytes"], 0)
        self.assertFalse(r["recovery_required"], r)  # these fixtures all refuse before disposition
        if expected_stage:
            self.assertEqual(r["stage"], expected_stage, r)
        actual = pathlib.Path(request[1]).read_bytes()
        self.assertEqual(actual, data)
        self.assertEqual(hashlib.sha256(actual).hexdigest(), hashlib.sha256(data).hexdigest())
        EVIDENCE.append({"retained": str(request[1]), "sha256": hashlib.sha256(actual).hexdigest()})
        return r

    def test_wrong_evidence_refused_unchanged(self):
        for field, value, stage in [(9, "0" * 64, "sha256_changed"),
                                    (8, 100, "size_changed"),
                                    (7, 1, "file_identity_changed"),
                                    (5, 1, "parent_identity_changed"),
                                    (3, 1, "approved_root_identity_changed"),
                                    (9, "ABC", "invalid_sha256"),
                                    (10, "archive", "not_explicit_temporary_file"),
                                    (10, "unspecified", "not_explicit_temporary_file")]:
            with self.subTest(field=field, stage=stage):
                request, data = self.request("evidence-" + stage + "-" + str(field) + "-" + str(value))
                request[field] = value
                self.retained(request, data, stage)

    def test_two_process_exclusion_and_normal_release(self):
        request, data = self.request("competition")
        holder = self.start(["hold", *request])
        self.assertTrue(holder.line()["ok"])
        r = self.call(["delete", *request])
        self.assertFalse(r["ok"], r)
        self.assertEqual(r["native_error"], 32, r)
        for mode in ["tryread", "trywrite", "trydelete"]:
            with self.subTest(mode=mode):
                r = self.call([mode, request[1]])
                self.assertFalse(r["ok"], r)
                self.assertEqual(r["native_error"], 32)
        with self.assertRaises(OSError):
            pathlib.Path(request[1]).unlink()
        with self.assertRaises(OSError):
            pathlib.Path(request[1]).parent.rename(self.root / "renamed-parent")
        holder.finish("CLOSE")
        self.assertEqual(pathlib.Path(request[1]).read_bytes(), data)
        self.assertTrue(self.call(["delete", *request])["ok"])
        self.assertFalse(pathlib.Path(request[1]).exists())

    def test_existing_reader_blocks_acquire_no_forced_takeover(self):
        request, data = self.request("reader")
        reader = self.start(["occupy", request[1]])
        self.assertTrue(reader.line()["ok"])
        r = self.retained(request, data, "exclusive_open")
        self.assertEqual(r["native_error"], 32)
        self.assertIsNone(reader.p.poll())
        reader.finish("CLOSE")
        self.assertTrue(self.call(["delete", *request])["ok"])

    def test_crash_releases_without_deleting(self):
        request, data = self.request("crash")
        holder = self.start(["hold", *request])
        self.assertTrue(holder.line()["ok"])
        EVIDENCE.append({"owned_pid": holder.p.pid, "crash_exit": holder.finish("CRASH", expected=73)})
        self.assertEqual(pathlib.Path(request[1]).read_bytes(), data)
        self.assertTrue(self.call(["delete", *request])["ok"])
        self.assertFalse(pathlib.Path(request[1]).exists())

    def test_parent_replaced_after_approval(self):
        request, data = self.request("parent-change")
        path = pathlib.Path(request[1])
        old = path.parent
        moved = self.root / "parent-change-old"
        old.rename(moved)
        old.mkdir()
        (moved / path.name).rename(path)
        self.retained(request, data, "parent_identity_changed")

    def test_file_replaced_after_approval(self):
        request, data = self.request("file-change")
        path = pathlib.Path(request[1])
        path.rename(path.with_suffix(".old"))
        path.write_bytes(data)
        self.retained(request, data, "file_identity_changed")

    def test_hardlink_refused(self):
        request, data = self.request("hardlink")
        alias = self.root / "hardlink-alias"
        os.link(request[1], alias)
        self.retained(request, data, "regular_single_link_required")
        self.assertEqual(alias.read_bytes(), data)

    def test_directory_refused_without_recursion(self):
        request, data = self.request("directory")
        directory = pathlib.Path(request[1]).parent
        request[1] = directory
        request[4:6] = self.identity(directory.parent)
        request[6:8] = self.identity(directory)
        r = self.call(["delete", *request])
        self.assertFalse(r["ok"])
        self.assertEqual(r["stage"], "regular_single_link_required")
        self.assertEqual((directory / "artifact.tmp").read_bytes(), data)

    def test_junction_ancestor_refused(self):
        request, data = self.request("junction-target")
        junction = self.root / "junction"
        batch = self.root / "junction.cmd"
        batch.write_text(f'@echo off\nmklink /J "{junction}" "{pathlib.Path(request[1]).parent}"\n', encoding="utf-8")
        proc = self.start_build(["cmd.exe", "/d", "/c", str(batch)])
        proc.finish()
        self.assertTrue(junction.stat(follow_symlinks=False).st_file_attributes & 0x400)
        request[1] = junction / "artifact.tmp"
        try:
            self.retained(request, data, "ancestor_not_plain_directory")
        finally:
            junction.rmdir()  # exact owned link; not recursive target cleanup

    def start_build(self, args):
        p = OwnedProcess(args, self.root, launcher=True)
        self.addCleanup(p.abort)
        return p

    def test_c_outside_boundary_without_touching_c(self):
        request, data = self.request("outside-c")
        original = request[1]
        request[1] = "C:/FateCleanupCoreNeverCreated/explicit.tmp"
        r = self.call(["delete", *request])
        self.assertFalse(r["ok"])
        self.assertEqual(r["stage"], "outside_approved_root")
        self.assertEqual(pathlib.Path(original).read_bytes(), data)

    def test_noncanonical_ads_device_and_sibling_boundary(self):
        request, data = self.request("paths")
        original = request[1]
        invalid = [str(original) + ":stream", str(original) + ".", str(original) + " ",
                   str(pathlib.Path(original).parent) + "/../paths/artifact.tmp",
                   "\\\\?\\" + str(original), "E:/NUL", "E:/CON.txt"]
        for path in invalid:
            with self.subTest(path=path):
                request[1] = path
                r = self.call(["delete", *request])
                self.assertFalse(r["ok"], r)
                self.assertEqual(r["stage"], "unsafe_path")
                self.assertEqual(pathlib.Path(original).read_bytes(), data)
        request[1] = original
        request[0] = pathlib.Path(original).parent / "sibling"
        self.retained(request, data, "outside_approved_root")

    def test_empty_and_multichunk_hash(self):
        for name, data in [("empty", b""), ("multichunk", bytes(range(256)) * 1025)]:
            with self.subTest(name=name):
                request, _ = self.request(name, data=data)
                r = self.call(["delete", *request])
                self.assertTrue(r["ok"], r)
                self.assertEqual(r["removed_bytes"], len(data))
                self.assertFalse(pathlib.Path(request[1]).exists())


    def test_leaf_symlink_refused(self):
        request, data = self.request("symlink-target")
        target = pathlib.Path(request[1])
        link = target.with_name("symlink.tmp")
        try:
            os.symlink(target, link)
        except OSError as error:
            EVIDENCE.append({"SKIP": "leaf_symlink", "reason": str(error)})
            self.skipTest(f"symlink privilege unavailable: {error}")
        request[1] = link
        try:
            self.retained(request, data, "regular_single_link_required")
        finally:
            link.unlink()
        self.assertEqual(target.read_bytes(), data)

    def test_readonly_disposition_refused(self):
        import stat
        request, data = self.request("readonly")
        path = pathlib.Path(request[1])
        path.chmod(stat.S_IREAD)
        try:
            self.retained(request, data, "handle_delete")
        finally:
            path.chmod(stat.S_IREAD | stat.S_IWRITE)

    def test_existing_mapping_fails_closed(self):
        request, data = self.request("mapped")
        holder = self.start(["map", request[1]])
        self.assertTrue(holder.line()["ok"])
        self.retained(request, data, "exclusive_open")
        self.assertIsNone(holder.p.poll())
        holder.finish("CLOSE")
        self.assertTrue(self.call(["delete", *request])["ok"])

    def test_leaf_junction_refused(self):
        request, data = self.request("leaf-junction-target")
        original = pathlib.Path(request[1])
        junction = original.with_name("link.tmp")
        batch = self.root / "leaf-junction.cmd"
        batch.write_text(f'@echo off\nmklink /J "{junction}" "{original.parent}"\n', encoding="utf-8")
        proc = self.start_build(["cmd.exe", "/d", "/c", str(batch)])
        proc.finish()
        request[1] = junction
        try:
            r = self.call(["delete", *request])
            self.assertFalse(r["ok"])
            self.assertEqual(r["stage"], "regular_single_link_required")
            self.assertTrue(junction.stat(follow_symlinks=False).st_file_attributes & 0x400)
            self.assertEqual(original.read_bytes(), data)
        finally:
            junction.rmdir()


    def test_lease_moves_single_attempt_and_no_reacquire(self):
        request, _ = self.request("lease-contract")
        p = self.start(["lease_contract", *request])
        stages = [p.line() for _ in range(6)]
        p.finish()
        self.assertEqual([r["stage"] for r in stages], ["exclusive_handle_acquired",
                         "lease_already_held", "inactive_lease", "inactive_lease",
                         "deleted_absence_confirmed", "inactive_lease"])
        self.assertFalse(pathlib.Path(request[1]).exists())
        EVIDENCE.append({"lease_contract": stages})


class EvidenceRunner(unittest.TextTestRunner):
    def run(self, test):
        result = super().run(test)
        root = getattr(TemporaryCleanupCoreTests, "root", None)
        if root:
            summary = {"tests": result.testsRun, "failures": len(result.failures),
                       "errors": len(result.errors), "skips": [(test.id(), reason) for test, reason in result.skipped],
                       "successful": result.wasSuccessful(), "command": "python tools/tests/test_temporary_cleanup_core.py",
                       "source_sha256": {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest()
                                         for p in [HEADER, CORE, PROBE, pathlib.Path(__file__)] if p.is_file()}}
            (root / "run-summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        return result


if __name__ == "__main__":
    unittest.main(verbosity=2, testRunner=EvidenceRunner)