"""A03: serial real-window baseline; no production/test modifications."""
import ctypes
from ctypes import wintypes as W
import datetime
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'reports/refactoring'
LOGS = OUT / 'window-logs'
GODOT = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe')
SUITES = ['area_lock_window_test', 'native_choices_window_test', 'net_v2_browsing_window_test', 'net_v2_ui_input_parity_window_test', 'net_v2_area_window_test', 'net_v2_residue_phase_window_test']
user = ctypes.WinDLL('user32', use_last_error=True)
gdi = ctypes.WinDLL('gdi32', use_last_error=True)
CB = ctypes.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
user.EnumWindows.argtypes = [CB, W.LPARAM]
user.GetWindowThreadProcessId.argtypes = [W.HWND, ctypes.POINTER(W.DWORD)]
user.IsWindowVisible.argtypes = [W.HWND]
user.GetClientRect.argtypes = [W.HWND, ctypes.POINTER(W.RECT)]
user.GetDC.argtypes = [W.HWND]; user.GetDC.restype = W.HDC
user.ReleaseDC.argtypes = [W.HWND, W.HDC]
user.PrintWindow.argtypes = [W.HWND, W.HDC, W.UINT]
gdi.CreateCompatibleDC.argtypes = [W.HDC]; gdi.CreateCompatibleDC.restype = W.HDC
gdi.CreateCompatibleBitmap.argtypes = [W.HDC, ctypes.c_int, ctypes.c_int]; gdi.CreateCompatibleBitmap.restype = W.HBITMAP
gdi.SelectObject.argtypes = [W.HDC, W.HANDLE]; gdi.SelectObject.restype = W.HANDLE
gdi.DeleteDC.argtypes = [W.HDC]; gdi.DeleteObject.argtypes = [W.HANDLE]
gdi.GetDIBits.argtypes = [W.HDC, W.HBITMAP, W.UINT, W.UINT, ctypes.c_void_p, ctypes.c_void_p, W.UINT]

def capture(pid, path):
    found = []
    @CB
    def visit(hwnd, _):
        owner = W.DWORD()
        user.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user.IsWindowVisible(hwnd):
            r = W.RECT()
            user.GetClientRect(hwnd, ctypes.byref(r))
            if r.right > 400 and r.bottom > 300:
                found.append((hwnd, r.right, r.bottom))
        return True
    user.EnumWindows(visit, 0)
    if not found:
        return None
    hwnd, width, height = found[0]
    dc = user.GetDC(hwnd)
    mem = gdi.CreateCompatibleDC(dc)
    bitmap = gdi.CreateCompatibleBitmap(dc, width, height)
    old = gdi.SelectObject(mem, bitmap)
    try:
        ok = user.PrintWindow(hwnd, mem, 3)  # client-only + render-full-content
        gdi.SelectObject(mem, old)
        header = struct.pack('<IiiHHIIiiII', 40, width, -height, 1, 32, 0, width * height * 4, 0, 0, 0, 0)
        info = ctypes.create_string_buffer(header)
        pixels = ctypes.create_string_buffer(width * height * 4)
        lines = gdi.GetDIBits(mem, bitmap, 0, height, pixels, info, 0)
        if not ok or lines != height:
            return {'hwnd': int(hwnd), 'width': width, 'height': height, 'error': 'PrintWindow/GetDIBits failed'}
        path.write_bytes(struct.pack('<2sIHHI', b'BM', 54 + len(pixels.raw), 0, 0, 54) + header + pixels.raw)
        return {'hwnd': int(hwnd), 'width': width, 'height': height, 'path': str(path), 'method': 'PrintWindow client+render-full-content', 'native_review': 'pending'}
    finally:
        gdi.DeleteObject(bitmap); gdi.DeleteDC(mem); user.ReleaseDC(hwnd, dc)

def owned_descendants(parent):
    # Godot's console executable forwards to a separate GUI process on Windows.
    class Entry(ctypes.Structure):
        _fields_ = [('dwSize', W.DWORD), ('cntUsage', W.DWORD), ('th32ProcessID', W.DWORD), ('th32DefaultHeapID', ctypes.c_size_t), ('th32ModuleID', W.DWORD), ('cntThreads', W.DWORD), ('th32ParentProcessID', W.DWORD), ('pcPriClassBase', W.LONG), ('dwFlags', W.DWORD), ('szExeFile', W.WCHAR * 260)]
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateToolhelp32Snapshot.argtypes = [W.DWORD, W.DWORD]
    kernel.CreateToolhelp32Snapshot.restype = W.HANDLE
    kernel.Process32FirstW.argtypes = [W.HANDLE, ctypes.POINTER(Entry)]
    kernel.Process32NextW.argtypes = [W.HANDLE, ctypes.POINTER(Entry)]
    kernel.CloseHandle.argtypes = [W.HANDLE]
    snap = kernel.CreateToolhelp32Snapshot(2, 0)
    rows = []
    entry = Entry(); entry.dwSize = ctypes.sizeof(entry)
    try:
        ok = kernel.Process32FirstW(snap, ctypes.byref(entry))
        while ok:
            rows.append((entry.th32ProcessID, entry.th32ParentProcessID))
            ok = kernel.Process32NextW(snap, ctypes.byref(entry))
    finally:
        kernel.CloseHandle(snap)
    owned = {parent}
    while True:
        added = {pid for pid, ppid in rows if ppid in owned} - owned
        if not added:
            return sorted(owned)
        owned.update(added)

