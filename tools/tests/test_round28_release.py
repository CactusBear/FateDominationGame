"""round28 生产发行工具回归；不启动 Godot。"""
import hashlib
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'release'))
from package_audit import pck_index, audit
from path_safety import new_output
from freeze_prepare import prepare
from release_contract import select


def pack(path, files):
    payload = b''
    rows = b''
    for name, content in files.items():
        raw = name.encode()
        raw += b'\0' * (-len(raw) % 4)
        rows += struct.pack('<I', len(raw)) + raw
        rows += struct.pack('<QQ', 96 + len(payload), len(content))
        rows += hashlib.md5(content).digest() + struct.pack('<I', 0)
        payload += content
    header = b'GDPC' + struct.pack('<IIII', 4, 4, 7, 2)
    header += struct.pack('<IQQ', 0, 0, 96 + len(payload))
    path.write_bytes(header.ljust(96, b'\0') + payload + struct.pack('<I', len(files)) + rows)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.project = self.root / 'project'
        self.project.mkdir()
        (self.project / 'project.godot').write_text('[application]\nconfig/name="test"\n')
        (self.project / 'export_presets.cfg').write_text('[preset.0]\nname="client"\nplatform="Windows Desktop"\ndedicated_server=false\n[preset.0.options]\nbinary_format/embed_pck=false\n')
        (self.project / 'data').mkdir()
        (self.project / 'data/a.json').write_text('{}')
        (self.project / 'release_contract.json').write_text(json.dumps({'version':1,'targets':[{'preset':'client','platform':'windows','role':'client','executable':'game.exe','runtime_files':[]}]}))
        self.package = self.root / 'package'
        self.package.mkdir()
        (self.package / 'game.exe').write_bytes(b'MZcandidate')
        (self.package / 'data').mkdir()
        (self.package / 'data/a.json').write_text('{}')
    def tearDown(self):
        self.temp.cleanup()
    def test_empty_pck_rejected(self):
        pack(self.package / 'game.pck', {})
        with self.assertRaises(ValueError):
            pck_index(self.package / 'game.pck')
    def test_real_index_and_corrupt_md5(self):
        p = self.package / 'game.pck'
        pack(p, {'project.binary':b'actual'})
        self.assertEqual(pck_index(p)['file_count'], 1)
        raw = bytearray(p.read_bytes()); raw[96] ^= 1; p.write_bytes(raw)
        with self.assertRaises(ValueError): pck_index(p)
    def test_client_dev_resource_rejected(self):
        pack(self.package / 'game.pck', {'addons/godot_ai/runtime/game_helper.gd':b'dev'})
        self.assertEqual(audit(self.project, self.package, self.root / 'audit.json', 'client'), 2)
    def test_no_data_rejected(self):
        (self.project / 'data/a.json').unlink()
        pack(self.package / 'game.pck', {'project.binary':b'ok'})
        with self.assertRaises(ValueError):
            audit(self.project, self.package, self.root / 'audit.json', 'client')
    def test_missing_package_rejected(self):
        self.assertEqual(audit(self.project, self.root / 'absent', self.root / 'audit.json', 'client'), 2)
    def test_explicit_allowed_root(self):
        value = new_output(self.root / 'new', allowed_root=self.root)
        self.assertEqual(value, self.root / 'new')
        with self.assertRaises(ValueError): new_output(self.root.parent / 'outside', allowed_root=self.root)
    def test_explicit_minimal_freeze(self):
        for name in ('icon.svg', 'icon.svg.import'):
            (self.project / name).write_text('')
        (self.project / 'scripts').mkdir()
        (self.project / 'scripts/test').mkdir()
        (self.project / 'scripts/test/unused.gd').write_text('extends Node')
        value = prepare(self.project, self.root / 'freeze', self.root / 'freeze.json',
                        preset='client', role='client', executable='game.exe', runtime_files=[], allowed_root=self.root)
        self.assertNotIn('scripts/test/unused.gd', value['files'])
        self.assertEqual(value['classification'], 'CANDIDATE_SOURCE_NOT_LOCKED')
    def declare(self, role):
        text = (self.project / 'export_presets.cfg').read_text().replace('dedicated_server=false', 'dedicated_server=' + ('false' if role == 'client' else 'true'))
        (self.project / 'export_presets.cfg').write_text(text)
        (self.project / 'release_contract.json').write_text(json.dumps({'version':1,'targets':[{'preset':'client','platform':'windows','role':role,'executable':'game.exe','runtime_files':[]}]}))
        if role == 'signaling':
            (self.project / 'project.godot').write_text('[network]\nsignaling_only=true\n')
            (self.package / 'data/a.json').unlink()
            (self.package / 'data').rmdir()
    def test_three_role_matrix(self):
        for role in ('client','server','signaling'):
            self.declare(role)
            pack(self.package / 'game.pck', {'project.binary':b'actual config'})
            self.assertEqual(audit(self.project, self.package, self.root / (role + '.json'), 'client', role=role), 0)
    def test_signaling_rules_rejected(self):
        self.declare('signaling')
        pack(self.package / 'game.pck', {'project.binary':b'actual config','scripts/match/rule_state.gdc':b'rules'})
        self.assertEqual(audit(self.project, self.package, self.root / 'signal.json', 'client', role='signaling'), 2)
    def test_signaling_autoload_rejected(self):
        self.declare('signaling')
        with (self.project / 'project.godot').open('a') as stream: stream.write('[autoload]\nRules="*res://rules.gd"\n')
        with self.assertRaises(ValueError): select(self.project, 'client', role='signaling')
    def test_missing_contract_rejected(self):
        (self.project / 'release_contract.json').unlink()
        with self.assertRaises(ValueError): select(self.project, 'client')
    def test_empty_executable_rejected(self):
        (self.package / 'game.exe').write_bytes(b'')
        pack(self.package / 'game.pck', {'project.binary':b'actual config'})
        self.assertEqual(audit(self.project, self.package, self.root / 'empty-exe.json', 'client'), 2)
    def test_packed_helper_autoload_rejected(self):
        pack(self.package / 'game.pck', {'project.binary':b'_mcp_game_helper'})
        self.assertEqual(audit(self.project, self.package, self.root / 'helper.json', 'client'), 2)
    def test_native_dependency_missing_rejected(self):
        descriptor = 'addons/native/plugin.gdextension'
        (self.project / 'addons/native').mkdir(parents=True)
        content = b'[libraries]\nwindows.x86_64="res://addons/native/native.dll"\n'
        (self.project / descriptor).write_bytes(content)
        (self.project / 'addons/native/native.dll').write_bytes(b'native library')
        pack(self.package / 'game.pck', {'project.binary':b'actual config', descriptor:content})
        self.assertEqual(audit(self.project, self.package, self.root / 'native.json', 'client'), 2)

if __name__ == '__main__': unittest.main()
