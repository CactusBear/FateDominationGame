"""One scene, explicit E-drive isolation and evidence; no game/round coupling.

Budgets are monitored ceilings, not an OS disk quota. Never change global TEMP.
Freeze is an explicit dependency allowlist, not an automatic project snapshot.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import time
import uuid


class SafetyError(ValueError):
    pass


def no_links(path):
    """Reject every existing ancestor reparse point, including Windows junctions."""
    path = Path(os.path.abspath(path))
    for part in (path, *path.parents):
        try:
            info = part.lstat()
        except FileNotFoundError:
            # Missing/atomically removed paths are allowed; still check ancestors.
            continue
        # Do not swallow permission/unknown errors or follow a link to inspect it.
        if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 0x400:
            raise SafetyError('link/reparse point: ' + str(part))
    return path


def physical_e(path):
    path = no_links(path).resolve(strict=True)
    if path.drive.upper() != 'E:':
        raise SafetyError('physical E drive required: ' + str(path))
    return path


def contained(path, root):
    path = no_links(path).resolve(strict=True)
    root = no_links(root).resolve(strict=True)
    if path == root or not path.is_relative_to(root):
        raise SafetyError('not a strict child of approved root: ' + str(path))
    return path


def unique_fields(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate field: ' + key)
        result[key] = value
    return result


def parse_result(line):
    payload = re.sub(r'^\s*RESULT\b\s*', '', line, count=1)
    decoder = json.JSONDecoder(object_pairs_hook=unique_fields,
                               parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))
    if payload.startswith('{'):
        result = decoder.decode(payload)
    else:
        pairs = []
        suite = re.match(r'([A-Za-z_][A-Za-z_0-9.-]*)\s+(?=[A-Za-z_][A-Za-z_0-9]*\s*=)', payload)
        if suite:
            pairs.append(('suite', suite[1]))
            payload = payload[suite.end():]
        while payload:
            match = re.match(r'([A-Za-z_][A-Za-z_0-9]*)\s*=\s*', payload)
            if not match:
                raise ValueError('invalid RESULT field')
            value, end = decoder.raw_decode(payload[match.end():])
            pairs.append((match[1], value))
            tail = payload[match.end() + end:]
            if tail and not tail[0].isspace():
                raise ValueError('missing separator')
            payload = tail.lstrip()
        result = unique_fields(pairs)
    if not isinstance(result, dict) or type(result.get('checks')) is not int or result['checks'] <= 0:
        raise ValueError('checks must be a positive integer')
    if not isinstance(result.get('failures'), list):
        raise ValueError('failures must be an array')
    return result


def analyze(stdout, stderr, exit_code):
    lines = stdout.splitlines() + stderr.splitlines()
    results = [line for line in stdout.splitlines() if re.match(r'^\s*RESULT\b', line)]
    reasons = []
    parsed = None
    if exit_code != 0:
        reasons.append('nonzero_exit')
    if len(results) != 1:
        reasons.append('expected_one_stdout_result')
    else:
        try:
            parsed = parse_result(results[0])
            if parsed['failures']:
                reasons.append('result_failures')
        except ValueError as exc:
            reasons.append('invalid_result: ' + str(exc))
    if any(re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:|^\s*FAIL\b', x) for x in lines):
        reasons.append('engine_error')
    checks = [x for x in lines if re.match(r'^\s*CHECK\b', x)]
    check_ids = set()
    for line in checks:
        tokens = line.split()[1:]
        values = []
        if tokens and tokens[0] in {'true', 'false'}:
            values.append(tokens.pop(0))
        if tokens and tokens[-1] in {'true', 'false'}:
            values.append(tokens.pop())
        if not values or len(set(values)) != 1 or not tokens:
            reasons.append('invalid_check')
        if 'false' in values:
            reasons.append('check_false')
        # Only an explicit numeric prefix is an ID. Loop labels may repeat.
        number = re.fullmatch(r'(?:#([0-9]+)|\[([0-9]+)\]|([0-9]+))', tokens[0]) if tokens else None
        if number:
            check_id = int(next(x for x in number.groups() if x is not None))
            if check_id in check_ids:
                reasons.append('duplicate_check_id')
            check_ids.add(check_id)
    if checks and parsed and len(checks) != parsed['checks']:
        reasons.append('check_count_mismatch')
    return {'passed': not reasons, 'reasons': reasons, 'result': parsed}


EXCLUDED = {'.git', '.godot', '__pycache__', 'test', 'runtime_reports', 'reports',
            'scratch', 'window', 'release', 'exports', 'node_modules'}


def source_files(project, includes):
    """Return explicit dependencies, refuse links, skip historical/cache products."""
    files = set()
    for name in includes:
        rel = Path(name)
        if rel.is_absolute() or '..' in rel.parts or any(x in EXCLUDED for x in rel.parts):
            raise SafetyError('unsafe/excluded include: ' + name)
        source = contained(project / rel, project)
        candidates = [source]
        if source.is_dir():
            if 'tests' in rel.parts:
                raise SafetyError('select target test files, not the whole tests directory')
            candidates = []
            for directory, dirs, names in os.walk(source, followlinks=False):
                no_links(directory)
                dirs[:] = [x for x in dirs if x not in EXCLUDED]
                for child in dirs:
                    no_links(Path(directory) / child)
                candidates.extend(Path(directory) / x for x in names)
        for candidate in candidates:
            no_links(candidate)
            if candidate.suffix in {'.log', '.tmp', '.pyc'}:
                continue
            if candidate.is_file():
                files.add(candidate.relative_to(project))
    return sorted(files)


def tree_bytes(root):
    total = 0
    for directory, dirs, names in os.walk(root, followlinks=False):
        no_links(directory)
        for name in dirs + names:
            no_links(Path(directory) / name)
        for name in names:
            try:
                total += (Path(directory) / name).stat().st_size
            except FileNotFoundError:
                # Live engine atomic rename/unlink is normal during import.
                continue
    return total


def delete_owned(root, owner):
    """Only our recorded generated child tree, with pre-scan before any deletion."""
    root = contained(root, owner)
    tree_bytes(root)  # pre-scan rejects embedded junctions, no partial traversal
    receipt = no_links(owner / 'manifest.json')
    if not receipt.is_file():
        raise SafetyError('missing ownership receipt')
    record = json.loads(receipt.read_text(encoding='utf-8'), object_pairs_hook=unique_fields)
    token = record.get('run_id')
    if not isinstance(token, str) or not re.fullmatch(r'[a-f0-9]{32}', token):
        raise SafetyError('invalid ownership identity')
    if owner.name != 'isolated-' + token or root != owner / 'generated' or record.get('generated') != str(root):
        raise SafetyError('ownership target mismatch')
    processes = record.get('processes')
    if not isinstance(processes, list) or any(x.get('retained') or x.get('exited') is not True or x.get('active_owned_processes') != 0 for x in processes):
        raise SafetyError('owned process exit not proven')
    shutil.rmtree(root)
    if root.exists():
        raise SafetyError('cleanup did not remove generated tree')


PROBE_SCRIPT = r'''extends SceneTree
func _initialize():
    var args = OS.get_cmdline_user_args()
    var token = args[0]
    var role = args[1]
    var approved = args[2].replace("\\", "/") + "/"
    var actual = OS.get_user_data_dir().replace("\\", "/")
    print("ACTUAL_USER_PATH " + actual)
    if not actual.begins_with(approved):
        quit(27)
        return
    var f = FileAccess.open("user://" + token + "-" + role + ".txt", FileAccess.WRITE)
    if f == null:
        quit(21)
        return
    f.store_string(token)
    f.close()
    var receipt = JSON.stringify({"role":role,"pid":OS.get_process_id(),"path":OS.get_user_data_dir(),"token":token,"worker_pool_max_threads":ProjectSettings.get_setting("threading/worker_pool/max_threads")})
    var record = FileAccess.open("user://" + token + "-" + role + ".json", FileAccess.WRITE)
    if record == null:
        quit(24)
        return
    record.store_string(receipt)
    record.close()
    print("USER_PROBE " + receipt)
    if role == "main":
        var child = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://probe.gd", "--", token, "worker", args[2]])
        if child <= 0:
            quit(22)
            return
        print("OWNED_CHILD " + str(child))
        var start = Time.get_ticks_msec()
        while OS.is_process_running(child):
            if Time.get_ticks_msec() - start > 15000:
                OS.kill(child)
                quit(23)
                return
            OS.delay_msec(20)
        print("CHILD_EXITED " + str(child))
        var exit_code = OS.get_process_exit_code(child)
        print("CHILD_EXIT_CODE " + str(exit_code))
        if exit_code != 0:
            quit(25)
            return
        var worker_receipt = FileAccess.get_file_as_string("user://" + token + "-worker.json")
        if worker_receipt.is_empty():
            quit(26)
            return
        print("USER_PROBE " + worker_receipt)
    quit(0)
'''


# The report script contains no user:// write operation at all. Worker receipts
# use the prevalidated, owned E control directory because child stdout is not
# reliably inherited by Godot OS.create_process on Windows.
PROBE_TEMPLATE = r'''extends SceneTree
func _initialize():
    call_deferred("_probe")
func _probe():
    var args = OS.get_cmdline_user_args()
    var token = args[0]
    var role = args[1]
    var control = args[2]
    var phase = args[3]
    var actual = OS.get_user_data_dir()
    var environment = {}
    for key in ["APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "TMPDIR"]:
        environment[key] = OS.get_environment(key)
    var receipt = {"role":role, "pid":OS.get_process_id(), "path":actual, "token":token, "phase":phase, "environment":environment, "worker_pool_max_threads":ProjectSettings.get_setting("threading/worker_pool/max_threads", -1)}
__AUTHORIZED_WRITE__
    print("USER_PROBE " + JSON.stringify(receipt))
    if role == "worker":
        var record = FileAccess.open(control.path_join(token + "-worker-" + phase + ".json"), FileAccess.WRITE)
        if record == null:
            quit(24)
            return
        record.store_string(JSON.stringify(receipt))
        record.close()
        OS.delay_msec(200)  # finite real-time observation window for kernel PID identity
    else:
        var child_args = ["--headless", "--log-file", control.path_join(token + "-worker-" + phase + ".engine.log"), "--fixed-fps", "60", "--quit-after", "1800", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://probe.gd", "--", token, "worker", control, phase]
        if phase == "write":
            child_args.append(args[4])
        print("CHILD_COMMAND " + JSON.stringify([OS.get_executable_path()] + child_args))
        var child = OS.create_process(OS.get_executable_path(), child_args)
        if child <= 0:
            quit(22)
            return
        print("OWNED_CHILD " + str(child))
        var start = Time.get_ticks_msec()
        while OS.is_process_running(child):
            if Time.get_ticks_msec() - start > 15000:
                print("CHILD_RETAINED " + str(child))
                quit(23)
                return
            OS.delay_msec(20)  # bounded wall-clock loop, not a simulated-frame deadline
        print("CHILD_EXITED " + str(child))
        var exit_code = OS.get_process_exit_code(child)
        print("CHILD_EXIT_CODE " + str(exit_code))
        if exit_code != 0:
            quit(25)
            return
        var worker_receipt = FileAccess.get_file_as_string(control.path_join(token + "-worker-" + phase + ".json"))
        if worker_receipt.is_empty():
            quit(26)
            return
        print("USER_PROBE " + worker_receipt)
    quit(0)
'''
READONLY_PROBE_SCRIPT = PROBE_TEMPLATE.replace('__AUTHORIZED_WRITE__', '')
WRITE_PROBE_SCRIPT = PROBE_TEMPLATE.replace('__AUTHORIZED_WRITE__', r'''    if phase != "write" or args.size() != 5 or actual.replace("\\", "/") != args[4].replace("\\", "/"):
        quit(27)
        return
    var f = FileAccess.open("user://" + token + "-" + role + ".txt", FileAccess.WRITE)
    if f == null:
        quit(21)
        return
    f.store_string(token)
    f.close()
    var user_receipt = FileAccess.open("user://" + token + "-" + role + ".json", FileAccess.WRITE)
    if user_receipt == null:
        quit(24)
        return
    user_receipt.store_string(JSON.stringify(receipt))
    user_receipt.close()''')


class OwnedJob:
    """Windows kernel ownership: assign suspended root before any child can spawn."""
    def __init__(self, *, no_kill=False):
        import ctypes
        self.no_kill = no_kill
        from ctypes import wintypes as w
        self.ctypes = ctypes
        self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        self.kernel.CreateJobObjectW.argtypes = [w.LPVOID, w.LPCWSTR]
        self.kernel.CreateJobObjectW.restype = w.HANDLE
        self.kernel.AssignProcessToJobObject.argtypes = [w.HANDLE, w.HANDLE]
        self.kernel.AssignProcessToJobObject.restype = w.BOOL
        self.kernel.QueryInformationJobObject.argtypes = [w.HANDLE, ctypes.c_int, w.LPVOID, w.DWORD, w.LPVOID]
        self.kernel.QueryInformationJobObject.restype = w.BOOL
        self.kernel.TerminateJobObject.argtypes = [w.HANDLE, w.UINT]
        self.kernel.TerminateJobObject.restype = w.BOOL
        self.kernel.CloseHandle.argtypes = [w.HANDLE]
        self.kernel.CloseHandle.restype = w.BOOL
        self.handle = self.kernel.CreateJobObjectW(None, None)
        if not self.handle:
            raise ctypes.WinError(ctypes.get_last_error())
        class BasicLimits(ctypes.Structure):
            _fields_ = [('process_time', ctypes.c_int64), ('job_time', ctypes.c_int64),
                        ('flags', w.DWORD), ('minimum_working_set', ctypes.c_size_t),
                        ('maximum_working_set', ctypes.c_size_t), ('active_limit', w.DWORD),
                        ('affinity', ctypes.c_size_t), ('priority', w.DWORD), ('scheduling', w.DWORD)]
        class ExtendedLimits(ctypes.Structure):
            _fields_ = [('basic', BasicLimits), ('io', ctypes.c_uint64 * 6),
                        ('process_memory', ctypes.c_size_t), ('job_memory', ctypes.c_size_t),
                        ('peak_process_memory', ctypes.c_size_t), ('peak_job_memory', ctypes.c_size_t)]
        limits = ExtendedLimits()
        limits.basic.flags = 0 if no_kill else 0x2000  # no termination authority in no-kill
        self.kernel.SetInformationJobObject.argtypes = [w.HANDLE, ctypes.c_int, w.LPVOID, w.DWORD]
        self.kernel.SetInformationJobObject.restype = w.BOOL
        if not self.kernel.SetInformationJobObject(self.handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
            error = ctypes.get_last_error()
            self.kernel.CloseHandle(self.handle)
            raise ctypes.WinError(error)

    def attach_resume(self, proc):
        if self.no_kill:
            raise SafetyError('no-kill requires atomic job-list launch; suspended attach refused')
        if not self.kernel.AssignProcessToJobObject(self.handle, int(proc._handle)):
            raise self.ctypes.WinError(self.ctypes.get_last_error())
        resume = self.ctypes.WinDLL('ntdll').NtResumeProcess
        resume.argtypes = [self.ctypes.c_void_p]
        resume.restype = self.ctypes.c_long
        if resume(int(proc._handle)) != 0:
            raise SafetyError('cannot resume owned process')

    def active(self):
        # JOBOBJECT_BASIC_ACCOUNTING_INFORMATION, fixed-width native layout.
        class Accounting(self.ctypes.Structure):
            _fields_ = [('times', self.ctypes.c_int64 * 4),
                        ('page_faults', self.ctypes.c_uint32),
                        ('total', self.ctypes.c_uint32),
                        ('active', self.ctypes.c_uint32),
                        ('terminated', self.ctypes.c_uint32)]
        info = Accounting()
        if not self.kernel.QueryInformationJobObject(self.handle, 1, self.ctypes.byref(info), self.ctypes.sizeof(info), None):
            raise self.ctypes.WinError(self.ctypes.get_last_error())
        return info.active

    def stop(self):
        if self.no_kill:
            raise SafetyError('termination forbidden by no-kill policy')
        if not self.kernel.TerminateJobObject(self.handle, 125):
            raise self.ctypes.WinError(self.ctypes.get_last_error())
        deadline = time.monotonic() + 15
        while self.active():
            if time.monotonic() > deadline:
                raise SafetyError('owned job exit not proven')
            time.sleep(0.02)

    def wait_log_release(self, paths):
        # ActiveProcesses can reach zero before Windows releases inherited I/O handles.
        from ctypes import wintypes as w
        create = self.kernel.CreateFileW
        create.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, w.LPVOID, w.DWORD, w.DWORD, w.HANDLE]
        create.restype = w.HANDLE
        deadline = time.monotonic() + 3
        for path in paths:
            while True:
                handle = create(str(path), 0x10000, 7, None, 3, 0x80, None)  # DELETE access, no deletion
                if handle != self.ctypes.c_void_p(-1).value:
                    self.kernel.CloseHandle(handle)
                    break
                error = self.ctypes.get_last_error()
                if error != 32 or time.monotonic() > deadline:
                    raise self.ctypes.WinError(error)
                time.sleep(0.02)

    def launch(self, command, env, cwd, stdout, stderr):
        if not self.no_kill:
            raise SafetyError('atomic launch is only exposed for explicit no-kill')
        return atomic_job_launch(self, command, env, cwd, stdout, stderr)

    def identities(self):
        """Exact currently active job PIDs, with kernel creation identity."""
        c = self.ctypes
        from ctypes import wintypes as w
        capacity = 16
        while capacity <= 65536:
            class Pids(c.Structure):
                _fields_ = [('assigned', w.DWORD), ('count', w.DWORD),
                            ('pids', c.c_size_t * capacity)]
            info = Pids()
            if self.kernel.QueryInformationJobObject(self.handle, 3, c.byref(info), c.sizeof(info), None):
                return [process_identity(int(pid)) for pid in info.pids[:info.count]]
            if c.get_last_error() != 234:
                raise c.WinError(c.get_last_error())
            capacity *= 2
        raise SafetyError('owned PID list exceeded bounded capacity')

    def close(self):
        if self.no_kill and self.active():
            raise SafetyError('live no-kill job handle must be retained')
        if self.handle:
            self.kernel.CloseHandle(self.handle)
            self.handle = None


def process_identity(pid, handle=None):
    import ctypes as c
    from ctypes import wintypes as w
    k = c.WinDLL('kernel32', use_last_error=True)
    k.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
    k.OpenProcess.restype = w.HANDLE
    k.GetProcessTimes.argtypes = [w.HANDLE, c.POINTER(w.FILETIME), c.POINTER(w.FILETIME), c.POINTER(w.FILETIME), c.POINTER(w.FILETIME)]
    k.GetProcessTimes.restype = w.BOOL
    k.CloseHandle.argtypes = [w.HANDLE]
    owned = handle is None
    handle = k.OpenProcess(0x1000, False, pid) if owned else handle
    if not handle:
        raise c.WinError(c.get_last_error())
    try:
        times = [w.FILETIME() for _ in range(4)]
        if not k.GetProcessTimes(handle, *(c.byref(x) for x in times)):
            raise c.WinError(c.get_last_error())
        return {'pid': pid, 'creation_time_100ns': (times[0].dwHighDateTime << 32) | times[0].dwLowDateTime}
    finally:
        if owned:
            k.CloseHandle(handle)


class NativeProcess:
    """Minimal observation handle, deliberately has no kill/terminate methods."""
    def __init__(self, kernel, handle, pid):
        self.kernel, self._handle, self.pid = kernel, handle, pid

    def poll(self):
        import ctypes as c
        status = self.kernel.WaitForSingleObject(self._handle, 0)
        if status == 258:
            return None
        if status != 0:
            raise c.WinError(c.get_last_error())
        code = c.c_uint32()
        if not self.kernel.GetExitCodeProcess(self._handle, c.byref(code)):
            raise c.WinError(c.get_last_error())
        return code.value

    def close(self):
        if self.poll() is None:
            raise SafetyError('live process handle must be retained')
        self.kernel.CloseHandle(self._handle)
        self._handle = None


def atomic_job_launch(job, command, env, cwd, stdout, stderr):
    """Win10+ JOB_LIST assignment is atomic with CreateProcess, no suspended gap.

    Unsupported attribute, nested-job denial or invalid job => CreateProcess
    refuses before user code. Never fall back to Popen/attach in no-kill mode.
    """
    import ctypes as c
    from ctypes import wintypes as w
    import msvcrt
    k = job.kernel
    class Startup(c.Structure):
        _fields_ = [('cb', w.DWORD), ('reserved', w.LPWSTR), ('desktop', w.LPWSTR),
                    ('title', w.LPWSTR), ('x', w.DWORD), ('y', w.DWORD),
                    ('xsize', w.DWORD), ('ysize', w.DWORD), ('xchars', w.DWORD),
                    ('ychars', w.DWORD), ('fill', w.DWORD), ('flags', w.DWORD),
                    ('show', w.WORD), ('reserved_size', w.WORD), ('reserved_bytes', c.c_void_p),
                    ('stdin', w.HANDLE), ('stdout', w.HANDLE), ('stderr', w.HANDLE)]
    class StartupEx(c.Structure):
        _fields_ = [('startup', Startup), ('attributes', c.c_void_p)]
    class ProcessInfo(c.Structure):
        _fields_ = [('process', w.HANDLE), ('thread', w.HANDLE), ('pid', w.DWORD), ('tid', w.DWORD)]
    k.InitializeProcThreadAttributeList.argtypes = [c.c_void_p, w.DWORD, w.DWORD, c.POINTER(c.c_size_t)]
    k.InitializeProcThreadAttributeList.restype = w.BOOL
    k.UpdateProcThreadAttribute.argtypes = [c.c_void_p, w.DWORD, c.c_size_t, c.c_void_p, c.c_size_t, c.c_void_p, c.c_void_p]
    k.UpdateProcThreadAttribute.restype = w.BOOL
    k.DeleteProcThreadAttributeList.argtypes = [c.c_void_p]
    k.CreateProcessW.argtypes = [w.LPCWSTR, w.LPWSTR, c.c_void_p, c.c_void_p, w.BOOL, w.DWORD,
                                c.c_void_p, w.LPCWSTR, c.POINTER(StartupEx), c.POINTER(ProcessInfo)]
    k.CreateProcessW.restype = w.BOOL
    k.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]
    k.WaitForSingleObject.restype = w.DWORD
    k.GetExitCodeProcess.argtypes = [w.HANDLE, c.POINTER(w.DWORD)]
    k.GetExitCodeProcess.restype = w.BOOL
    size = c.c_size_t()
    k.InitializeProcThreadAttributeList(None, 2, 0, c.byref(size))
    if not size.value:
        raise SafetyError('atomic JOB_LIST unsupported; no-kill launch refused')
    attributes = c.create_string_buffer(size.value)
    if not k.InitializeProcThreadAttributeList(attributes, 2, 0, c.byref(size)):
        raise c.WinError(c.get_last_error())
    try:
        jobs = (w.HANDLE * 1)(job.handle)
        if not k.UpdateProcThreadAttribute(attributes, 0, 0x2000D, jobs, c.sizeof(jobs), None, None):
            raise SafetyError('atomic JOB_LIST unavailable; no process launched: ' + str(c.get_last_error()))
        with open(os.devnull, 'rb') as stdin:
            handles = (w.HANDLE * 3)(*(msvcrt.get_osfhandle(x.fileno()) for x in (stdin, stdout, stderr)))
            inherited = [os.get_handle_inheritable(x) for x in handles]
            try:
                for h in handles:
                    os.set_handle_inheritable(h, True)
                if not k.UpdateProcThreadAttribute(attributes, 0, 0x20002, handles, c.sizeof(handles), None, None):
                    raise c.WinError(c.get_last_error())
                startup = StartupEx()
                startup.startup.cb = c.sizeof(startup)
                startup.startup.flags = 0x100  # STARTF_USESTDHANDLES
                startup.startup.stdin, startup.startup.stdout, startup.startup.stderr = handles
                startup.attributes = c.cast(attributes, c.c_void_p)
                environment = c.create_unicode_buffer('\0'.join(k + '=' + v for k, v in sorted(env.items(), key=lambda x: x[0].upper())) + '\0\0')
                argv = c.create_unicode_buffer(subprocess.list2cmdline(command))
                info = ProcessInfo()
                # CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT | UNICODE_ENVIRONMENT
                if not k.CreateProcessW(str(command[0]), argv, None, None, True, 0x08080400,
                                        environment, str(cwd), c.byref(startup), c.byref(info)):
                    raise c.WinError(c.get_last_error())
                # Atomic assignment succeeded; both identity and ownership are now known.
                process = NativeProcess(k, info.process, info.pid)
                job.launched_process = process  # recover ownership if post-create handle release raises
                k.CloseHandle(info.thread)
                return process
            finally:
                for h, value in zip(handles, inherited):
                    os.set_handle_inheritable(h, value)
    finally:
        k.DeleteProcThreadAttributeList(attributes)


# Live handles are retained in this module, not serialized or silently cancelled.
# CLI exit releases non-killing handles; PIDs/creation identities remain in evidence.
RETAINED = {}


def execute(command, env, generated, evidence, label, budgets, records, *, no_kill=False):
    if no_kill:
        return execute_observation(command, env, generated, evidence, label, budgets, records)
    out, err = evidence / (label + '.stdout.log'), evidence / (label + '.stderr.log')
    start = time.monotonic()
    reason = None
    if os.name != 'nt':
        raise SafetyError('Windows E-drive runner requires Windows process ownership')
    job = OwnedJob()
    with out.open('wb') as stdout, err.open('wb') as stderr:
        proc = None
        record = {'label': label, 'command': command, 'exited': False}
        records.append(record)
        try:
            proc = subprocess.Popen(command, env=env, stdout=stdout, stderr=stderr,
                                    cwd=generated, creationflags=0x00000004)
            record['pid'] = proc.pid
            job.attach_resume(proc)
            while proc.poll() is None or job.active():
                if time.monotonic() - start > budgets['seconds']:
                    reason = 'timeout'
                elif tree_bytes(generated.parent) > budgets['bytes']:
                    reason = 'byte_budget'
                elif shutil.disk_usage(generated).free < budgets['min_free']:
                    reason = 'free_space_budget'
                if reason:
                    break
                time.sleep(0.1)
        finally:
            try:
                if job.active():
                    job.stop()
                if proc is not None:
                    if proc.poll() is None:
                        proc.kill()  # attach failure: still only the exact owned root handle
                    code = proc.wait(timeout=15)
                    active = job.active()
                    record.update(exit_code=code, budget_failure=reason,
                                  duration_seconds=round(time.monotonic() - start, 3),
                                  active_owned_processes=active, exited=(active == 0))
            finally:
                job.close()
    job.wait_log_release([out, err])
    record['log_handles_released'] = True
    stdout = out.read_bytes().decode('utf-8')
    stderr = err.read_bytes().decode('utf-8')
    if reason:
        raise SafetyError(reason)
    return stdout, stderr, code


def observation_logs(out, err, evidence, label, phase):
    """Snapshot bytes at this observation; never relabel a live log as final."""
    result = []
    for source, stream in ((out, 'stdout'), (err, 'stderr')):
        data = source.read_bytes()
        target = evidence / (label + '.' + phase + '.' + stream + '.log')
        with target.open('xb') as f:
            f.write(data)
        result.append({'path': str(target), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    return result


def execute_observation(command, env, generated, evidence, label, budgets, records):
    """No-kill strategy; errors stop dispatch, never cancel existing processes."""
    if os.name != 'nt':
        raise SafetyError('Windows atomic job-list ownership required')
    if any(x.get('launch_blocked') for x in records):
        raise SafetyError('launch blocked by previous incomplete/failed observation')
    generated, evidence = physical_e(generated), physical_e(evidence)
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', label):
        raise SafetyError('unsafe log label')
    if not math.isfinite(budgets['seconds']) or budgets['seconds'] <= 0 or budgets['bytes'] <= 0 or budgets['min_free'] < 0:
        raise SafetyError('invalid explicit budget')
    out, err = evidence / (label + '.stdout.log'), evidence / (label + '.stderr.log')
    if out.exists() or err.exists():
        raise SafetyError('raw log already exists; refusing overwrite')
    start = time.monotonic()
    record = {'label': label, 'command': list(command), 'cwd': str(generated), 'no_kill': True,
              'environment': {k: env.get(k) for k in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR')},
              'started': False, 'exited': False, 'exit_code': None, 'active_owned_processes': None,
              'stdout': str(out), 'stderr': str(err), 'budget_failure': None,
              'retained': False, 'owned_process_identities': [], 'observed_process_identities': []}
    records.append(record)  # register before even creating a job
    job, proc, failure = None, None, None
    try:
        job = OwnedJob(no_kill=True)
        with out.open('xb') as stdout, err.open('xb') as stderr:
            proc = job.launch(command, env, generated, stdout, stderr)
            record.update(pid=proc.pid, started=True)
            record['root_identity'] = process_identity(proc.pid, proc._handle)
            while True:
                code, active = proc.poll(), job.active()
                record.update(exit_code=code, active_owned_processes=active)
                record['owned_process_identities'] = job.identities()
                for identity in record['owned_process_identities']:
                    if identity not in record['observed_process_identities']:
                        record['observed_process_identities'].append(identity)
                if code is not None and active == 0:
                    break
                if time.monotonic() - start > budgets['seconds']:
                    record['budget_failure'] = 'timeout'
                elif tree_bytes(generated.parent) > budgets['bytes']:
                    record['budget_failure'] = 'byte_budget'
                elif shutil.disk_usage(generated).free < budgets['min_free']:
                    record['budget_failure'] = 'free_space_budget'
                if record['budget_failure']:
                    raise SafetyError(record['budget_failure'])
                time.sleep(0.05)
    except BaseException as exc:
        failure = exc
        record['error'] = type(exc).__name__ + ': ' + str(exc)
        record['launch_blocked'] = True
    finally:
        record['duration_seconds'] = round(time.monotonic() - start, 3)
        if proc is None and job is not None:
            proc = getattr(job, 'launched_process', None)
            if proc is not None:
                record.update(pid=proc.pid, started=True)
        try:
            if proc is not None:
                if 'root_identity' not in record:
                    record['root_identity'] = process_identity(proc.pid, proc._handle)
                record['exit_code'] = proc.poll()
            active = job.active() if job is not None else 0
            record['active_owned_processes'] = active
            if job is not None:
                record['owned_process_identities'] = job.identities()
            record['exited'] = active == 0 and (proc is None or record['exit_code'] is not None)
        except BaseException as exc:
            record['observation_error'] = type(exc).__name__ + ': ' + str(exc)
            record['exited'] = False
            record['active_owned_processes'] = None
            failure = failure or exc
        if not record['exited']:
            record.update(retained=True, launch_blocked=True,
                          retention='NO_KILL: preserve owned processes, handles, generated tree and raw logs; exit unknown is null')
            key = str(evidence / label)
            record['retained_handle_key'] = key
            RETAINED[key] = (job, proc, out, err, record)
        else:
            try:
                if job is not None:
                    job.wait_log_release([out, err])
                record['log_handles_released'] = True
                if proc is not None:
                    proc.close()
                if job is not None:
                    job.close()
            except BaseException as exc:
                record.update(retained=True, launch_blocked=True, release_error=str(exc),
                              retention='NO_KILL: handle release unproven; preserve generated and evidence')
                if job is not None and proc is not None and job.handle and proc._handle:
                    key = str(evidence / label)
                    record['retained_handle_key'] = key
                    RETAINED[key] = (job, proc, out, err, record)
                failure = failure or exc
        if out.exists() and err.exists():
            try:
                record['observation_logs'] = observation_logs(out, err, evidence, label, 'observation')
            except BaseException as exc:
                record['snapshot_error'] = str(exc)
                failure = failure or exc
        # Immutable original observation even when a later natural exit is recorded.
        with (evidence / (label + '.observation.json')).open('x', encoding='utf-8') as f:
            json.dump(record, f, ensure_ascii=False, indent=2)
    if failure is not None:
        raise failure
    return out.read_bytes().decode('utf-8'), err.read_bytes().decode('utf-8'), record['exit_code']


def observe_retained(key, seconds):
    """Bounded observation only; append a separate receipt, keep original unchanged."""
    if not math.isfinite(seconds) or seconds <= 0:
        raise SafetyError('invalid late observation budget')
    job, proc, out, err, original = RETAINED[key]
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        code, active = proc.poll(), job.active()
        if code is not None and active == 0:
            break
        time.sleep(0.05)
    else:
        raise SafetyError('late observation expired; still retained, no termination')
    job.wait_log_release([out, err])
    identities = job.identities()
    late = {'original_observation': str(out.parent / (original['label'] + '.observation.json')),
            'root_identity': original['root_identity'], 'exit_code': code,
            'active_owned_processes': active, 'owned_process_identities': identities,
            'exited': True, 'log_handles_released': True, 'retention_released': True,
            'logs': observation_logs(out, err, out.parent, original['label'], 'late')}
    with (out.parent / (original['label'] + '.late.json')).open('x', encoding='utf-8') as f:
        json.dump(late, f, ensure_ascii=False, indent=2)
    proc.close()
    job.close()
    del RETAINED[key]
    return late


def verify_probe(stdout, generated, token):
    entries = []
    for line in stdout.splitlines():
        if line.startswith('USER_PROBE '):
            entries.append(json.loads(line[len('USER_PROBE '):], object_pairs_hook=unique_fields))
    if len(entries) != 2 or {x.get('role') for x in entries} != {'main', 'worker'}:
        raise SafetyError('missing real main/worker probe')
    if len({x.get('pid') for x in entries}) != 2:
        raise SafetyError('probe PID collision')
    for item in entries:
        if item.get('token') != token or type(item.get('pid')) is not int or item['pid'] <= 0:
            raise SafetyError('invalid probe identity')
        path = physical_e(item['path'])
        contained(path, generated)
        probe = contained(path / (token + '-' + item['role'] + '.txt'), generated)
        receipt = contained(path / (token + '-' + item['role'] + '.json'), generated)
        if probe.read_text(encoding='utf-8') != token:
            raise SafetyError('physical probe content mismatch')
        if json.loads(receipt.read_text(encoding='utf-8'), object_pairs_hook=unique_fields) != item:
            raise SafetyError('physical worker receipt mismatch')
        item['physical_path'] = str(path)
        item['probe_sha256'] = hashlib.sha256(probe.read_bytes()).hexdigest()
        item['receipt_sha256'] = hashlib.sha256(receipt.read_bytes()).hexdigest()
    worker = next(x for x in entries if x['role'] == 'worker')['pid']
    if 'OWNED_CHILD ' + str(worker) not in stdout.splitlines() or 'CHILD_EXITED ' + str(worker) not in stdout.splitlines():
        raise SafetyError('missing owned child exit evidence')
    if 'CHILD_EXIT_CODE 0' not in stdout.splitlines():
        raise SafetyError('worker exit code is not zero')
    return entries


def verify_report_probe(stdout, generated, token):
    entries = [json.loads(line[len('USER_PROBE '):], object_pairs_hook=unique_fields)
               for line in stdout.splitlines() if line.startswith('USER_PROBE ')]
    if len(entries) != 2 or {x.get('role') for x in entries} != {'main', 'worker'}:
        raise SafetyError('missing real main/worker report')
    if len({x.get('pid') for x in entries}) != 2:
        raise SafetyError('probe PID collision')
    for item in entries:
        if item.get('token') != token or type(item.get('pid')) is not int or item['pid'] <= 0 or item.get('phase') != 'report':
            raise SafetyError('invalid read-only probe identity')
        item['physical_path'] = str(contained(physical_e(item['path']), generated))
        if not isinstance(item.get('environment'), dict) or type(item.get('worker_pool_max_threads')) is not int:
            raise SafetyError('missing actual environment/threading report')
    worker = next(x for x in entries if x['role'] == 'worker')['pid']
    if any(line not in stdout.splitlines() for line in ('OWNED_CHILD ' + str(worker), 'CHILD_EXITED ' + str(worker), 'CHILD_EXIT_CODE 0')):
        raise SafetyError('missing natural child exit evidence')
    if len({x['physical_path'] for x in entries}) != 1:
        raise SafetyError('main/worker data paths differ; write not authorized')
    return entries


def run_two_phase_probe(executable, probe, env, generated, evidence, token, budgets, records):
    """Authorization gate between read-only reporting and explicit user:// write."""
    control = probe / 'control'
    control.mkdir()
    contained(physical_e(control), generated)
    (probe / 'probe.gd').write_text(READONLY_PROBE_SCRIPT, encoding='utf-8')
    (evidence / 'probe-report.gd').write_text(READONLY_PROBE_SCRIPT, encoding='utf-8')
    shutil.copyfile(probe / 'project.godot', evidence / 'probe-project.godot')
    base = [str(executable), '--headless', '--fixed-fps', '60', '--quit-after', '1800',
            '--path', str(probe), '--script', 'res://probe.gd', '--', token, 'main', str(control)]
    report_command = base[:1] + ['--log-file', str(control / (token + '-main-report.engine.log'))] + base[1:] + ['report']
    stdout, stderr, code = execute(report_command, env, generated, evidence, 'probe-report', budgets, records, no_kill=True)
    if code != 0 or re.search(r'SCRIPT ERROR|ERROR:', stdout + stderr):
        raise SafetyError('read-only engine probe failed')
    reports = verify_report_probe(stdout, generated, token)
    path = reports[0]['physical_path']
    authorization = {'token': token, 'reports': reports, 'approved_user_path': path,
                     'user_token_write_before_authorization': False}
    # No token file may already exist; first phase cannot masquerade as a writer.
    for item in reports:
        for suffix in ('.txt', '.json'):
            if (Path(path) / (token + '-' + item['role'] + suffix)).exists():
                raise SafetyError('user token exists before authorization')
    with (evidence / 'probe-authorization.json').open('x', encoding='utf-8') as f:
        json.dump(authorization, f, ensure_ascii=False, indent=2)
    contained(physical_e(path), generated)  # revalidate immediately before write launch
    contained(physical_e(control), generated)
    (probe / 'probe.gd').write_text(WRITE_PROBE_SCRIPT, encoding='utf-8')
    (evidence / 'probe-write.gd').write_text(WRITE_PROBE_SCRIPT, encoding='utf-8')
    write_command = base[:1] + ['--log-file', str(control / (token + '-main-write.engine.log'))] + base[1:] + ['write', path]
    stdout, stderr, code = execute(write_command, env, generated, evidence, 'probe-write', budgets, records, no_kill=True)
    if code != 0 or re.search(r'SCRIPT ERROR|ERROR:', stdout + stderr):
        raise SafetyError('authorized engine write probe failed')
    written = verify_probe(stdout, generated, token)
    for item in written:
        if item.get('phase') != 'write' or item['physical_path'] != path:
            raise SafetyError('write probe did not match authorized physical path')
    artifacts = evidence / 'probe-artifacts'
    artifacts.mkdir()
    for source in control.iterdir():
        source = contained(source, generated)
        if source.is_file():
            shutil.copyfile(source, artifacts / source.name)
    for item in written:
        for suffix in ('.txt', '.json'):
            name = token + '-' + item['role'] + suffix
            shutil.copyfile(contained(Path(path) / name, generated), artifacts / name)
    return {'reports': reports, 'writes': written, 'authorization': authorization}


