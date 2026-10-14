"""Owned outpost lifecycle migration; no full gate, GUI, or net long round."""
import sys
sys.dont_write_bytecode = True
import importlib.util
import json
import re
import shutil
import uuid
import difflib
from pathlib import Path
from collections import Counter

PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('r74_helpers', PROJECT/'tools/tests/test_round64_private_fixture_retirement.py')
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
a, r = h.a, h.r
REL = 'tests/outpost_identity_test.gd'
UNIT = 'newtests/round74_outpost_public_contract_test.gd'
NET = 'tests/net_v2_one_round_test.gd'
PRECHECK = '''\tcheck(GameProgress.current_player_id == local and GameProgress.current_phase_player_index == GameProgress.get_ordered_player_ids().find(local) + 1,"outpost fixture selects actor through phase lifecycle")
\tcheck(TimePointChecker.phase_time_points.has(TimePoints.OUTPOST_PHASE) and not TimePointChecker.phase_time_points.has(TimePoints.PREPARE_PHASE),"outpost fixture establishes matching fixed phase window")
\tcheck(d.current_time_points.has(TimePoints.SELF_PREFIX + TimePoints.OUTPOST_PHASE) and not d.current_time_points.has(TimePoints.SELF_PREFIX + TimePoints.PREPARE_PHASE),"outpost fixture establishes matching self phase window")
'''
OLD = '''\tGameProgress.current_phase_index=1
\tGameProgress.current_player_id=local
\tGameProgress._phase_end_pending=false
\tGameProgress._phase_end_running=false
\tGameLog.set_context(GameProgress.current_round,"outpost")
'''
NEW = '''\t# 公开复位取消旧局协程；正常阶段初始化同时建立日志、时点与行动者游标。
\tvar fixture_round:int=GameProgress.current_round
\tGameProgress.reset_progress()
\tGameProgress.current_round=fixture_round
\tGameProgress.current_phase_index=1
\tGameProgress.current_phase_player_index=GameProgress.get_ordered_player_ids().find(local)
\tGameProgress.begin_phase()
'''

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def candidate(text):
    if text.count(OLD)!=1: raise r.SafetyError('exact original lifecycle anchor not unique')
    return text.replace(OLD, NEW + PRECHECK)

def fragment(text, original):
    if original:
        if text.count(OLD)!=1: raise r.SafetyError('red lifecycle anchor')
        text=text.replace(OLD, OLD+PRECHECK)
    cut='\tRemoveFromBoard.new().exec(local)'
    if text.count(cut)!=1: raise r.SafetyError('fragment cut')
    return text.split(cut)[0]+'\tprint("RESULT checks=",checks," failures=",failures)\n\tget_tree().quit(0 if failures.is_empty() else 1)\n'

def scene(m, text, label):
    owner=Path(m['owner']); gen=owner/'generated'; target=gen/'project'
    rel='tests/r74_owned_probe.gd'
    (target/rel).write_text(text,encoding='utf-8',newline='')
    scene_path=target/'tests/r74_owned_probe.tscn'
    scene_path.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://'+rel+'" id="1"]\n[node name="Probe" type="Node"]\nscript = ExtResource("1")\n',encoding='utf-8')
    command=[str(gen/'Godot.exe'),'--headless','--fixed-fps','60','--path',str(target),'--scene','res://tests/r74_owned_probe.tscn']
    out,err,code=h.execute(m,command,label)
    row=dict(a.analyze(out,err,code),label=label,exit_code=code,command=command,executed=True)
    m['suites'].append(row); save(owner/'manifest.json',m)
    print(json.dumps({'label':label,'exit':code,'checks':row['observed_checks'],'passed':row['passed'],'errors':row['errors']},ensure_ascii=False),flush=True)
    return row

