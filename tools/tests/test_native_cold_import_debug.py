"""Windows native debugger contract tests; only creates owned E: children."""
import os
from pathlib import Path
import subprocess
import sys
import unittest
import uuid

from tools.diagnostics import native_cold_import_debug as probe

REPO=Path(__file__).resolve().parents[2]
BASE=Path('E:/Caches/Hermes/cache/scratch')


class NativeDebugContract(unittest.TestCase):
    def test_real_log_second_chance_is_distinct_from_first_chance(self):
        log=(REPO/'tools/tests/fixtures/native_cold_import_second_chance.txt').read_text(errors='replace')
        result=probe.parse_debug_log(log)
        self.assertEqual(result['child_exit_hex'],'0xc0000005')
        self.assertEqual(len(result['second_chance']),1)
        event=result['second_chance'][0]
        self.assertEqual(event['code'],'0xc0000005')
        self.assertEqual(event['parameters'],[0,8])
        self.assertEqual(event['registers']['RBX'],8)
        self.assertGreater(len(event['frames']),5)
        self.assertIn('offset=0x53fd042',event['module_line'])
        self.assertTrue(any('value=0x0' in x for x in event['watches']))

    def test_root_refuses_warm_directory(self):
        owned=BASE/('round39-debugger-root-test-'+uuid.uuid4().hex)
        owned.mkdir()
        try:
            with self.assertRaises(ValueError):
                probe.require_fresh_e(owned)
        finally:
            owned.rmdir()

    def test_root_refuses_c_drive(self):
        with self.assertRaises(ValueError):
            probe.require_fresh_e(Path('C:/round39-must-not-create-'+uuid.uuid4().hex))

    @unittest.skipUnless(os.name=='nt','Windows x64 debugger')
    def test_controlled_real_av_child(self):
        root=BASE/('round39-debugger-test-'+uuid.uuid4().hex)
        root.mkdir()
        cpp=root/'av.cpp'
        cpp.write_text('#include <cstdint>\nint main(){return *reinterpret_cast<volatile int*>(uintptr_t(8));}\n')
        bat=root/'build.cmd'
        bat.write_text(f'@call "D:/VS2022/Common7/Tools/VsDevCmd.bat" -arch=x64 -host_arch=x64\n@cl /nologo /EHsc /Od "{cpp}" /Fe:"{root / "av.exe"}" /Fo:"{root / "av.obj"}"\n')
        build=subprocess.run(['cmd.exe','/d','/c',str(bat)],cwd=root,capture_output=True)
        (root/'fixture-build.log').write_bytes(build.stdout+build.stderr)
        self.assertEqual(build.returncode,0)
        candidate=root/'capture'
        result=subprocess.run([sys.executable,'-B',str(REPO/'tools/diagnostics/native_cold_import_debug.py'),
                               '--root',str(candidate),'--source',str(REPO),'--godot',str(root/'av.exe'),
                               '--timeout','15'],cwd=REPO,capture_output=True,timeout=60)
        (root/'cli.log').write_bytes(result.stdout+result.stderr)
        self.assertEqual(result.returncode,1)
        parsed=probe.parse_debug_log((candidate/'debug.log').read_text(errors='replace'))
        self.assertEqual(parsed['child_exit_hex'],'0xc0000005')
        self.assertEqual(len(parsed['second_chance']),1)
        self.assertEqual(parsed['second_chance'][0]['parameters'],[0,8])
        self.assertIn('av.exe',parsed['second_chance'][0]['module_line'])


if __name__=='__main__':
    unittest.main()