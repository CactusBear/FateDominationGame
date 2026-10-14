"""Scoped Windows assembly observations; never enumerate system handles.

Compatible argv: scan PID fixture staging source | identity directory |
lock fixture file ready release. Authorization is supplied only by the owning
integrator via HERMES_ASSEMBLY_SCOPE/TOKEN/SCOPE_SHA256. No debug privilege,
foreign PID inspection, publication fallback, or production retry is provided.
"""
import ctypes as c
from ctypes import wintypes as w
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
import uuid

sys.dont_write_bytecode = True


class ProbeSafetyError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ProbeSafetyError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def safe(path):
    p = Path(path)
    require(p.is_absolute() and p.drive.upper() == 'E:' and '..' not in p.parts,
            'explicit physical E path required: ' + str(p))
    for ancestor in (p, *p.parents):
        if ancestor.exists():
            require(not ancestor.lstat().st_file_attributes & 0x400,
                    'reparse point refused: ' + str(ancestor))
    require(p.resolve() == p, 'physical path differs: ' + str(p))
    return p


def within(path, root):
    p, base = safe(path), safe(root)
    require(p.is_relative_to(base), 'path outside explicit scope: ' + str(p))
    return p


def validate_paths(scope, token, command, args):
    require(scope.get('version') == 1 and re.fullmatch(r'[0-9a-f]{32}', token or '')
            and scope.get('run_id') == token, 'old/invalid ownership token')
    generated = safe(scope['generated'])
    require(generated.name == 'generated' and generated.parent.name == 'isolated-' + token,
            'generated UUID does not match token')
    fixture = within(scope['fixture_root'], generated / 'f')
    source = within(scope['source_root'], generated / 'project')
    require(source == generated / 'project/data', 'source must be exact frozen data root')
    require(safe(scope['engine']) == generated / 'Godot.exe', 'foreign engine path')
    if command == 'scan':
        require(len(args) == 3, 'scan requires fixture/staging/source')
        root, stage, supplied_source = map(safe, args)
        within(root, fixture)
        within(stage, root)
        require(stage != root and supplied_source == source, 'invalid stage/source scope')
        return root, stage, source
    if command == 'identity':
        require(len(args) == 1, 'identity requires directory')
        return (within(args[0], fixture),)
    if command == 'lock':
        require(len(args) == 4, 'lock requires fixture/file/ready/release')
        root = within(args[0], fixture)
        values = [within(p, root) for p in args[1:]]
        require(len(set(values)) == 3 and all(p != root for p in values), 'lock paths overlap')
        return (root, *values)
    raise ProbeSafetyError('unsupported command')


def validate_caller(scope, requested_pid, caller, owner):
    require(type(requested_pid) is int and requested_pid > 0 and requested_pid == caller['pid'],
            'scan may only inspect its direct owning Godot parent PID')
    require(caller['parent'] == scope['owner_pid'] and owner['pid'] == scope['owner_pid']
            and owner['creation'] == scope['owner_creation'], 'foreign/stale owner PID')
    require(Path(caller['image']) == safe(scope['engine']) and caller['in_job'] is True,
            'caller is not the current owned engine in a Job')
    return requested_pid


_api = None


def api():
    global _api
    if _api is not None:
        return _api
    require(os.name == 'nt', 'Windows native helper required')
    k = c.WinDLL('kernel32', use_last_error=True)
    nt = c.WinDLL('ntdll')
    signatures = {
        'CreateFileW': ([w.LPCWSTR, w.DWORD, w.DWORD, w.LPVOID, w.DWORD, w.DWORD, w.HANDLE], w.HANDLE),
        'CloseHandle': ([w.HANDLE], w.BOOL),
        'OpenProcess': ([w.DWORD, w.BOOL, w.DWORD], w.HANDLE),
        'DuplicateHandle': ([w.HANDLE, w.HANDLE, w.HANDLE, c.POINTER(w.HANDLE), w.DWORD, w.BOOL, w.DWORD], w.BOOL),
        'GetCurrentProcess': ([], w.HANDLE),
        'GetFileType': ([w.HANDLE], w.DWORD),
        'GetFinalPathNameByHandleW': ([w.HANDLE, w.LPWSTR, w.DWORD, w.DWORD], w.DWORD),
        'MoveFileW': ([w.LPCWSTR, w.LPCWSTR], w.BOOL),
        'QueryFullProcessImageNameW': ([w.HANDLE, w.DWORD, w.LPWSTR, c.POINTER(w.DWORD)], w.BOOL),
        'GetProcessTimes': ([w.HANDLE, c.POINTER(w.FILETIME), c.POINTER(w.FILETIME), c.POINTER(w.FILETIME), c.POINTER(w.FILETIME)], w.BOOL),
        'IsProcessInJob': ([w.HANDLE, w.HANDLE, c.POINTER(w.BOOL)], w.BOOL),
    }
    for name, (args, restype) in signatures.items():
        getattr(k, name).argtypes, getattr(k, name).restype = args, restype
    nt.NtQueryInformationProcess.argtypes = [w.HANDLE, w.ULONG, w.LPVOID, w.ULONG, c.POINTER(w.ULONG)]
    nt.NtQueryInformationProcess.restype = c.c_long
    _api = k, nt
    return _api