def prepare():
    r.physical_e(h.ROOT); r.physical_e(h.ENGINE)
    baseline=a.load(h.OLD)
    owner=h.ROOT/('round74-outpost-'+uuid.uuid4().hex); owner.mkdir()
    gen=owner/'generated'; gen.mkdir(); evidence=owner/'evidence'; evidence.mkdir()
    save(owner/'owner.json',{'token':owner.name,'generated':str(gen)})
    m={'owner':str(owner),'phase':'preparing','passed':False,'processes':[],'suites':[],'timeout':180,'net_long_round':'not_run_no_public_reason_equivalence'}
    try:
        paths={p for p in baseline['freeze_before'] if not p.startswith('tests/')}
        paths.update(p.relative_to(PROJECT).as_posix() for p in (PROJECT/'scripts').rglob('*') if p.is_file() and p.suffix in {'.gd','.uid'})
        paths.update([REL,UNIT,NET,'tests/outpost_identity_test.tscn'])
        m['source_hashes']={p:a.digest(PROJECT/p) for p in sorted(paths)}
        m['engine_sha256']=a.digest(h.ENGINE)
        if m['engine_sha256']!=baseline['engine_sha256']: raise r.SafetyError('engine drift')
        target=gen/'project'
        m['native_old_hashes']={}
        for p in sorted(paths):
            src=r.contained(PROJECT/p,PROJECT); dst=target/p
            if src.suffix=='.dll':
                expected=baseline['freeze_before'][p]
                if m['source_hashes'][p]!=expected: raise r.SafetyError('old native DLL drift: '+p)
                m['native_old_hashes'][p]=expected
            dst.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(src,dst)
            if a.digest(dst)!=m['source_hashes'][p] or a.digest(src)!=m['source_hashes'][p]: raise r.SafetyError('freeze drift: '+p)
        original=(target/REL).read_bytes(); (evidence/'original.gd').write_bytes(original)
        changed=candidate(original.decode('utf-8-sig'))
        (evidence/'candidate.gd').write_text(changed,encoding='utf-8',newline='')
        (evidence/'unit.gd').write_bytes((target/UNIT).read_bytes())
        m['source_fingerprint']=a.round50_source_fingerprint(m['source_hashes'])
        config=(target/'project.godot').read_text(encoding='utf-8-sig')
        if (PROJECT/'override.cfg').exists() or 'config/project_settings_override=' in config: raise r.SafetyError('project override')
        transformed,m['editor_transform']=a.transform_isolated_editor_vcs(config)
        (target/'project.godot').write_text(transformed,encoding='utf-8')
        shutil.copyfile(h.ENGINE,gen/'Godot.exe')
        probe=gen/'probe'; probe.mkdir()
        app=re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)
        thread=re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)
        pc='config_version=5\n[application]\n'+re.sub(r'^run/main_scene=.*\n','',app[1],flags=re.M)
        if thread: pc+='\n[threading]\n'+thread[1]
        (probe/'project.godot').write_text(pc,encoding='utf-8'); (probe/'probe.gd').write_text(r.PROBE_SCRIPT,encoding='utf-8')
        out,err,code=h.execute(m,[str(gen/'Godot.exe'),'--headless','--path',str(probe),'--script','res://probe.gd','--',owner.name,'main',str(gen)],'user-probe')
        if code or re.search(r'SCRIPT ERROR|ERROR:',out+err): raise r.SafetyError('user probe failed')
        m['user_probes']=r.verify_probe(out,gen,owner.name)
        out,err,code=h.execute(m,[str(gen/'Godot.exe'),'--headless','--editor','--import','--path',str(target)],'selected-import')
        m['import']={'exit':code,'errors':[line for line in (out+err).splitlines() if re.search(r'SCRIPT ERROR|ERROR:',line)]}
        if code or m['import']['errors']: raise r.SafetyError('selected import failed')
        red=scene(m,fragment(original.decode('utf-8-sig'),True),'old-fixture-precondition-RED')
        log=(evidence/'old-fixture-precondition-RED.stdout.log').read_text(encoding='utf-8')
        expected=['outpost fixture establishes matching fixed phase window','outpost fixture establishes matching self phase window']
        m['red_valid']=red['exit_code']==1 and not red['errors'] and all('CHECK '+label+' false' in log for label in expected)
        if not m['red_valid']: raise r.SafetyError('RED not expected precondition failure')
        m['phase']='valid_RED_before_source_write'
    except Exception as exc:
        m['error']=type(exc).__name__+': '+str(exc)
    save(owner/'manifest.json',m)
    print(json.dumps({'manifest':str(owner/'manifest.json'),'phase':m['phase'],'error':m.get('error')},ensure_ascii=False))
    return 0 if m['phase']=='valid_RED_before_source_write' else 1

