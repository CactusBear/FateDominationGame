"""Round67 wire observer safety preflight; NOT a validated live observer.

Never starts/attaches a process, reads socket buffers, opens a network socket,
installs a breakpoint, decodes a packet or executes the recovery runner.
Exit 2 is an accurate validation blocker, never sourcePASS.
"""
from __future__ import annotations
import sys
sys.dont_write_bytecode = True
import argparse
import ctypes as c
from ctypes import wintypes as w
import hashlib
import json
from pathlib import Path
import struct
import unittest

PROJECT = Path(__file__).resolve().parents[2]
ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
ENGINE_SHA = 'ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424'
COMMIT = 'ed1daf0bf001b61586d9930840f2f1394092c079'
APIS = ('sendto', 'recvfrom', 'send', 'recv', 'WSASendTo', 'WSARecvFrom',
        'socket', 'bind', 'getsockname', 'closesocket', 'WSAGetLastError')
READONLY = (
    'scripts/net/session/lobby_session.gd',
    'scripts/net/transport/enet_transport.gd',
    'scripts/net/transport/recovery_net_probe.gd',
    'scripts/net/server/server_gateway.gd',
    'scripts/net/server/server_room_worker.gd',
    'scripts/net/server/recovery_save_diagnostic.gd',
    'scripts/net/validation/room_data_validation_worker.gd',
    'scripts/system/global/load_game.gd',
    'tests/net_server_gateway_restart_test.gd',
    'tools/diagnostics/round61_restart_agent_runner.py',
    'tools/diagnostics/round63_observer_lock_contract.py',
    'tools/diagnostics/assembly_publish_failure_capture.py',
    'tools/diagnostics/native_cold_import_debug.py',
)


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