def run(args):
    no_kill = getattr(args, 'no_kill', False)
    quit_after = getattr(args, 'quit_after', None)
    if quit_after is not None and (not no_kill or type(quit_after) is not int or quit_after <= 0):
        raise SafetyError('quit-after requires positive frames and explicit no-kill')
    root = physical_e(args.root)
    project = physical_e(args.project)
    executable = physical_e(args.godot)
    if not executable.is_file() or not (project / 'project.godot').is_file():
        raise SafetyError('project/executable missing')
    config = no_links(project / 'project.godot').read_text(encoding='utf-8-sig')
    override = no_links(project / 'override.cfg')
    if override.exists() or re.search(r'^\s*config/project_settings_override(?:[.\w]*)\s*=', config, re.M):
        raise SafetyError('project settings override is not covered by physical probe; refused')
    if not args.scene.startswith('res://') or not args.scene.endswith('.tscn'):
        raise SafetyError('scene must be explicit res:// .tscn')
    scene_rel = args.scene[len('res://'):]
    if '..' in Path(scene_rel).parts or Path(scene_rel).is_absolute():
        raise SafetyError('scene traversal')
    contained(project / scene_rel, project)
    budgets = {'seconds': args.timeout, 'bytes': args.max_bytes, 'min_free': args.min_free_bytes}
    if not math.isfinite(args.timeout) or args.timeout <= 0 or args.max_bytes <= 0 or args.min_free_bytes < 0:
        raise SafetyError('invalid explicit budget')
    if shutil.disk_usage(root).free < args.min_free_bytes:
        raise SafetyError('insufficient free disk before allocation')
    run_id = uuid.uuid4().hex
    owner = root / ('isolated-' + run_id)
    owner.mkdir()
    generated, evidence = owner / 'generated', owner / 'evidence'
    generated.mkdir()
    evidence.mkdir()
    manifest = {'run_id': run_id, 'root': str(root), 'generated': str(generated), 'project': str(project),
                'scene': args.scene, 'godot': str(executable), 'budgets': budgets,
                'freeze': args.freeze, 'no_kill': no_kill, 'processes': [], 'passed': False,
                'cleanup': 'not_started', 'source_files': []}
    env = os.environ.copy()
    env['APPDATA'] = str(generated / 'appdata')
    env['LOCALAPPDATA'] = str(generated / 'localappdata')
    # Legacy callers keep their environment contract. No-kill owns all temp output.
    if no_kill:
        (generated / 'tmp').mkdir()
        for key in ('TEMP', 'TMP', 'TMPDIR'):
            env[key] = str(generated / 'tmp')
    (generated / 'appdata').mkdir()
    (generated / 'localappdata').mkdir()
    target = project
    try:
        application = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)', config, re.M | re.S)
        if not application:
            raise SafetyError('application section required for accurate user-data probe')
        probe = generated / 'probe'
        probe.mkdir()
        threading = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)', config, re.M | re.S)
        probe_config = 'config_version=5\n[application]\n' + application[1]
        if threading:
            probe_config += '\n[threading]\n' + threading[1]
        (probe / 'project.godot').write_text(probe_config, encoding='utf-8')
        if no_kill:
            manifest['two_phase_probe'] = run_two_phase_probe(executable, probe, env, generated, evidence,
                run_id, budgets, manifest['processes'])
            manifest['user_probes'] = manifest['two_phase_probe']['writes']
        else:
            (probe / 'probe.gd').write_text(PROBE_SCRIPT, encoding='utf-8')
            command = [str(executable), '--headless', '--path', str(probe), '--script', 'res://probe.gd', '--', run_id, 'main', str(generated)]
            stdout, stderr, code = execute(command, env, generated, evidence, 'probe', budgets, manifest['processes'])
            if code != 0 or re.search(r'SCRIPT ERROR|ERROR:', stdout + stderr):
                raise SafetyError('engine probe failed')
            manifest['user_probes'] = verify_probe(stdout, generated, run_id)
        manifest['probe_config_sha256'] = hashlib.sha256(probe_config.encode('utf-8')).hexdigest()
        target = project
        if args.freeze:
            files = source_files(project, ['project.godot', scene_rel, *args.include])
            total = sum((project / x).stat().st_size for x in files)
            if total + tree_bytes(owner) > args.max_bytes:
                raise SafetyError('freeze byte budget exceeded before copy')
            target = generated / 'project'
            target.mkdir()
            for rel in files:
                source = contained(project / rel, project)
                destination = target / rel
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
                digest = hashlib.sha256(destination.read_bytes()).hexdigest()
                if digest != hashlib.sha256(source.read_bytes()).hexdigest():
                    raise SafetyError('source changed during freeze')
                manifest['source_files'].append({'path': rel.as_posix(), 'bytes': destination.stat().st_size, 'sha256': digest})
            if no_links(target / 'project.godot').read_text(encoding='utf-8-sig') != config or no_links(target / 'override.cfg').exists():
                raise SafetyError('project configuration changed after physical probe')
            scene_text = (target / scene_rel).read_text(encoding='utf-8-sig')
            dependencies = re.findall(r'^\[ext_resource\b[^\n]*\bpath="(res://[^"\n]+)"', scene_text, re.M)
            missing = []
            for dependency in dependencies:
                rel = Path(dependency[len('res://'):])
                if rel.is_absolute() or '..' in rel.parts:
                    raise SafetyError('unsafe frozen scene dependency: ' + dependency)
                path = no_links(target / rel)
                if not path.is_file():
                    missing.append(dependency)
                else:
                    contained(path, target)
            if missing:
                raise SafetyError('missing frozen scene dependencies: ' + ', '.join(sorted(set(missing))) +
                                  '; add explicit --include dependencies (no automatic broad copy)')
            stdout, stderr, code = execute([str(executable), '--headless', '--editor', '--import', '--path', str(target)],
                                           env, generated, evidence, 'import', budgets, manifest['processes'], no_kill=no_kill)
            if code != 0 or re.search(r'SCRIPT ERROR|ERROR:', stdout + stderr):
                raise SafetyError('frozen dependency import failed; inspect evidence/import.stdout.log and import.stderr.log; add explicit --include dependencies')
        if no_links(target / 'project.godot').read_text(encoding='utf-8-sig') != config or no_links(target / 'override.cfg').exists():
            raise SafetyError('project configuration changed after physical probe')
        command = [str(executable), '--headless', '--fixed-fps', '60', '--path', str(target), '--scene', args.scene]
        if no_kill and getattr(args, 'quit_after', None):
            command += ['--quit-after', str(args.quit_after)]
        stdout, stderr, code = execute(command, env, generated, evidence, 'scene', budgets, manifest['processes'], no_kill=no_kill)
        manifest['analysis'] = analyze(stdout, stderr, code)
        manifest['passed'] = manifest['analysis']['passed']
    except Exception as exc:
        manifest['error'] = type(exc).__name__ + ': ' + str(exc)
    finally:
        # Archive content-addressed minimal evidence before removing generated copies.
        try:
            retained = no_kill and any(x.get('retained') or not x.get('exited') for x in manifest['processes'])
            if retained:
                manifest['retention'] = 'NO_KILL: active/unknown owned tree preserved; no scan/archive/cleanup of generated'
            if not manifest['passed'] and not retained:
                failure = evidence / 'failure'
                failure.mkdir()
                for path in [generated / 'probe' / 'project.godot', generated / 'probe' / 'probe.gd']:
                    if path.is_file():
                        shutil.copyfile(no_links(path), failure / path.name)
                minimal = failure / 'target'
                minimal.mkdir()
                scene = target / scene_rel
                names = {'project.godot', scene_rel}
                if scene.is_file() and scene.stat().st_size <= 65536:
                    names.update(x[len('res://'):] for x in re.findall(r'path="(res://[^"\n]+\.gd)"', scene.read_text(encoding='utf-8')))
                manifest['failure_evidence'] = []
                remaining = min(1048576, args.max_bytes)
                for name in sorted(names):
                    path = target / name
                    if not path.is_file():
                        continue
                    path = contained(path, target)
                    size = path.stat().st_size
                    if size > 65536 or size > remaining:
                        manifest['failure_evidence'].append({'path': name, 'retained': False, 'reason': 'minimal_evidence_budget'})
                        continue
                    destination = minimal / name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(path, destination)
                    remaining -= size
                    manifest['failure_evidence'].append({'path': name, 'retained': True, 'bytes': size,
                        'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
            manifest['logs'] = [{'path': x.name, 'bytes': x.stat().st_size,
                                 'sha256': hashlib.sha256(x.read_bytes()).hexdigest()}
                                for x in evidence.glob('*.log') if not retained or '.observation.' in x.name]
            # Write evidence before cleanup; source repository/formal saves never targets.
            (owner / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
            if not retained and all(x.get('exited') for x in manifest['processes']):
                delete_owned(generated, owner)
                manifest['cleanup'] = 'generated_removed'
            else:
                manifest['cleanup'] = 'retained_process_exit_unproven'
                manifest['passed'] = False
        except Exception as exc:
            manifest['cleanup'] = 'retained: ' + str(exc)
            manifest['passed'] = False
        (owner / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'passed': manifest['passed'], 'manifest': str(owner / 'manifest.json'),
                      'error': manifest.get('error'), 'cleanup': manifest['cleanup']}, ensure_ascii=False))
    return 0 if manifest['passed'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('project', 'scene', 'root', 'godot'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--timeout', type=float, required=True, help='seconds per process')
    parser.add_argument('--max-bytes', type=int, required=True, help='monitored total owned tree ceiling')
    parser.add_argument('--min-free-bytes', type=int, required=True)
    parser.add_argument('--freeze', action='store_true')
    parser.add_argument('--no-kill', action='store_true', help='never terminate; budgets stop launches and retain live owned processes/evidence (Win10+ atomic JOB_LIST required)')
    parser.add_argument('--quit-after', type=int, help='optional finite engine frame limit in no-kill scene mode; not a wall-clock cancellation')
    parser.add_argument('--include', action='append', default=[], help='explicit freeze dependency, project-relative')
    args = parser.parse_args()
    try:
        return run(args)
    except (SafetyError, OSError) as exc:
        print(json.dumps({'passed': False, 'error': str(exc)}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