def accept_archived_red(path):
    path=r.contained(Path(path),r.physical_e(h.ROOT)); owner=path.parent
    if not re.fullmatch(r'round74-outpost-[a-f0-9]{32}',owner.name): raise r.SafetyError('owner identity')
    m=a.load(path)
    if m['phase']!='preparing' or m.get('error')!="KeyError: 'results'": raise r.SafetyError('only known reporting error may resume')
    out=(owner/'evidence/old-fixture-precondition-RED.stdout.log').read_text(encoding='utf-8')
    err=(owner/'evidence/old-fixture-precondition-RED.stderr.log').read_text(encoding='utf-8')
    red=a.analyze(out,err,m['suites'][-1]['exit_code'])
    expected=['outpost fixture selects actor through phase lifecycle','outpost fixture establishes matching fixed phase window','outpost fixture establishes matching self phase window']
    if m['suites'][-1]['exit_code']!=1 or red['errors'] or red['observed_checks']!=5 or not all('CHECK '+label+' false' in out for label in expected): raise r.SafetyError('archived RED invalid')
    m['historical_runner_error']=m.pop('error'); m['red_valid']=True; m['phase']='valid_RED_before_source_write'
    save(path,m)
    print(json.dumps({'manifest':str(path),'phase':m['phase'],'red_exit':1,'red_checks':5,'rerun':False}))
    return 0


def verify(path):
    path=r.contained(Path(path),r.physical_e(h.ROOT)); owner=path.parent
    if not re.fullmatch(r'round74-outpost-[a-f0-9]{32}',owner.name): raise r.SafetyError('owner identity')
    m=a.load(path); gen=owner/'generated'; evidence=owner/'evidence'
    if m['phase']!='valid_RED_before_source_write': raise r.SafetyError('verification phase')
    current=(PROJECT/REL).read_bytes()
    if current!=(evidence/'candidate.gd').read_bytes(): raise r.SafetyError('formal candidate byte mismatch')
    if a.digest(PROJECT/UNIT)!=m['source_hashes'][UNIT]: raise r.SafetyError('unit drift')
    checks=lambda text: Counter(x.strip() for x in text.splitlines() if x.strip().startswith('check('))
    original=(evidence/'original.gd').read_text(encoding='utf-8-sig'); changed=current.decode('utf-8-sig')
    missing=checks(original)-checks(changed)
    m['assertion_preservation']={'missing':list(missing.elements()),'added':list((checks(changed)-checks(original)).elements())}
    if missing: raise r.SafetyError('original assertion removed')
    try:
        if not scene(m,fragment(changed,False),'public-fixture-precondition-GREEN')['passed']: raise r.SafetyError('fixture GREEN failed')
        if not scene(m,(evidence/'unit.gd').read_text(encoding='utf-8-sig'),'public-lifecycle-query-messages-GREEN')['passed']: raise r.SafetyError('public contract GREEN failed')
        # Run the actual formal scene once, with original identity/zone assertions intact.
        (gen/'project'/REL).write_bytes(current)
        cmd=[str(gen/'Godot.exe'),'--headless','--fixed-fps','60','--path',str(gen/'project'),'--scene','res://tests/outpost_identity_test.tscn']
        out,err,code=h.execute(m,cmd,'formal-outpost-once-GREEN')
        row=dict(a.analyze(out,err,code),label='formal-outpost-once-GREEN',exit_code=code,command=cmd,executed=True)
        m['suites'].append(row)
        print(json.dumps({'label':row['label'],'exit':code,'passed':row['passed'],'checks':row['observed_checks'],'errors':row['errors']},ensure_ascii=False),flush=True)
        if not row['passed']: raise r.SafetyError('formal outpost failed')
        m['phase']='verified_selected_green'; m['passed']=True
    except Exception as exc:
        m['error']=type(exc).__name__+': '+str(exc)
    m['current_source_sha256']=a.digest(PROJECT/REL)
    m['net_source_sha256']=a.digest(PROJECT/NET)
    m['net_unchanged']=m['net_source_sha256']==m['source_hashes'][NET]
    m['unowned_source_drift']=[p for p,hashval in m['source_hashes'].items() if p!=REL and a.digest(PROJECT/p)!=hashval]
    m['all_owned_job0']=all(x.get('exited') and x.get('active_owned_processes')==0 and x.get('log_handles_released') for x in m['processes'])
    m['retired_anchors']=[{'path':REL,'target':target,'line':i,'code':line.strip(),'count':1} for i,line in enumerate(original.splitlines(),1) for target in ['GameProgress._phase_end_pending','GameProgress._phase_end_running'] if target in line]
    m['remaining_net_anchor']=[{'path':NET,'line':i,'code':line.strip()} for i,line in enumerate((PROJECT/NET).read_text(encoding='utf-8-sig').splitlines(),1) if 'GameProgress._action_completion_block_reason' in line]
    (evidence/'migration.patch').write_text(''.join(difflib.unified_diff(original.splitlines(True),changed.splitlines(True),fromfile='original/'+REL,tofile='current/'+REL)),encoding='utf-8',newline='')
    m['logs']=[{'path':str(p.relative_to(evidence)),'sha256':a.digest(p)} for p in evidence.rglob('*.log')]
    save(path,m)
    if m['all_owned_job0']:
        token=a.load(owner/'owner.json')
        if token!={'token':owner.name,'generated':str(gen)}: raise r.SafetyError('cleanup token')
        r.no_links(gen)
        r.tree_bytes(gen)
        shutil.rmtree(gen)
        m['cleanup']='generated_removed'; save(path,m)
    print(json.dumps({'manifest':str(path),'phase':m['phase'],'passed':m['passed'],'drift':m['unowned_source_drift'],'net_unchanged':m['net_unchanged'],'job0':m['all_owned_job0'],'error':m.get('error')},ensure_ascii=False))
    return 0 if m['passed'] and m['all_owned_job0'] and m['net_unchanged'] else 1