def process_identity(pid):
    k, nt = api()
    handle = k.OpenProcess(0x400 | 0x1000, False, pid)
    if not handle:
        raise c.WinError(c.get_last_error())
    try:
        class Basic(c.Structure):
            _fields_ = [('reserved', c.c_void_p), ('peb', c.c_void_p),
                        ('reserved2', c.c_void_p * 2), ('pid', c.c_size_t), ('parent', c.c_size_t)]
        basic = Basic()
        status = nt.NtQueryInformationProcess(handle, 0, c.byref(basic), c.sizeof(basic), None)
        require(status == 0, 'cannot establish process ancestry')
        creation, exit_time, kernel, user = (w.FILETIME() for _ in range(4))
        if not k.GetProcessTimes(handle, c.byref(creation), c.byref(exit_time), c.byref(kernel), c.byref(user)):
            raise c.WinError(c.get_last_error())
        name = c.create_unicode_buffer(32768)
        size = w.DWORD(len(name))
        if not k.QueryFullProcessImageNameW(handle, 0, name, c.byref(size)):
            raise c.WinError(c.get_last_error())
        in_job = w.BOOL()
        if not k.IsProcessInJob(handle, None, c.byref(in_job)):
            raise c.WinError(c.get_last_error())
        return {'pid':pid, 'parent':basic.parent, 'creation':str((creation.dwHighDateTime << 32) | creation.dwLowDateTime),
                'image':name.value, 'in_job':bool(in_job.value)}
    finally:
        k.CloseHandle(handle)


def native(path):
    return '\\\\?\\' + str(Path(path)).replace('/', '\\')


BAD = c.c_void_p(-1).value


def access(path, desired):
    k, _ = api()
    handle = k.CreateFileW(native(safe(path)), desired, 7, None, 3, 0x02000000, None)
    error = c.get_last_error() if handle == BAD else 0
    if handle != BAD:
        k.CloseHandle(handle)
    return error


class HandleEntry(c.Structure):
    _fields_ = [('handle', c.c_void_p), ('handle_count', c.c_size_t), ('pointer_count', c.c_size_t),
                ('access', w.ULONG), ('type', w.ULONG), ('attributes', w.ULONG), ('reserved', w.ULONG)]


def process_handles(handle):
    """ProcessHandleInformation (51), not SystemExtendedHandleInformation (64)."""
    _, nt = api()
    size = 65536
    for _ in range(8):
        buf = c.create_string_buffer(size)
        needed = w.ULONG()
        status = nt.NtQueryInformationProcess(handle, 51, buf, size, c.byref(needed))
        if status == 0:
            count = c.c_size_t.from_buffer(buf).value
            require(2*c.sizeof(c.c_size_t) + count*c.sizeof(HandleEntry) <= size,
                    'native handle count exceeds snapshot')
            return [HandleEntry.from_buffer_copy(buf, 2*c.sizeof(c.c_size_t) + i*c.sizeof(HandleEntry))
                    for i in range(count)]
        require(status in {-1073741820, -1073741789}, 'process handle query failed: ' + hex(status & 0xffffffff))
        size = max(size*2, needed.value + 65536)
    raise ProbeSafetyError('bounded process handle query exhausted')


def handles(pid, root, source):
    k, _ = api()
    sentinel = k.CreateFileW(native(root), 0x80, 7, None, 3, 0x02000000, None)
    require(sentinel != BAD, 'cannot open owned fixture sentinel')
    try:
        file_type = next((e.type for e in process_handles(k.GetCurrentProcess()) if e.handle == sentinel), None)
        require(file_type is not None, 'sentinel File object type unavailable')
    finally:
        k.CloseHandle(sentinel)
    ph = k.OpenProcess(0x400 | 0x40, False, pid)
    if not ph:
        raise c.WinError(c.get_last_error())
    rows, denied = [], []
    try:
        entries = process_handles(ph)
        for entry in entries:
            if entry.type != file_type:
                continue
            dup = w.HANDLE()
            if not k.DuplicateHandle(ph, entry.handle, k.GetCurrentProcess(), c.byref(dup), 0, False, 2):
                denied.append({'handle':entry.handle, 'error':c.get_last_error()})
                continue
            try:
                if k.GetFileType(dup) != 1:
                    continue
                name = c.create_unicode_buffer(32768)
                length = k.GetFinalPathNameByHandleW(dup, name, len(name), 0)
                if not length or length >= len(name):
                    denied.append({'handle':entry.handle, 'path_query_error':c.get_last_error()})
                    continue
                path = Path(name.value.removeprefix('\\\\?\\'))
                for label, base in [('fixture', root), ('source', source)]:
                    if path.is_relative_to(base):
                        safe(path)
                        rows.append({'handle':entry.handle, 'access':entry.access, 'path':path.as_posix(), 'scope':label})
                        break
            finally:
                k.CloseHandle(dup)
    finally:
        k.CloseHandle(ph)
    return {'matching_handles':rows, 'duplicate_failures':denied, 'owned_handle_count':len(entries),
            'handle_query':'NtQueryInformationProcess/ProcessHandleInformation', 'inspected_pid':pid}


