import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = Path(os.environ.get('TMPDIR', Path.home() / 'AppData/Local/hermes/cache/scratch')).resolve()
SPEC = importlib.util.spec_from_file_location('package_audit', ROOT / 'tools/release/package_audit.py')
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class PackageAuditContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='round9-audit-', dir=SCRATCH)
        self.root = Path(self.temp.name)
        self.project = self.root / 'project'
        self.project.mkdir()
        (self.project / 'data').mkdir()
        (self.project / 'data' / 'runtime.json').write_bytes(b'{}')
        (self.project / 'data' / 'ignored.import').write_bytes(b'import')
        (self.project / 'export_presets.cfg').write_text(
            '[preset.0]\nname="Windows Client"\nplatform="Windows Desktop"\n'
            'dedicated_server=false\n[preset.0.options]\n'
            'binary_format/embed_pck=false\n', encoding='utf-8')
        (self.project / 'release_contract.json').write_text(json.dumps({'version':1,'targets':[{'preset':'Windows Client','platform':'windows','role':'client','executable':'FateDomination.exe','runtime_files':[]}]}), encoding='utf-8')

    def tearDown(self):
        self.temp.cleanup()

    def audit(self, package):
        report = self.root / 'report.json'
        code = AUDIT.audit(self.project, package, report, 'Windows Client')
        return code, json.loads(report.read_text(encoding='utf-8'))

    def test_missing_package_and_missing_files_block(self):
        code, report = self.audit(self.root / 'missing')
        self.assertEqual(code, 2)
        self.assertEqual(report['status'], 'BLOCK')
        self.assertEqual(set(report['blockers']), {'package_missing', 'executable_missing', 'pck_missing'})

    def test_runtime_manifest_matches_copy_contract(self):
        package = self.root / 'package'
        (package / 'data').mkdir(parents=True)
        (package / 'data' / 'runtime.json').write_bytes(b'{}')
        (package / 'data' / 'ignored.import').write_bytes(b'not-copied')
        (package / 'FateDomination.exe').write_bytes(b'exe')
        import hashlib, struct
        payload = b'config_version=5\n'
        name = b'project.godot\x00'
        header = struct.pack('<6I2Q', 0x43504447,4,4,7,2,2,112,112+len(payload)) + bytes(72)
        entry = struct.pack('<I',len(name)) + name + struct.pack('<QQ',0,len(payload)) + hashlib.md5(payload).digest() + struct.pack('<I',0)
        (package / 'FateDomination.pck').write_bytes(header + payload + struct.pack('<I',1) + entry)
        code, report = self.audit(package)
        self.assertEqual(code, 0)
        self.assertEqual(report['status'], 'STATIC_PASS_RUNTIME_PENDING')
        self.assertEqual(report['data'], {'missing': [], 'extra': [], 'changed': []})

    def test_embed_pck_remains_explicitly_unsupported(self):
        (self.project / 'export_presets.cfg').write_text(
            '[preset.0]\nname="Windows Client"\nplatform="Windows Desktop"\n'
            'dedicated_server=false\n[preset.0.options]\n'
            'binary_format/embed_pck=true\n', encoding='utf-8')
        package = self.root / 'embedded'
        (package / 'data').mkdir(parents=True)
        (package / 'data' / 'runtime.json').write_bytes(b'{}')
        (package / 'FateDomination.exe').write_bytes(b'exe')
        code, report = self.audit(package)
        self.assertEqual(code, 2)
        self.assertEqual(report['status'], 'BLOCK')
        self.assertEqual(report['blockers'], ['embedded_pck_unsupported'])
        self.assertFalse(report['pck_present'])
        self.assertTrue(report['embed_pck'])

    def test_linux_preset_is_explicitly_rejected(self):
        (self.project / 'export_presets.cfg').write_text(
            '[preset.0]\nname="Linux"\nplatform="Linux"\ndedicated_server=false\n'
            '[preset.0.options]\nbinary_format/embed_pck=false\n', encoding='utf-8')
        with self.assertRaises(ValueError):
            self.audit(self.root / 'package')


    def test_manifest_rejects_external_file_link_before_open_or_hash(self):
        outside = self.root / 'outside'
        outside.mkdir()
        sentinel = outside / 'sentinel.txt'
        sentinel.write_text('owned ordinary fixture', encoding='utf-8')
        link = self.project / 'data' / 'linked.txt'
        try:
            link.symlink_to(sentinel)
        except OSError as exc:
            self.skipTest(f'当前主机不允许真实文件 symlink: {exc}')
        real_open = Path.open
        real_sha = AUDIT.sha
        accesses = []

        def guarded_open(path, *args, **kwargs):
            if path.resolve() == sentinel:
                accesses.append('open')
                raise AssertionError('不得读取包外 sentinel')
            return real_open(path, *args, **kwargs)

        def guarded_sha(path):
            if path.resolve() == sentinel:
                accesses.append('hash')
                raise AssertionError('不得哈希包外 sentinel')
            return real_sha(path)

        with patch.object(Path, 'open', guarded_open), patch.object(AUDIT, 'sha', guarded_sha):
            with self.assertRaisesRegex(ValueError, '拒绝链接/junction'):
                AUDIT.manifest(self.project / 'data')
        self.assertEqual(accesses, [])

    def test_manifest_rejects_external_junction_before_enumeration_or_hash(self):
        import subprocess
        outside = self.root / 'outside'
        outside.mkdir()
        sentinel = outside / 'sentinel.txt'
        sentinel.write_text('owned ordinary fixture', encoding='utf-8')
        link = self.project / 'data' / 'linked'
        if os.name != 'nt' or not hasattr(Path, 'is_junction'):
            self.skipTest('当前主机不支持 Windows junction')
        result = subprocess.run(['cmd.exe', '/d', '/c', 'mklink', '/J', str(link), str(outside)],
                                capture_output=True)
        if result.returncode or not link.is_junction():
            self.skipTest('当前主机不允许创建自有 junction')
        real_iterdir, real_open, real_sha = Path.iterdir, Path.open, AUDIT.sha
        real_scandir = os.scandir
        accesses = []

        def guarded_scandir(path):
            if Path(path).resolve() == outside:
                accesses.append('enumerate')
                raise AssertionError('不得遍历包外目录')
            return real_scandir(path)

        def guarded_iterdir(path):
            if path.resolve() == outside:
                accesses.append('enumerate')
                raise AssertionError('不得遍历包外目录')
            return real_iterdir(path)

        def guarded_open(path, *args, **kwargs):
            if path.resolve() == sentinel:
                accesses.append('open')
                raise AssertionError('不得读取包外 sentinel')
            return real_open(path, *args, **kwargs)

        def guarded_sha(path):
            if path.resolve() == sentinel:
                accesses.append('hash')
                raise AssertionError('不得哈希包外 sentinel')
            return real_sha(path)

        try:
            with patch.object(os, 'scandir', guarded_scandir), patch.object(Path, 'iterdir', guarded_iterdir), patch.object(Path, 'open', guarded_open), patch.object(AUDIT, 'sha', guarded_sha):
                with self.assertRaisesRegex(ValueError, '拒绝链接/junction'):
                    AUDIT.manifest(self.project / 'data')
            self.assertEqual(accesses, [])
        finally:
            link.rmdir()  # 只删除 junction，本测试从不递归删除目标。

    def test_pck_v4_index_integrity_and_unsupported_formats(self):
        import hashlib, struct
        self.assertTrue(hasattr(AUDIT, 'pck_index'), '缺少真实 PCK 索引审计')
        pck = self.root / 'sample.pck'
        payload = b'actual resource'
        name = b'assets/runtime.cfg\x00'
        header = struct.pack('<6I2Q', 0x43504447,4,4,7,2,2,112,112+len(payload)) + bytes(72)
        entry = struct.pack('<I',len(name)) + name + struct.pack('<QQ',0,len(payload)) + hashlib.md5(payload).digest() + struct.pack('<I',0)
        pck.write_bytes(header + payload + struct.pack('<I',1) + entry)
        value = AUDIT.pck_index(pck)
        self.assertEqual(value['files']['res://assets/runtime.cfg']['sha256'], hashlib.sha256(payload).hexdigest())
        damaged = bytearray(pck.read_bytes()); damaged[112] ^= 1; pck.write_bytes(damaged)
        with self.assertRaises(ValueError): AUDIT.pck_index(pck)
        pck.write_bytes(b'GDPC' + struct.pack('<I',99))
        with self.assertRaises(ValueError): AUDIT.pck_index(pck)

if __name__ == '__main__':
    unittest.main()