def readback(path):
    path=r.contained(Path(path),r.physical_e(h.ROOT)); owner=path.parent
    if not re.fullmatch(r'round74-outpost-[a-f0-9]{32}',owner.name): raise r.SafetyError('owner identity')
    m=a.load(path); gen=owner/'generated'; evidence=owner/'evidence'
    if m['phase']!='verified_selected_green' or not m['all_owned_job0']: raise r.SafetyError('not verified or Job not zero')
    log_drift=[x['path'] for x in m['logs'] if a.digest(evidence/x['path'])!=x['sha256']]
    if log_drift: raise r.SafetyError('archive log drift')
    if a.digest(PROJECT/REL)!=m['current_source_sha256'] or a.digest(PROJECT/NET)!=m['net_source_sha256']: raise r.SafetyError('formal source drift')
    if gen.exists():
        if a.load(owner/'owner.json')!={'token':owner.name,'generated':str(gen)}: raise r.SafetyError('cleanup token')
        r.no_links(gen); r.tree_bytes(gen); shutil.rmtree(gen)
        m['cleanup']='generated_removed'
        m['historical_cleanup_runner_error']='AttributeError: no_reparse_ancestors; fixed to existing no_links/tree_bytes; no scene rerun'
        save(path,m)
    rows=[{'label':x['label'],'exit':x['exit_code'],'actual_checks':x['observed_checks'],'declared_checks':x['result']['checks'],'failures':x['result']['failures'],'errors':x['errors']} for x in m['suites']]
    receipt={'manifest':str(path),'manifest_sha256':a.digest(path),'freeze_fingerprint':m['source_fingerprint'],'source_count':len(m['source_hashes']),'original_sha256':a.digest(evidence/'original.gd'),'current_sha256':a.digest(PROJECT/REL),'net_unchanged_sha256':a.digest(PROJECT/NET),'unit_sha256':a.digest(PROJECT/UNIT),'runner_sha256':a.digest(Path(__file__)),'patch_sha256':a.digest(evidence/'migration.patch'),'engine_sha256':m['engine_sha256'],'native_count':len(m['native_old_hashes']),'retired_anchors':m['retired_anchors'],'scenes':rows,'assertions':m['assertion_preservation'],'log_drift':log_drift,'source_drift_now':[p for p,hashval in m['source_hashes'].items() if p!=REL and a.digest(PROJECT/p)!=hashval],'job0':m['all_owned_job0'],'cleanup':m['cleanup'],'generated_exists':gen.exists(),'net_long_round':m['net_long_round'],'issues':[m.get('historical_runner_error'),m.get('historical_cleanup_runner_error')]}
    receipt['passed']=m['passed'] and not receipt['generated_exists'] and not receipt['log_drift'] and receipt['job0'] and not receipt['assertions']['missing']
    save(evidence/'readback.json',receipt)
    print(json.dumps(receipt,ensure_ascii=False,indent=2))
    return 0 if receipt['passed'] else 1


if __name__=='__main__':
    if len(sys.argv)==1: sys.exit(prepare())
    if len(sys.argv)==3 and sys.argv[1]=='--accept-archived-red': sys.exit(accept_archived_red(sys.argv[2]))
    if len(sys.argv)==3 and sys.argv[1]=='--readback': sys.exit(readback(sys.argv[2]))
    if len(sys.argv)==3 and sys.argv[1]=='--verify': sys.exit(verify(sys.argv[2]))
    raise SystemExit('usage: runner [--verify manifest.json]')
