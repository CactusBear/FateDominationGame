"""Owned HWND-only desktop client crop; no focus change or OS input."""
import ctypes as c
from ctypes import wintypes as w
import hashlib, json, struct, threading, time, zlib
from pathlib import Path

def capture(pid, output):
    if pid in (17120, 28100): raise ValueError('protected PID')
    u=c.WinDLL('user32',use_last_error=True); g=c.WinDLL('gdi32',use_last_error=True)
    u.SetThreadDpiAwarenessContext.argtypes=[c.c_void_p]; u.SetThreadDpiAwarenessContext.restype=c.c_void_p
    u.SetThreadDpiAwarenessContext(c.c_void_p(-4))
    callback=c.WINFUNCTYPE(w.BOOL,w.HWND,w.LPARAM)
    u.EnumWindows.argtypes=[callback,w.LPARAM]
    u.GetWindowThreadProcessId.argtypes=[w.HWND,c.POINTER(w.DWORD)]
    u.IsWindowVisible.argtypes=[w.HWND]; u.GetForegroundWindow.restype=w.HWND
    found=[]
    @callback
    def visit(hwnd, unused):
        owner=w.DWORD(); u.GetWindowThreadProcessId(hwnd,c.byref(owner))
        if owner.value==pid and u.IsWindowVisible(hwnd): found.append(hwnd)
        return True
    u.EnumWindows(visit,0)
    if len(found)!=1: raise ValueError('owned visible HWND count: '+str(len(found)))
    hwnd=found[0]
    foreground = u.GetForegroundWindow()==hwnd
    u.PrintWindow.argtypes=[w.HWND,w.HDC,w.UINT]
    rect=w.RECT(); origin=w.POINT(0,0)
    u.GetClientRect.argtypes=[w.HWND,c.POINTER(w.RECT)]; u.ClientToScreen.argtypes=[w.HWND,c.POINTER(w.POINT)]
    u.GetClientRect(hwnd,c.byref(rect)); u.ClientToScreen(hwnd,c.byref(origin))
    width,height=rect.right,rect.bottom
    if not 0<width<=8192 or not 0<height<=8192: raise ValueError('bad client bounds')
    u.GetDC.argtypes=[w.HWND]; u.GetDC.restype=w.HDC
    u.ReleaseDC.argtypes=[w.HWND,w.HDC]
    g.CreateCompatibleDC.argtypes=[w.HDC]; g.CreateCompatibleDC.restype=w.HDC
    g.CreateCompatibleBitmap.argtypes=[w.HDC,c.c_int,c.c_int]; g.CreateCompatibleBitmap.restype=w.HBITMAP
    g.SelectObject.argtypes=[w.HDC,w.HGDIOBJ]; g.SelectObject.restype=w.HGDIOBJ
    g.BitBlt.argtypes=[w.HDC,c.c_int,c.c_int,c.c_int,c.c_int,w.HDC,c.c_int,c.c_int,w.DWORD]
    g.DeleteObject.argtypes=[w.HGDIOBJ]; g.DeleteDC.argtypes=[w.HDC]
    class Header(c.Structure):
        _fields_=[('size',w.DWORD),('width',w.LONG),('height',w.LONG),('planes',w.WORD),('bit_count',w.WORD),('compression',w.DWORD),('size_image',w.DWORD),('x',w.LONG),('y',w.LONG),('used',w.DWORD),('important',w.DWORD)]
    class Info(c.Structure): _fields_=[('header',Header),('colors',w.DWORD*3)]
    g.GetDIBits.argtypes=[w.HDC,w.HBITMAP,w.UINT,w.UINT,c.c_void_p,c.POINTER(Info),w.UINT]
    desktop=u.GetDC(None); dc=g.CreateCompatibleDC(desktop); bitmap=g.CreateCompatibleBitmap(desktop,width,height); previous=g.SelectObject(dc,bitmap)
    try:
        method = 'PrintWindow PW_CLIENTONLY|PW_RENDERFULLCONTENT; exact owned HWND; no focus/input'
        if not u.PrintWindow(hwnd,dc,3):
            if not foreground: raise ValueError('PrintWindow failed and background desktop crop forbidden')
            if not g.BitBlt(dc,0,0,width,height,desktop,origin.x,origin.y,0x00CC0020|0x40000000): raise OSError(c.get_last_error())
            method = 'GDI composited desktop client crop; exact foreground owned HWND; no focus/input'
        info=Info(); info.header=Header(c.sizeof(Header),width,-height,1,32,0,0,0,0,0,0)
        raw=c.create_string_buffer(width*height*4)
        if g.GetDIBits(dc,bitmap,0,height,raw,c.byref(info),0)!=height: raise OSError('GetDIBits')
        bgra=raw.raw; rgb=bytearray(width*height*3)
        rgb[0::3]=bgra[2::4]; rgb[1::3]=bgra[1::4]; rgb[2::3]=bgra[0::4]
        def chunk(kind,data): return struct.pack('!I',len(data))+kind+data+struct.pack('!I',zlib.crc32(kind+data)&0xffffffff)
        scan=b''.join(b'\0'+rgb[y*width*3:(y+1)*width*3] for y in range(height))
        png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',width,height,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(scan))+chunk(b'IEND',b'')
        output.parent.mkdir(parents=True,exist_ok=True); output.write_bytes(png)
        return {'ok':True,'pid':pid,'hwnd':hwnd,'path':str(output),'sha256':hashlib.sha256(png).hexdigest(),'client_physical':[origin.x,origin.y,width,height],'capture':method,'foreground':foreground}
    finally:
        g.SelectObject(dc,previous); g.DeleteObject(bitmap); g.DeleteDC(dc); u.ReleaseDC(None,desktop)

def wrap_execute(original):
    def execute(command,env,cwd,evidence,label,budgets,processes):
        if '--' not in command or 'window' not in command: return original(command,env,cwd,evidence,label,budgets,processes)
        project=Path(command[command.index('--path')+1]); folder=project/'tests/runtime_reports'
        stop=threading.Event(); records=[]; seen=set()
        def watch():
            while not stop.is_set():
                for marker in folder.glob('*.native-ready.json'):
                    if marker.name in seen: continue
                    seen.add(marker.name); data=json.loads(marker.read_text(encoding='utf-8'))
                    try: result=capture(data['pid'],Path(evidence)/'native-window'/data['filename'])
                    except Exception as exc: result={'ok':False,'phase':data['filename'],'error':repr(exc)}
                    records.append(result)
                    marker.with_name(marker.name.replace('.native-ready.json','.native-ack.json')).write_text(json.dumps(result),encoding='utf-8')
                stop.wait(0.05)
        thread=threading.Thread(target=watch,daemon=True); thread.start()
        child_env=env.copy(); child_env['FD_T18_NATIVE_WINDOW']='1'
        try: return original(command,child_env,cwd,evidence,label,budgets,processes)
        finally:
            stop.set(); thread.join(timeout=10)
            (Path(evidence)/'native-window-captures.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
    return execute
