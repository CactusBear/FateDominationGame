"""Exact-owned HWND real OS input after CUA foreground escalation."""
import ctypes, json, time, argparse
from ctypes import wintypes
from pathlib import Path
u = ctypes.windll.user32
u.SetProcessDPIAware()
class MOUSEINPUT(ctypes.Structure):
    _fields_=[('dx',wintypes.LONG),('dy',wintypes.LONG),('mouseData',wintypes.DWORD),('dwFlags',wintypes.DWORD),('time',wintypes.DWORD),('dwExtraInfo',ctypes.c_size_t)]
class KEYBDINPUT(ctypes.Structure):
    _fields_=[('wVk',wintypes.WORD),('wScan',wintypes.WORD),('dwFlags',wintypes.DWORD),('time',wintypes.DWORD),('dwExtraInfo',ctypes.c_size_t)]
class UNION(ctypes.Union):
    _fields_=[('mi',MOUSEINPUT),('ki',KEYBDINPUT),('padding',ctypes.c_byte*32)]
class INPUT(ctypes.Structure):
    _fields_=[('type',wintypes.DWORD),('data',UNION)]
u.SendInput.argtypes=[wintypes.UINT,ctypes.POINTER(INPUT),ctypes.c_int]
ROOT=Path('E:/scratch/continuous-next-wave/ui-final')
def state():
    for _ in range(20):
        try:return json.loads((ROOT/'window-state.json').read_text(encoding='utf-8'))
        except (ValueError,OSError):time.sleep(.02)
    raise RuntimeError('state unavailable')
def point(h,x,y):
    p=wintypes.POINT(round(x),round(y));u.ClientToScreen(h,ctypes.byref(p))
    # Godot's viewport can be DPI-scaled inside the HWND client area. Read the
    # application's real OS mouse position back; do not guess from desktop DPI.
    for _ in range(8):
        u.SetCursorPos(p.x,p.y);time.sleep(.08)
        observed=state().get('mouse_position')
        if observed is None:return [p.x,p.y]
        dx=round(x-observed[0]);dy=round(y-observed[1])
        if abs(dx)<=1 and abs(dy)<=1:return [p.x,p.y]
        p.x+=dx;p.y+=dy
    raise RuntimeError('OS viewport coordinate calibration failed: '+str(observed))
def mouse(flag):
    i=INPUT();i.type=0;i.data.mi.dwFlags=flag
    if u.SendInput(1,ctypes.byref(i),ctypes.sizeof(i))!=1:raise ctypes.WinError()
def main():
    p=argparse.ArgumentParser();p.add_argument('--pid',type=int,required=True);p.add_argument('--hwnd',type=int,required=True);p.add_argument('--target',required=True);p.add_argument('--hover',action='store_true');a=p.parse_args()
    got=wintypes.DWORD();u.GetWindowThreadProcessId(a.hwnd,ctypes.byref(got));assert got.value==a.pid and u.IsWindow(a.hwnd),'not owned live target'
    u.ShowWindow(a.hwnd,4);u.SetForegroundWindow(a.hwnd);time.sleep(.15)
    assert u.GetForegroundWindow()==a.hwnd,'exact target not foreground; no input sent'
    if a.target in ['history','card-gold']:point(a.hwnd,910,1040);time.sleep(1.0)
    if a.target in ['effect-both','card-both']:point(a.hwnd,1110,1040);time.sleep(1.0)
    previous=None;trace=[]
    for _ in range(25):
        d=state();r=[930,930,2,2] if a.target=='hand-space' else d['targets'].get(a.target)
        if not r:raise RuntimeError('target not visible: '+a.target)
        left=max(0,r[0]);right=min(1920,r[0]+r[2]);top=max(0,r[1]);bottom=min(1080,r[1]+r[3])
        assert right>left and bottom>top,'target has no visible viewport intersection'
        centre=[(left+right)/2,(top+bottom)/2];trace.append(centre)
        point(a.hwnd,*centre);time.sleep(.10)
        if previous and max(abs(x-y) for x,y in zip(centre,previous))<1:break
        previous=centre
    before=state()
    latest=[930,930,2,2] if a.target=='hand-space' else before['targets'].get(a.target)
    observed=before.get('mouse_position')
    if not a.hover and latest and observed:
        assert latest[0]-2<=observed[0]<=latest[0]+latest[2]+2 and latest[1]-2<=observed[1]<=latest[1]+latest[3]+2,'pointer no longer inside the exact moving target; no click'
    assert u.GetForegroundWindow()==a.hwnd,'focus changed; no click'
    if not a.hover:mouse(0x0002);time.sleep(.05);mouse(0x0004)
    time.sleep(.2);after=state()
    result={'pid':a.pid,'hwnd':a.hwnd,'target':a.target,'hover_only':a.hover,'client_target_trace':trace,'os_input':'SendInput' if not a.hover else 'SetCursorPos','before':before,'after':after}
    import hashlib
    out=ROOT/('os-input-'+hashlib.sha256(a.target.encode('utf-8')).hexdigest()[:16]+'-'+str(time.time_ns())+'.json');out.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'evidence':str(out),'before_history':before['history_visible'],'after_history':after['history_visible'],'downs':after['downs'],'stage':after['stage']},ensure_ascii=False))
if __name__=='__main__':main()
