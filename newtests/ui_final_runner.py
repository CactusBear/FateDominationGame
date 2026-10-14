"""Owned E-drive freeze, bounded natural-exit runs, no terminate/kill."""
import os, sys, json, hashlib, subprocess, shutil, importlib.util, re
from pathlib import Path
ROOT = Path('E:/scratch/continuous-next-wave/ui-final')
REPO = Path(__file__).resolve().parents[1]
GEN = ROOT / 'generated'
PROJECT = GEN / 'project'
ENGINE = GEN / 'UIFinalGodot.exe'
TARGETS = ['scripts/game_scene/battle_board_v2.gd', 'assets/scenes/game_scene/battle_board_v2.tscn', 'scripts/net/ui/v2_view_presenter.gd']
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def env():
    e = os.environ.copy()
    for key in ['TMPDIR','TEMP','TMP','APPDATA','LOCALAPPDATA']:
        p = GEN / 'environment' / key.lower(); p.mkdir(parents=True,exist_ok=True); e[key] = str(p)
    e['FATE_TEST_SCRATCH_ROOT'] = str(GEN / 'fixtures')
    e.pop('HERMES_RECOVERY_VALIDATION_ROOT',None)
    return e
def _run(label,scene,window=False,importing=False):
    outp = ROOT / (label+'.stdout.txt'); errp = ROOT / (label+'.stderr.txt')
    command = [str(ENGINE),'--path',str(PROJECT),'--quit-after','108000' if window else '10800','--max-fps','60']
    command += ['--headless','--editor','--import'] if importing else (([] if window else ['--headless'])+['--fixed-fps','60','--scene','res://'+scene])
    if window: command += ['--','window']
    rec = {'command':command,'isolated_environment':{k:env()[k] for k in ['TMPDIR','TEMP','TMP','APPDATA','LOCALAPPDATA']}}
    with outp.open('wb') as out, errp.open('wb') as err:
        p = subprocess.Popen(command,cwd=GEN,env=env(),stdout=out,stderr=err)
        rec['pid'] = p.pid
        (ROOT/(label+'.json')).write_text(json.dumps(rec,indent=2),encoding='utf-8')
        print('OWNED_PID',p.pid,flush=True)
        try: rec['exit'] = p.wait(timeout=1900 if window else 180)
        except subprocess.TimeoutExpired:
            rec['timeout'] = True
            print('NO_KILL_TIMEOUT',p.pid,flush=True)
    text = outp.read_text(encoding='utf-8',errors='replace')+'\n'+errp.read_text(encoding='utf-8',errors='replace')
    rec['results'] = [line for line in text.splitlines() if line.startswith('RESULT ')]
    rec['errors'] = re.findall(r'^.*(?:SCRIPT ERROR|SHADER ERROR|ERROR:).*$',text,re.M)
    rec['source_target_sha'] = {s:sha(REPO/s) for s in TARGETS}
    rec['frozen_target_sha'] = {s:sha(PROJECT/s) for s in TARGETS}
    (ROOT/(label+'.json')).write_text(json.dumps(rec,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(rec,ensure_ascii=False),flush=True)
    return rec.get('exit',1) if not rec['errors'] and (importing or rec['results']) else 1
def run(label,scene,window=False,importing=False):
    if not window:
        return _run(label,scene,window=False,importing=importing)
    sys.path.insert(0,str(REPO/'tools'))
    from win_notify import occupy_start, occupy_end
    os.environ.update({k:env()[k] for k in ['TMPDIR','TEMP','TMP','APPDATA','LOCALAPPDATA']})
    notices = {'start':occupy_start('UI 窗口验收',foreground_required=True)}
    print('WINDOW_NOTIFY_START',notices['start'],flush=True)
    code = 1
    try:
        code = _run(label,scene,window=True,importing=importing)
        return code
    finally:
        notices['end'] = occupy_end('UI 窗口验收',ok=code==0)
        print('WINDOW_NOTIFY_END',notices['end'],'ok=',code==0,flush=True)
        (ROOT/(label+'.notifications.json')).write_text(json.dumps(notices,ensure_ascii=False,indent=2),encoding='utf-8')

if __name__ == '__main__':
    ROOT.mkdir(parents=True,exist_ok=True)
    mode = sys.argv[1]
    if mode == 'prepare':
        if PROJECT.exists(): raise RuntimeError('owned freeze already exists')
        spec = importlib.util.spec_from_file_location('isolation',REPO/'tools/run_isolated_godot_test.py')
        m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
        includes = ['project.godot','scripts','assets','data','game_data','addons','json_maker','icon.svg','newtests']
        files = list(m.source_files(REPO,includes))
        before = {p.as_posix():sha(REPO/p) for p in files}
        for p in files:
            dest = PROJECT/p; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(REPO/p,dest)
        (ROOT/'freeze.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
        for s in TARGETS:
            (ROOT/(Path(s).name+'.before.txt')).write_bytes((REPO/s).read_bytes())
        shutil.copyfile('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe',ENGINE)
        spec = importlib.util.spec_from_file_location('transform',REPO/'tools/tests/test_round29_integrated_evidence.py')
        t = importlib.util.module_from_spec(spec); spec.loader.exec_module(t)
        config,_ = t.transform_isolated_editor_vcs((PROJECT/'project.godot').read_text(encoding='utf-8-sig'))
        (PROJECT/'project.godot').write_text(config,encoding='utf-8')
        print('COPIED',len(files),'DRIFT',[s for s in TARGETS if sha(REPO/s)!=before[s]],flush=True)
        sys.exit(run('import','',importing=True))
    elif mode == 'sync':
        for s in TARGETS:
            shutil.copyfile(REPO/s,PROJECT/s)
        for p in (REPO/'newtests').glob('ui_final*'):
            if p.is_file(): shutil.copyfile(p,PROJECT/'newtests'/p.name)
        print('SYNC', {s:sha(PROJECT/s) for s in TARGETS})
    elif mode == 'run': sys.exit(run(sys.argv[2],sys.argv[3],window='--window' in sys.argv))
