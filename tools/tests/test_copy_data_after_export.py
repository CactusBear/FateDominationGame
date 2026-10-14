"""G03：只在 Hermes scratch 使用真实文件，不执行发行导出。"""
import importlib.util
import contextlib
import io
import os
import shutil
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "copy_data_after_export.py"
spec = importlib.util.spec_from_file_location("copy_export_data", SCRIPT)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
SCRATCH = (Path.home() / "AppData/Local/hermes/cache/scratch").resolve()


class ExplicitTargetTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="g03-copy-", dir=SCRATCH)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.previous = tool.PROJECT_ROOT, tool.DATA_DIR, tool.PRESETS
        tool.PROJECT_ROOT = self.root / "project"
        tool.DATA_DIR = tool.PROJECT_ROOT / "data"
        tool.PRESETS = tool.PROJECT_ROOT / "export_presets.cfg"
        tool.DATA_DIR.mkdir(parents=True)
        self.addCleanup(self.restore)

    def restore(self):
        tool.PROJECT_ROOT, tool.DATA_DIR, tool.PRESETS = self.previous

    def test_missing_target_is_error(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            tool.resolve_output_dir([str(SCRIPT)])
        self.assertEqual(error.exception.code, 2)

    def test_named_preset_uses_its_own_section(self):
        tool.PRESETS.write_text('[preset.0]\nname="first"\nexport_path="../wrong/app.exe"\n'
                               '[preset.0.options]\nname="chosen"\nexport_path="../trap/app.exe"\n'
                               '[preset.7]\nname="chosen"\nexport_path="../正确目录/app.exe"\n', encoding="utf-8")
        self.assertEqual(tool.resolve_output_dir(["copy", "--project", str(tool.PROJECT_ROOT), "--preset", "chosen"]), (self.root / "正确目录", tool.PROJECT_ROOT))

    def test_source_destination_overlap_rejected_before_write(self):
        (tool.DATA_DIR / "real.json").write_bytes(b'{"actual":true}')
        for output in (tool.PROJECT_ROOT, tool.DATA_DIR / "nested"):
            with self.subTest(output=output), self.assertRaises(ValueError):
                tool.copy_data(output, tool.PROJECT_ROOT)
        self.assertFalse((tool.DATA_DIR / "nested").exists())

    def test_destination_hardlink_cannot_modify_outside_file(self):
        (tool.DATA_DIR / "real.json").write_bytes(b'{"actual":true}')
        outside = self.root / "outside.json"
        outside.write_bytes(b"original")
        output = self.root / "output"
        (output / "data").mkdir(parents=True)
        os.link(outside, output / "data/real.json")
        with self.assertRaises(ValueError):
            tool.copy_data(output, tool.PROJECT_ROOT)
        self.assertEqual(outside.read_bytes(), b"original")

    def test_explicit_directories_and_argument_rejections(self):
        output = self.root / "输出 目录"
        for arguments in ([str(output)], ["--output-dir", str(output)]):
            self.assertEqual(tool.resolve_output_dir(["copy", "--project", str(tool.PROJECT_ROOT), *arguments]), (output, tool.PROJECT_ROOT))
        for arguments in ([], [""], ["   "], ["--preset", ""],
                          [str(output), "--preset", "chosen"],
                          ["--output-dir", str(output), str(output)],
                          ["--preset", "chosen", "--output-dir", str(output)],
                          [str(output), "extra"], ["--unknown"]):
            with self.subTest(arguments=arguments), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                tool.resolve_output_dir(["copy", "--project", str(tool.PROJECT_ROOT), *arguments])

    def test_preset_missing_duplicate_empty_malformed(self):
        cases = ('[preset.0]\nname="other"\nexport_path="../wrong/app.exe"\n',
                 '[preset.0]\nname="chosen"\nexport_path=""\n',
                 '[preset.0]\nname="chosen"\n',
                 '[preset.0]\nname="chosen"\nexport_path="../folder/"\n',
                 '[preset.0]\nname="chosen"\nexport_path="../a.exe"\n[preset.1]\nname="chosen"\n',
                 '[preset.0]\nname="chosen"\nname="chosen"\n',
                 '[preset.0]\nname="chosen"\n[preset.0]\nname="chosen"\n',
                 '[preset.0]\nname="chosen"\nexport_path=invalid\n')
        for text in cases:
            tool.PRESETS.write_text(text, encoding="utf-8")
            with self.subTest(text=text), self.assertRaises(ValueError):
                tool.resolve_output_dir(["copy", "--project", str(tool.PROJECT_ROOT), "--preset", "chosen"])
        tool.PRESETS.unlink()
        with self.assertRaises(FileNotFoundError):
            tool.resolve_output_dir(["copy", "--project", str(tool.PROJECT_ROOT), "--preset", "chosen"])

    def test_absolute_preset_and_bom(self):
        import json
        executable = self.root / "absolute/app.exe"
        tool.PRESETS.write_text('[preset.9]\nname="chosen"\nexport_path=' + json.dumps(str(executable)) + '\n', encoding="utf-8-sig")
        self.assertEqual(tool.resolve_output_dir(["copy", "--project", str(tool.PROJECT_ROOT), "--preset", "chosen"]), (executable.parent, tool.PROJECT_ROOT))

    def test_real_copy_overwrite_skip_and_preserve_old(self):
        nested = tool.DATA_DIR / "中文/nested"
        nested.mkdir(parents=True)
        (nested / "card.json").write_bytes('{"卡":"真实测试文件"}'.encode())
        (nested / "art.png").write_bytes(bytes(range(256)))
        (nested / "art.png.import").write_bytes(b"import metadata")
        output = self.root / "output"
        (output / "data/中文/nested").mkdir(parents=True)
        (output / "data/中文/nested/card.json").write_bytes(b"old")
        (output / "data/stale.json").write_bytes(b"keep")
        self.assertEqual(tool.copy_data(output, tool.PROJECT_ROOT), (2, 1))
        for filename in ("card.json", "art.png"):
            self.assertEqual((output / "data/中文/nested" / filename).read_bytes(), (nested / filename).read_bytes())
        self.assertFalse((output / "data/中文/nested/art.png.import").exists())
        self.assertEqual((output / "data/stale.json").read_bytes(), b"keep")

    def test_empty_and_missing_source(self):
        output = self.root / "output"
        self.assertEqual(tool.copy_data(output, tool.PROJECT_ROOT), (0, 0))
        self.assertTrue((output / "data").is_dir())
        tool.DATA_DIR.rmdir()
        with self.assertRaises(ValueError):
            tool.copy_data(self.root / "never-created", tool.PROJECT_ROOT)
        self.assertFalse((self.root / "never-created").exists())

    def test_destination_conflict_fails_before_any_copy(self):
        (tool.DATA_DIR / "first.json").write_bytes(b"first")
        (tool.DATA_DIR / "conflict.json").write_bytes(b"second")
        output = self.root / "output"
        (output / "data/conflict.json").mkdir(parents=True)
        with self.assertRaises(ValueError):
            tool.copy_data(output, tool.PROJECT_ROOT)
        self.assertFalse((output / "data/first.json").exists())

    def test_real_junction_redirects_rejected(self):
        if os.name != "nt":
            self.skipTest("Windows junction 专项")
        outside = self.root / "outside"
        outside.mkdir()
        (tool.DATA_DIR / "real.json").write_bytes(b"copy")
        for link in (self.root / "output", tool.DATA_DIR / "linked"):
            result = subprocess.run(["cmd.exe", "/c", "mklink", "/J", str(link), str(outside)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            try:
                self.assertTrue(link.is_junction())
                with self.assertRaises(ValueError):
                    tool.copy_data(self.root / "output", tool.PROJECT_ROOT)
                self.assertEqual(list(outside.iterdir()), [])
            finally:
                os.rmdir(link)

    def test_cli_real_isolated_project(self):
        # 原脚本逐字节复制到隔离项目，让子进程沿真实 __file__ 定位。
        script = tool.PROJECT_ROOT / "tools/copy_data_after_export.py"
        script.parent.mkdir()
        shutil.copy2(SCRIPT, script)
        (tool.DATA_DIR / "real.json").write_bytes(b'{"disk":true}')
        tool.PRESETS.write_text('[preset.0]\nname="first"\nexport_path="../wrong/app.exe"\n'
                               '[preset.3]\nname="selected"\nexport_path="../selected/app.exe"\n', encoding="utf-8")
        for arguments, expected in (([], 2), (["--preset", "missing"], 1), (["--preset", "selected"], 0),
                                    (["--output-dir", str(self.root / "explicit")], 0)):
            result = subprocess.run([sys.executable, "-B", str(script), "--project", str(tool.PROJECT_ROOT), *arguments], cwd=self.root,
                                    capture_output=True, text=True, encoding="utf-8", timeout=15)
            self.assertEqual(result.returncode, expected, result.stderr)
        self.assertFalse((self.root / "wrong").exists())
        for name in ("selected", "explicit"):
            self.assertEqual((self.root / name / "data/real.json").read_bytes(), b'{"disk":true}')


if __name__ == "__main__":
    unittest.main()