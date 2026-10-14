"""Real OS acceptance orchestration; every input is exact-owned SendInput."""
import json, time, sys, subprocess, ctypes
from pathlib import Path
import ui_final_os_input as inp
ROOT=inp.ROOT
OWNED_LABEL='os-window-complete'
def wait(predicate,seconds=15):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        d=inp.state()
        if predicate(d):return d
        time.sleep(.1)
    raise RuntimeError('state condition not reached: '+json.dumps(d,ensure_ascii=False))
def command(s):
    (ROOT/'window-command.txt').write_text(s,encoding='utf-8')
    time.sleep(.2)
def verify(s):
    n=inp.state()['checks'];command(s)
    d=wait(lambda d:d['checks']>n)
    if d['failures']:raise RuntimeError('failed acceptance '+str(d['failures']))
    print('VERIFIED',s,'checks',d['checks'],flush=True)
def shot(s):
    command('shot-'+s)
    p=ROOT/('shot-'+s+'.png')
    end=time.monotonic()+10
    while time.monotonic()<end:
        if p.exists() and p.stat().st_size>1000:return str(p)
        time.sleep(.1)
    raise RuntimeError('missing real window frame '+str(p))
def main():
    info=json.loads((ROOT/(OWNED_LABEL+'.json')).read_text());pid=info['pid']
    u=ctypes.windll.user32
    found=[]
    CB=ctypes.WINFUNCTYPE(ctypes.c_bool,ctypes.c_void_p,ctypes.c_void_p)
    def enum(h,l):
        p=ctypes.c_ulong();u.GetWindowThreadProcessId(h,ctypes.byref(p))
        if p.value==pid and u.IsWindowVisible(h):found.append(h)
        return True
    u.EnumWindows(CB(enum),0)
    if len(found)!=1:raise RuntimeError('exact owner window ambiguity '+str(found))
    hwnd=found[0];print('EXACT_OWNED',pid,hwnd,flush=True)
    def click(target,hover=False):
        args=[sys.executable,'-B',str(Path(__file__).with_name('ui_final_os_input.py')),'--pid',str(pid),'--hwnd',str(hwnd),'--target',target]
        if hover:args.append('--hover')
        r=subprocess.run(args,capture_output=True,text=True)
        print(r.stdout,r.stderr,flush=True)
        if r.returncode:raise RuntimeError('real OS input failed '+target)
    captures=[]
    try:
        wait(lambda d:d['stage']=='local' and len(d['frames'])==4)
        verify('verify-initial')
        click('hand-space',True);captures.append(shot('fixed-four-states-occlusion'))
        click('card-gold');verify('verify-selected');captures.append(shot('fixed-gold-selected-white'))
        click('card-gold')
        click('effect-both');verify('verify-effect-selected');captures.append(shot('fixed-purple-selected-white'))
        click('ModalLayer/EffectChoice/Box/ButtonsRow/BtnCancel');verify('verify-effect-cancel')
        click('own_spell');verify('verify-spell-open');captures.append(shot('self-spell-authorized'))
        click('ModalLayer/EffectChoice/Box/ButtonsRow/BtnCancel');verify('verify-spell-cancel')
        click('own_spell')
        option=next(k for k in inp.state()['targets'] if k.endswith(':行动阶段：获得4魔力'))
        click(option);verify('verify-spell-confirm');captures.append(shot('self-spell-confirmed-own-cost-once'))
        command('deny');wait(lambda d:d['own_spell_count']==0)
        click('own_spell');verify('verify-deny')
        click('rival_spell');verify('verify-rival');captures.append(shot('rival-information-only'))
        command('network');wait(lambda d:d['stage']=='network-history')
        click('history');verify('verify-network-history');captures.append(shot('network-history-authorized'))
        command('revoke-network');wait(lambda d:d['stage']=='network-revoked');verify('verify-network-revoked');captures.append(shot('network-history-revoked'))
        command('network-played');wait(lambda d:d['stage']=='network-played' and 'played_history' in d['targets'])
        click('played_history');verify('verify-played-history');captures.append(shot('network-first-played-history'))
        before=inp.state();command('finish')
        result={'complete':True,'pid':pid,'hwnd':hwnd,'captures':captures,'last_state':before}
        (ROOT/'os-complete-orchestration.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        print('OS_ACCEPT_COMPLETE',json.dumps(result,ensure_ascii=False),flush=True)
    except Exception as e:
        (ROOT/'os-complete-orchestration.json').write_text(json.dumps({'complete':False,'error':repr(e),'captures':captures,'state':inp.state()},ensure_ascii=False,indent=2),encoding='utf-8')
        command('finish')
        raise
if __name__=='__main__':main()