class PE:
    """Bounded PE32+ import/export reader. Reads executable files, not packets."""
    def __init__(self, path):
        self.data = Path(path).read_bytes()
        self.sections = []
        if self.data[:2] != b'MZ':
            raise ValueError('not PE')
        pe = self.u32(60)
        if self.slice(pe, 4) != b'PE\0\0':
            raise ValueError('invalid PE signature')
        if self.u16(pe + 4) != 0x8664:
            raise ValueError('requires AMD64')
        count, size = self.u16(pe + 6), self.u16(pe + 20)
        opt = pe + 24
        if self.u16(opt) != 0x20b or size < 240:
            raise ValueError('requires PE32+')
        self.image_base = self.u64(opt + 24)
        self.headers = self.u32(opt + 60)
        self.directories = [struct.unpack('<II', self.slice(opt + 112 + i * 8, 8)) for i in range(16)]
        for i in range(count):
            p = opt + size + i * 40
            vs, va, rs, raw = struct.unpack('<IIII', self.slice(p + 8, 16))
            self.sections.append((va, vs, raw, rs))

    def slice(self, pos, size):
        if pos < 0 or size < 0 or pos + size > len(self.data):
            raise ValueError('PE out of bounds')
        return self.data[pos:pos + size]

    def u16(self, p): return struct.unpack('<H', self.slice(p, 2))[0]
    def u32(self, p): return struct.unpack('<I', self.slice(p, 4))[0]
    def u64(self, p): return struct.unpack('<Q', self.slice(p, 8))[0]

    def offset(self, rva, size=1):
        if 0 <= rva < self.headers and rva + size <= self.headers:
            self.slice(rva, size)
            return rva
        for va, vs, raw, rs in self.sections:
            delta = rva - va
            if 0 <= delta and delta + size <= rs:
                self.slice(raw + delta, size)
                return raw + delta
        raise ValueError('RVA not backed by file')

    def string(self, rva):
        pos = self.offset(rva)
        limit = min(len(self.data), pos + 1024)
        end = self.data.find(b'\0', pos, limit)
        if end < 0:
            raise ValueError('unterminated PE name')
        return self.slice(pos, end - pos).decode('ascii')

    def imports(self):
        rva, size = self.directories[1]
        if not rva: return []
        rows = []
        for i in range(size // 20):
            oft, _, _, name, ft = struct.unpack('<IIIII', self.slice(self.offset(rva + 20*i, 20), 20))
            if not any((oft, name, ft)): return rows
            dll = self.string(name)
            for j in range(65536):
                value = self.u64(self.offset((oft or ft) + 8*j, 8))
                if not value: break
                symbol = '#' + str(value & 0xffff) if value >> 63 else self.string(value + 2)
                rows.append({'dll': dll, 'name': symbol, 'iat_slot_rva': hex(ft + 8*j),
                             'import_lookup_rva': hex((oft or ft) + 8*j)})
            else: raise ValueError('unterminated import thunk')
        raise ValueError('unterminated import directory')

    def exports(self):
        rva, size = self.directories[0]
        if not rva: return {}
        p = self.offset(rva, 40)
        count, functions, names, ordinals = self.u32(p+24), self.u32(p+28), self.u32(p+32), self.u32(p+36)
        out = {}
        for i in range(count):
            name = self.string(self.u32(self.offset(names + 4*i, 4)))
            ordinal = self.u16(self.offset(ordinals + 2*i, 2))
            address = self.u32(self.offset(functions + 4*ordinal, 4))
            out[name] = {'rva': address, 'forwarder': self.string(address) if rva <= address < rva+size else None}
        return out


def local_exports():
    """Same real GetProcAddress owner-module method as round63; LOCAL only."""
    k = c.WinDLL('kernel32', use_last_error=True)
    k.GetProcAddress.argtypes = [w.HMODULE, c.c_char_p]
    k.GetProcAddress.restype = c.c_void_p
    k.GetModuleHandleExW.argtypes = [w.DWORD, c.c_void_p, c.POINTER(w.HMODULE)]
    k.GetModuleHandleExW.restype = w.BOOL
    k.GetModuleFileNameW.argtypes = [w.HMODULE, w.LPWSTR, w.DWORD]
    k.GetModuleFileNameW.restype = w.DWORD
    libraries = [('WSOCK32.dll', c.WinDLL('wsock32', use_last_error=True)),
                 ('WS2_32.dll', c.WinDLL('ws2_32', use_last_error=True))]
    rows = []
    for requested_dll, name in [(dll, name) for dll, _ in libraries for name in APIS]:
        library = next(lib for dll, lib in libraries if dll == requested_dll)
        address = k.GetProcAddress(library._handle, name.encode('ascii'))
        if not address:
            rows.append({'requested_dll': requested_dll, 'name': name, 'available': False})
            continue
        module = w.HMODULE()
        if not k.GetModuleHandleExW(6, address, c.byref(module)):
            raise c.WinError(c.get_last_error())
        path = c.create_unicode_buffer(32768)
        if not k.GetModuleFileNameW(module, path, len(path)):
            raise c.WinError(c.get_last_error())
        pe = PE(path.value)
        export = pe.exports().get(name)
        rva = address - module.value
        disk = pe.slice(pe.offset(rva, 8), 8)
        loaded = c.string_at(address, 8)
        rows.append({'requested_dll': requested_dll, 'name': name, 'available': True, 'module': path.value,
                     'module_sha256': sha(path.value), 'local_address': hex(address),
                     'actual_owner_module_rva': hex(rva),
                     'disk_export_matches_GetProcAddress': bool(export and export['rva'] == rva and not export['forwarder']),
                     'local_loaded_vs_disk_code8_equal': loaded == disk,
                     'code8_sha256': hashlib.sha256(loaded).hexdigest(),
                     'owned_remote_address_verified': False})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True, help='existing self-owned downloaded source root under E:/scratch/isolated-UUID')
    args = parser.parse_args()
    root = args.root.resolve()
    import re
    if root.parent != Path('E:/scratch').resolve() or not re.fullmatch(r'isolated-[a-f0-9]{32}', root.name):
        raise ValueError('requires declared E scratch UUID root')
    if any(p.is_symlink() or p.is_junction() for p in [root, *root.parents]):
        raise ValueError('reparse scope refused')
    if (root/'report.json').exists():
        raise ValueError('report already exists; no overwrite/retry')
    if sha(ENGINE) != ENGINE_SHA:
        raise ValueError('host hash differs')
    before = {p: sha(PROJECT/p) for p in READONLY}
    imports = PE(ENGINE).imports()
    downloads = json.loads((root/'downloads.json').read_text(encoding='utf-8'))
    for row in downloads:
        if 'sha256' in row:
            if not row['url'].startswith('https://raw.githubusercontent.com/godotengine/godot/'+COMMIT+'/') or sha(root/'source'/row['file']) != row['sha256']:
                raise ValueError('download identity mismatch')
    source_index = {p.relative_to(root).as_posix(): sha(p) for p in (root/'source').rglob('*') if p.is_file()}
    exports = local_exports()
    report = {
        'status': 'TOOLBLOCK_WIRE_OBSERVER_NOT_VALIDATED', 'exit_code': 2,
        'sourcePASS': False, 'releasePASS': False, 'native_disconnect_cause': 'unknown',
        'engine': {'path': ENGINE.as_posix(), 'sha256': sha(ENGINE)},
        'official_commit': COMMIT, 'official_source_hashes': source_index, 'downloads': downloads,
        'observer_preflight_source_sha256': sha(__file__),
        'iat_kind': 'on-disk import descriptors/lookup thunks and IAT slot RVAs; NOT live resolved IAT',
        'winsock_imports': [r for r in imports if r['dll'].lower() in {'ws2_32.dll', 'wsock32.dll'}],
        'named_network_imports': [r for r in imports if r['name'] in APIS],
        'local_export_verification': exports,
        'verified_network_source_path': ['thirdparty/enet/enet_godot.cpp:584-647', 'drivers/windows/net_socket_winsock.cpp:421-499'],
        'existing_export_debugger_method': 'round63_observer_lock_contract.py:168-180 verifies actual local owner module and remote code8 before arming; not executed or modified here',
        'missing_validation_gates': [
            'No live self-owned remote export/IAT verification or network entry/return breakpoint implementation exercised.',
            'No registered self-owned socket handle lifetime/local+remote loopback tuple/creation-time filter exercised.',
            'No recvfrom successful-return buffer length/source-address pairing or same-thread API-error capture exercised.',
            'No ReadProcessMemory header-only range policy validated: SEND data must never be fetched, not merely redacted after a full buffer read.',
            'No checksum configuration proof: checksum adds four bytes without a datagram flag; guessing zero risks misclassifying checksum as a command.',
            'Compressed command stream must be unknown, not decompressed (which would read business-bearing bytes); gaps forbid an absence-of-DISCONNECT claim.',
            'No multi-command/SEND-length/fragment/truncation safe-skip parser implemented or validated.',
            'Natural handshake, explicit close and declared stop-service negative cases each remain unrun.',
            'No pause-duration/overhead measurement or debugger-induced-timeout control exists for this wire observer.',
        ],
        'new_owned_processes': [], 'new_owned_job0': 'not applicable: no process created',
        'new_save_recover_runs': 0, 'independent_enet_case_runs': 0,
        'safe_control_records': [], 'wire_observation_performed': False,
        'recovery_scene_exit': None, 'recovery_scene_exit_reason': 'not started because preflight gate failed',
        'debug_attach_calls': 0, 'packet_payload_bytes_read': 0, 'socket_opens': 0,
        'read_only_hashes_before': before,
        'read_only_hashes_after': {p: sha(PROJECT/p) for p in READONLY},
        'production_patch_proposed': False,
    }
    report['read_only_unchanged'] = report['read_only_hashes_before'] == report['read_only_hashes_after']
    (root/'executor.py').write_bytes(Path(__file__).read_bytes())
    out = root/'report.json'
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'report': out.as_posix(), 'sha256': sha(out), 'status': report['status'],
                      'readonly_unchanged': report['read_only_unchanged'], 'runs': 0}, ensure_ascii=False))
    return 2