def scan(pid, root, stage, source):
    k, _ = api()
    result = {'pid':pid, **handles(pid, root, source), 'stage_exists':stage.exists(),
              'parent_identity':[str(stage.parent.stat()[i]) for i in (1, 2)],
              'stage_delete_error':access(stage, 0x10000), 'blocked_files':[]}
    # Explicit no-follow traversal; reject directory links before enumerating them.
    queue = [stage]
    while queue:
        directory = safe(queue.pop())
        for child in directory.iterdir():
            p = within(child, stage)
            error = access(p, 0x10000)
            if error:
                result['blocked_files'].append({'path':p.relative_to(stage).as_posix(), 'delete_error':error,
                                               'read_error':access(p, 0x80000000), 'write_error':access(p, 0x40000000)})
            if p.is_dir():
                queue.append(p)
    disposable = root / ('native-disposable-' + uuid.uuid4().hex)
    disposable.mkdir()
    held = disposable / 'held'
    held.write_bytes(b'probe')
    moved = disposable.with_name(disposable.name + '-moved')
    lock = k.CreateFileW(native(held), 0x80000000, 3, None, 3, 0, None)
    require(lock != BAD, 'controlled lock failed')
    try:
        ok = k.MoveFileW(native(disposable), native(moved))
        error = c.get_last_error() if not ok else 0
    finally:
        k.CloseHandle(lock)
    result['controlled_native_rename'] = {'ok':bool(ok), 'win32_error':error, 'api':'MoveFileW',
                                           'share_flags':3, 'access':0x80000000}
    if ok:
        held, disposable = moved / 'held', moved
    held.unlink()
    disposable.rmdir()
    return result


def lock_file(root, file, ready, release):
    k, _ = api()
    require(not ready.exists() and not release.exists(), 'stale lock receipts')
    handle = k.CreateFileW(native(file), 0x80000000, 3, None, 3, 0, None)
    require(handle != BAD, 'owned lock open failed')
    try:
        ready.write_text(json.dumps({'pid':os.getpid(), 'share_flags':3, 'access':0x80000000}), encoding='utf-8')
        deadline = time.monotonic() + 15
        while not release.exists() and time.monotonic() < deadline:
            time.sleep(.01)
        require(release.exists(), 'owned lock release deadline exceeded')
    finally:
        k.CloseHandle(handle)
    return {'released':True, 'pid':os.getpid()}


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    require(args and args[0] in {'scan','identity','lock'}, 'explicit command required')
    scope_path = safe(os.environ.get('HERMES_ASSEMBLY_SCOPE', ''))
    require(digest(scope_path) == os.environ.get('HERMES_ASSEMBLY_SCOPE_SHA256'), 'scope bytes changed')
    scope = json.loads(scope_path.read_text(encoding='utf-8'))
    command = args.pop(0)
    pid = int(args.pop(0)) if command == 'scan' else None
    paths = validate_paths(scope, os.environ.get('HERMES_ASSEMBLY_TOKEN'), command, args)
    within(scope_path, scope['generated'])
    require(digest(__file__) == scope['helper_sha256'], 'helper bytes differ from frozen authorization')
    caller_pid = process_identity(os.getpid())['parent']
    caller = process_identity(caller_pid)
    owner = process_identity(scope['owner_pid'])
    validate_caller(scope, caller_pid if pid is None else pid, caller, owner)
    if scope.get('engine_sha256'):
        require(digest(scope['engine']) == scope['engine_sha256'], 'owned engine bytes changed')
    if command == 'scan':
        result = scan(pid, *paths)
    elif command == 'identity':
        result = [str(paths[0].stat()[i]) for i in (1, 2)]
    else:
        result = lock_file(*paths)
    audit = within(Path(scope['generated']) / 'native-audit', scope['generated'])
    audit.mkdir(exist_ok=True)
    receipt = {'run_id':scope['run_id'], 'command':command, 'argv':sys.argv,
               'helper_pid':os.getpid(), 'caller':caller, 'owner':owner, 'result':result, 'exit':0}
    (audit / (command + '-' + uuid.uuid4().hex + '.json')).write_text(json.dumps(receipt, ensure_ascii=False), encoding='utf-8')
    if command != 'lock':
        print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ProbeSafetyError, OSError, ValueError, KeyError) as exc:
        print('ASSEMBLY_PROBE_REJECT ' + str(exc), file=sys.stderr)
        raise SystemExit(2)