def main():
    LOGS.mkdir(parents=True, exist_ok=True)
    report = {'task': 'A03', 'started_at': datetime.datetime.now().astimezone().isoformat(), 'timeout_seconds_per_suite': 240, 'serial': True, 'headless': False, 'suites': [], 'notes': ['No production/test source edits. Tests may create their own runtime evidence.', 'Automated GUI events are supplied by existing tests, not OS hardware mouse validation.', 'Headless comparisons will be attached only when real baseline results are available.', 'Screenshot capture alone is not visual acceptance; native review required.']}
    for suite in SUITES:
        cmd = [str(GODOT), '--fixed-fps', '60', '--path', str(ROOT), '--scene', 'res://tests/' + suite + '.tscn', '--', 'window']
        log = LOGS / (suite + '.log')
        start = time.monotonic()
        item = {'suite': suite, 'command': cmd, 'log': str(log), 'screenshots': [], 'timeout': False}
        with log.open('wb') as stream:
            process = subprocess.Popen(cmd, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
            item['pid'] = process.pid
            next_capture = start + 2
            while process.poll() is None:
                now = time.monotonic()
                if now - start >= 240:
                    item['timeout'] = True
                    for owned_pid in reversed(owned_descendants(process.pid)):
                        if owned_pid != process.pid:
                            subprocess.run(['taskkill', '/PID', str(owned_pid), '/F'], capture_output=True)
                    process.kill()  # only this runner's process and proven descendants
                    break
                if now >= next_capture and len(item['screenshots']) < 3:
                    try:
                        pids = owned_descendants(process.pid)
                        item['owned_pids'] = sorted(set(item.get('owned_pids', [])) | set(pids))
                        for pid in pids:
                            shot = capture(pid, LOGS / (suite + '-capture-' + str(len(item['screenshots']) + 1) + '.bmp'))
                            if shot:
                                shot['pid'] = pid
                                item['screenshots'].append(shot)
                                break
                    except Exception as exc:
                        item.setdefault('capture_errors', []).append(repr(exc))
                    next_capture = now + 4
                time.sleep(0.1)
            item['exit_code'] = process.wait()
        item['elapsed_seconds'] = round(time.monotonic() - start, 3)
        text = log.read_text(encoding='utf-8', errors='replace')
        lines = text.splitlines()
        item['results'] = [line for line in lines if 'RESULT' in line]
        item['checks'] = [int(x) for line in item['results'] for x in re.findall(r'checks\s*=\s*(\d+)', line)]
        item['errors'] = [line for line in lines if re.search(r'SCRIPT ERROR|SHADER ERROR|^ERROR:|^FAIL\b|^CHECK .* false\s*$', line)]
        item['warnings'] = [line for line in lines if line.startswith('WARNING:')]
        item['status'] = 'pass' if item['exit_code'] == 0 and item['results'] and not item['errors'] and not item['timeout'] else 'failed_or_incomplete'
        report['suites'].append(item)
        (OUT / 'baseline-window.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        summary = ['A03 actual serial non-headless window baseline', 'Every command uses --fixed-fps 60 and -- window; 240s timeout per suite.', 'Raw output and exact process return codes retained.']
        for r in report['suites']:
            summary.extend(['', '== ' + r['suite'], 'command=' + subprocess.list2cmdline(r['command']), 'pid=%s exit_code=%s timeout=%s elapsed_seconds=%s status=%s' % (r['pid'], r['exit_code'], r['timeout'], r['elapsed_seconds'], r['status']), 'checks=' + str(r['checks']), *r['results'], 'errors:', *(r['errors'] or ['(none)']), 'warnings:', *(r['warnings'] or ['(none)']), 'screenshots=' + json.dumps(r['screenshots'], ensure_ascii=False), 'log=' + r['log']])
        (OUT / 'baseline-window.txt').write_text('\n'.join(summary) + '\n', encoding='utf-8')
        print(suite, item['exit_code'], item['checks'], item['results'], 'errors=',len(item['errors']), flush=True)
    assert len(report['suites']) == len(SUITES)
    report['finished_at'] = datetime.datetime.now().astimezone().isoformat()
    (OUT / 'baseline-window.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')

if __name__ == '__main__':
    # 这套基线全部是真窗口（不带 --headless），运行时会真的抢走鼠标/键盘。
    # 开始与结束各弹一条 Windows 通知，明确告诉用户此刻能不能操作电脑。
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from win_notify import window_occupancy
    with window_occupancy('窗口基线（A03 真窗口套件）', foreground_required=False):
        main()