class EvidenceTests(unittest.TestCase):
    def test_actual_engine_imports(self):
        self.assertEqual(sha(ENGINE), ENGINE_SHA)
        rows = PE(ENGINE).imports()
        names = {r['name'] for r in rows if r['dll'].lower() == 'wsock32.dll'}
        self.assertTrue({'sendto', 'recvfrom', 'WSAGetLastError'} <= names)
        self.assertFalse({'WSASendTo', 'WSARecvFrom'} & {r['name'] for r in rows})

    def test_actual_system_exports(self):
        rows = local_exports()
        for row in rows:
            if not row['available']:
                self.assertEqual(row['requested_dll'], 'WSOCK32.dll')
                self.assertIn(row['name'], {'WSASendTo', 'WSARecvFrom'})
                continue
            self.assertTrue(row['disk_export_matches_GetProcAddress'])
            self.assertTrue(row['local_loaded_vs_disk_code8_equal'])
            self.assertFalse(row['owned_remote_address_verified'])

    def test_bounds_are_rejected(self):
        pe = PE(ENGINE)
        with self.assertRaises(ValueError): pe.slice(-1, 1)
        with self.assertRaises(ValueError): pe.offset(0xffffffff, 8)
        with self.assertRaises(ValueError): pe.slice(len(pe.data), 1)


if __name__ == '__main__':
    if sys.argv[1:] == ['--self-test']:
        unittest.main(argv=[sys.argv[0]])
    else:
        raise SystemExit(main())
