"""Round71 one-shot current-source sample. Production and old fixtures are readonly.

No live content scanner, recovery/identity payload reader, debugger attach, retry,
new delay or alternate publication. A missing safe observer remains an evidence gap.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time
import uuid

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[2]
ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
ENGINE_SHA = 'ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424'
DLL = 'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll'
DLL_SHA = '92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd'
SUITES = [('validation_stage_timing_test',600,None),
          ('server_shutdown_close_handoff_test',180,86),
          ('server_shutdown_close_handoff_pending_test',180,36),
          ('net_server_shutdown_failure_test',180,161)]
ERROR = re.compile(r'ERROR|SHADER ERROR|CAPTURE_BLOCK|SECOND_CHANCE|^\s*FAIL\b')


def digest(p):
    with Path(p).open('rb') as f:
        return hashlib.file_digest(f,'sha256').hexdigest()


def save(p,v):
    p.parent.mkdir(parents=True,exist_ok=True)
    raw=json.dumps(v,ensure_ascii=False,indent=2).encode('utf-8')
    p.write_bytes(raw)
    if p.read_bytes()!=raw: raise ValueError('diagnostic write readback mismatch')


def load_runner(path):
    spec=importlib.util.spec_from_file_location('round71_owned_runner',path)
    r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
    return r


def require_exit(m):
    rows=m['processes'];labels=m['owned_labels']
    if not labels or [x.get('label') for x in rows]!=labels or len(set(labels))!=len(labels):
        raise ValueError('launch/exit ledger incomplete')
    for row in rows:
        if (row.get('exited') is not True or type(row.get('active_owned_processes')) is not int
            or row['active_owned_processes']!=0 or row.get('log_handles_released') is not True
            or type(row.get('pid')) is not int or row['pid']<=0 or type(row.get('exit_code')) is not int):
            raise ValueError('Job0/log-release not proven')


def event_projection(row):
    keys={'version','stage','native_stage','native_error','godot_error','pid'}
    if set(row)!=keys or row['version']!=1 or type(row['pid']) is not int or row['pid']<=0:
        raise ValueError('unsafe save diagnostic')
    for key in ('native_error','godot_error'):
        if row[key] is not None and type(row[key]) is not int: raise ValueError('noninteger native/Godot error')
    return row


def receipt_projection(row):
    # Never expose state_hash, journal or arbitrary result fields.
    keys={'ok','room','pid','instance','authority_host_mode','request_id'}
    if not keys.issubset(row) or type(row['ok']) is not bool or type(row['pid']) is not int:
        raise ValueError('missing receipt binding')
    result=row.get('result',{})
    if not isinstance(result,dict): raise ValueError('invalid receipt result')
    value={k:row[k] for k in keys}
    value['result']={k:result[k] for k in ('saved','room_state_saved','closing') if k in result}
    return value


def collect_files(r):
    files={Path('project.godot'),Path('icon.svg'),Path('assets/config/server.cfg'),Path(DLL),
           Path('addons/fate_server_signals/fate_server_signals.gdextension'),
           Path('assets/scenes/main_menu/room_data_validation_worker.tscn'),
           Path('tools/run_isolated_godot_test.py'),Path(__file__).relative_to(REPO)}
    files.update(p.relative_to(REPO) for p in (REPO/'scripts').rglob('*') if p.is_file() and p.suffix in {'.gd','.uid'})
    files.update(p.relative_to(REPO) for p in (REPO/'data').rglob('*') if p.is_file() and p.suffix.lower() in {'.json','.png','.jpg','.jpeg','.webp'})
    for suite,_,_ in SUITES:
        files.update(Path('tests/'+suite+x) for x in ('.gd','.tscn'))
    queue=list(files)
    while queue:
        rel=queue.pop()
        if rel.suffix not in {'.gd','.tscn','.tres','.godot'}: continue
        p=r.contained(REPO/rel,REPO)
        text=p.read_text(encoding='utf-8-sig')
        for ref in re.findall(r'res://([^\s\"\'<>\)]+)',text):
            dep=Path(ref)
            if '..' in dep.parts or dep.is_absolute() or any(x in r.EXCLUDED for x in dep.parts): continue
            if (REPO/dep).is_file() and dep not in files:
                r.contained(REPO/dep,REPO);files.add(dep);queue.append(dep)
    return sorted(files)


def self_test():
    good={'processes':[{'label':'a','pid':1,'exit_code':0,'exited':True,'active_owned_processes':0,'log_handles_released':True}], 'owned_labels':['a']}
    require_exit(good)
    rejected=0
    for key,value in [('active_owned_processes',1),('active_owned_processes',False),('exited',False),('log_handles_released',False),('pid',None),('exit_code',None)]:
        bad=json.loads(json.dumps(good));bad['processes'][0][key]=value
        try: require_exit(bad)
        except ValueError: rejected+=1
    for labels in ([],['a','unknown']):
        bad=dict(good,owned_labels=labels)
        try: require_exit(bad)
        except ValueError: rejected+=1
    row={'version':1,'stage':'write','native_stage':None,'native_error':None,'godot_error':12,'pid':1}
    assert event_projection(row)==row
    try: event_projection(dict(row,secret='must reject'))
    except ValueError: rejected+=1
    projected=receipt_projection({'ok':True,'room':'r','pid':1,'instance':'i','authority_host_mode':'dedicated','request_id':'q','result':{'saved':False,'room_state_saved':True,'closing':True,'state_hash':'not exported'}})
    assert 'state_hash' not in projected['result'] and rejected==9
    print(json.dumps({'self_test':'PASS','rejected_unsafe_cases':rejected}))


def run(continue_unrun=None):
    initial=None
    input_root=REPO
    selected=SUITES
    if continue_unrun:
        original=Path(continue_unrun).resolve(strict=True)
        initial=json.loads(original.read_text(encoding='utf-8'))
        require_exit(initial)
        if initial.get('runtime_consumed') is not True or initial.get('first_failure') is None:
            raise ValueError('continuation requires retained first RED and completed cleanup')
        input_root=original.parent/'evidence/frozen-source'
        r=load_runner(input_root/'tools/run_isolated_godot_test.py')
        r.physical_e(input_root)
        hashes=initial['source_hashes'];files=sorted(map(Path,hashes))
        attempted={x['suite'] for x in initial['suites']}
        selected=[x for x in SUITES if x[0] not in attempted]
        if not selected: raise ValueError('no unattempted original suites')
        # Exclusive claim prevents another invocation repeating the remaining suites.
        claim=original.parent/'remaining-claim.json'
        with claim.open('x',encoding='utf-8') as f:
            json.dump({'initial_manifest_sha256':digest(original),'selected':[x[0] for x in selected],'continuation_runner_sha256':digest(__file__)},f,indent=2)
    else:
        r=load_runner(REPO/'tools/run_isolated_godot_test.py')
        files=collect_files(r)
        hashes={p.as_posix():digest(r.contained(REPO/p,REPO)) for p in files}
    if digest(ENGINE)!=ENGINE_SHA or hashes[DLL]!=DLL_SHA: raise ValueError('original engine/DLL binding changed')
    cfg=(input_root/'project.godot').read_text(encoding='utf-8-sig')
    public=(input_root/'assets/config/server.cfg').read_text(encoding='utf-8-sig')
    if not re.search(r'max_threads\s*=\s*20',cfg) or not re.search(r'random_sim_budget_sec\s*=\s*15\.0',public) or not re.search(r'random_sim_enabled\s*=\s*true',public):
        raise ValueError('pool/default policy changed')
    token=uuid.uuid4().hex;owner=r.physical_e('E:/scratch')/('isolated-'+token);owner.mkdir()
    g=owner/'generated';ev=owner/'evidence';g.mkdir();ev.mkdir()
    m={'run_id':token,'generated':str(g),'source_hashes':hashes,'source_set_sha256':hashlib.sha256(json.dumps(hashes,sort_keys=True).encode()).hexdigest(),
       'engine_sha256':ENGINE_SHA,'dll_sha256':DLL_SHA,'processes':[],'owned_labels':[], 'suites':[], 'artifacts':[],
       'correctness_passed':False,'evidence_complete':False,'historical_root_cause':'UNKNOWN','runtime_consumed':False,
       'suite_attempt_limit':1,'runtime_budget_seconds':sum(x[1] for x in SUITES),
       'budgets':{'seconds':180,'bytes':8*1024**3,'min_free':1024**3},
       'evidence_gaps':['No approved failure-only native API observer for original validation_stage_timing paths; existing capture is gated to other fixture labels and pauses success paths. No authorization broadened.',
                        'Original shutdown fixtures have no safe per-attempt receipt/diagnostic handoff for every transient failure. FATE_R60_ARTIFACT_ROOT deliberately unset: that branch reads complete recovery payload.'],
       'observer_policy':'No background content reads. Exact safe log/report/control evidence after all owned Job0/log release only; no recovery/temp/key/ticket content reads, hashes or copies by this runner.'}
    if initial is not None:
        m['continuation_of']={'manifest':str(original),'sha256':digest(original),'already_attempted':sorted(attempted),'initial_first_failure':initial['first_failure']}
        m['continuation_runner_sha256']=digest(__file__)
    def checkpoint(): save(owner/'manifest.json',m)
    checkpoint();print('ROUND71_SCOPE '+str(owner),flush=True)
    def execute(label,cmd,env,seconds):
        m['owned_labels'].append(label);checkpoint()
        try:
            result=r.execute(cmd,env,g,ev,label,dict(m['budgets'],seconds=seconds),m['processes'])
        finally: checkpoint()
        require_exit(m)
        return result
    def environment(base):
        base.mkdir(parents=True,exist_ok=True)
        env=dict(os.environ)
        for key in list(env):
            if key.startswith(('HERMES_ASSEMBLY_','FATE_R60_','ROUND66_')) or key in {'HERMES_RECOVERY_VALIDATION_ROOT','HERMES_SHUTDOWN_TEST_ROOT','ROUND56_HANDOFF_ROOT','FATE_TEST_SCRATCH_ROOT'}: env.pop(key,None)
        for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR'):
            p=base/key.lower();p.mkdir(exist_ok=True);env[key]=p.as_posix()
        (base/'localappdata/hermes/cache/scratch').mkdir(parents=True,exist_ok=True)
        fixtures=base/'fixtures';fixtures.mkdir(exist_ok=True)
        env.update(ROUND56_HANDOFF_ROOT=fixtures.as_posix(),HERMES_SHUTDOWN_TEST_ROOT=fixtures.as_posix())
        return env
    def archive(path):
        require_exit(m)
        r.contained(path,g)
        dest=ev/'runtime'/path.relative_to(g);dest.parent.mkdir(parents=True,exist_ok=True)
        raw=path.read_bytes();dest.write_bytes(raw)
        if dest.read_bytes()!=raw: raise ValueError('archive readback changed')
        row={'path':dest.relative_to(ev).as_posix(),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
        m['artifacts'].append(row)
        return raw,row
    try:
        # Persist initial raw source bytes once, before starting ANY Godot process.
        source=ev/'frozen-source';project=g/'project';project.mkdir()
        for rel in files:
            raw=(input_root/rel).read_bytes()
            if hashlib.sha256(raw).hexdigest()!=hashes[rel.as_posix()]: raise ValueError('initial source drift: '+str(rel))
            for root in (source,project):
                dst=root/rel;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(raw)
                if digest(dst)!=hashes[rel.as_posix()]: raise ValueError('freeze mismatch')
        ex=g/'engine/Godot.exe';ex.parent.mkdir();shutil.copyfile(ENGINE,ex)
        if digest(ex)!=ENGINE_SHA: raise ValueError('engine copy mismatch')
        # Imported in isolated copy only. Original autoload/runtime/pool are restored.
        changed='\n'.join(x for x in cfg.splitlines() if not x.startswith(('run/main_scene=','run/main_scene.fate_server=','_mcp_game_helper=','_mcp_game_helper=','enabled=PackedStringArray(','version_control/')))
        changed=re.sub(r'^_mcp_game_helper=.*\n','',changed,flags=re.M)
        changed=changed.replace('renderer/rendering_method="mobile"','renderer/rendering_method="gl_compatibility"')
        app=re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)',changed,re.M|re.S)[1]
        threads=re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)',changed,re.M|re.S)[0]
        simple='config_version=5\n[application]\n'+app+'\n'+threads
        m['project_transform']='owned copy only: remove missing main scene, VCS and MCP plugin/helper; headless compatibility renderer. No runtime autoload/production/test changes.'
        setup=environment(g/'setup');probe=g/'probe';probe.mkdir()
        (probe/'project.godot').write_text(simple,encoding='utf-8');(probe/'probe.gd').write_text(r.PROBE_SCRIPT,encoding='utf-8')
        out,err,code=execute('probe',[str(ex),'--headless','--path',str(probe),'--script','res://probe.gd','--',token,'main',str(g)],setup,180)
        if code or ERROR.search(out+'\n'+err): raise ValueError('main/child E probe failed')
        m['user_probes']=r.verify_probe(out,g,token)
        if any(x['worker_pool_max_threads']!=20 for x in m['user_probes']): raise ValueError('pool probe differs')
        for label,config in [('resource-import',simple),('import',changed)]:
            (project/'project.godot').write_text(config,encoding='utf-8')
            out,err,code=execute(label,[str(ex),'--headless','--editor','--import','--path',str(project)],setup,180)
            if code or ERROR.search(out+'\n'+err): raise ValueError(label+' failed')
        m['frozen_hashes']={p.as_posix():digest(project/p) for p in files}
        m['frozen_set_sha256']=hashlib.sha256(json.dumps(m['frozen_hashes'],sort_keys=True).encode()).hexdigest()
        if initial is not None and m['frozen_hashes']!=initial['frozen_hashes']:
            raise ValueError('continuation is not the exact initial frozen runtime')
        for suite,seconds,checks in selected:
            env=environment(g/'runs'/suite)
            row={'suite':suite,'budget_seconds':seconds,'attempt':1,'evidence_gaps':[]};m['suites'].append(row)
            cmd=[str(ex),'--headless','--audio-driver','Dummy','--fixed-fps','60','--path',str(project),'--log-file',str(g/'runs'/suite/'parent.log'),'--scene','res://tests/'+suite+'.tscn']
            row['command']=cmd;checkpoint()
            try: out,err,code=execute(suite,cmd,env,seconds)
            except Exception as exc:
                row['executor_error']=str(exc);require_exit(m)
                out=(ev/(suite+'.stdout.log')).read_text(encoding='utf-8');err=(ev/(suite+'.stderr.log')).read_text(encoding='utf-8')
                code=m['processes'][-1]['exit_code']
            row['analysis']=r.analyze(out,err,code)
            if checks is not None and row['analysis'].get('result',{}).get('checks')!=checks:
                row['analysis']['passed']=False;row['analysis']['reasons'].append('original_check_count_changed')
            row['walltime']={'seconds':m['processes'][-1]['duration_seconds'],'watchdog_seconds':seconds,'budget_failure':m['processes'][-1].get('budget_failure')}
            row['original_rejections']=[x for x in (out+'\n'+err).splitlines() if x.startswith(('ROOM_DATA_ASSEMBLY_REJECT ','RECOVERY_SAVE_DIAGNOSTIC '))]
            row['save_diagnostics']=[];row['control_receipts']=[];row['errors']=[]
            # Nothing below runs until the exact suite returned its Job0/log receipt.
            require_exit(m)
            runroot=g/'runs'/suite
            logs=[]
            for directory,dirs,names in os.walk(runroot,followlinks=False):
                r.no_links(directory)
                for name in names:
                    p=Path(directory)/name;r.no_links(p)
                    # Only logs, approved control responses and fixture ready identities.
                    if p.suffix=='.log':
                        raw,_=archive(p);text=raw.decode('utf-8',errors='replace');logs.append((p,text))
            for p,text in [(ev/(suite+'.stdout.log'),out),(ev/(suite+'.stderr.log'),err),*logs]:
                row['errors'].extend({'log':str(p),'line':i,'text':x} for i,x in enumerate(text.splitlines(),1) if ERROR.search(x))
                for line in text.splitlines():
                    if line.startswith('RECOVERY_SAVE_DIAGNOSTIC '):
                        event=event_projection(json.loads(line.split(' ',1)[1]));row['save_diagnostics'].append({'log':str(p),'event':event})
                    if line.startswith('ROOM_DATA_ASSEMBLY_REJECT '): row['original_rejections'].append(line)
            if suite=='validation_stage_timing_test':
                timings=[json.loads(x.split(' ',1)[1]) for x in out.splitlines() if x.startswith('STAGE_TIMING ')]
                if len(timings)!=1: raise ValueError('missing original STAGE_TIMING')
                timing=timings[0];row['timings']=timing
                # Explicit original producer path, not recursive report discovery.
                reportdir=r.contained(Path(timing['real_task']['report_dir']),runroot)
                actual,artifact=archive(reportdir/'report.json');report=json.loads(actual)
                manifest,manifest_artifact=archive(reportdir/'manifest.json');approved=json.loads(manifest)
                simulation=report.get('random_simulation',{})
                row['real_report']={'artifact':artifact,'manifest_artifact':manifest_artifact,'files':len(approved),'same_as_parent_report':report==timing['real_task']['report'],
                    'enabled':simulation.get('enabled'),'budget_seconds':simulation.get('budget_seconds'),'elapsed_seconds':simulation.get('elapsed_seconds'),'status':simulation.get('status'),'ok':report.get('ok')}
                row['formal_15_verified']=(timing['inventory']['files']==204 and len(approved)==204 and report==timing['real_task']['report'] and report.get('ok') is True and report.get('errors')==[] and timing['options'].get('enabled') is True and timing['options'].get('seconds')==15.0 and simulation.get('budget_seconds')==15.0 and simulation.get('ok') is True)
                row['walltime']['original_task_deadline_seconds']=45.0
                row['walltime']['whole_preparation_seconds']=timing['real_task']['total_seconds']
                row['walltime']['worker_from_launch_seconds']=timing['real_task']['total_seconds']-timing['real_task']['task_launch_offset_seconds']
                row['walltime']['static_checkpoint_from_launch_seconds']=timing['real_task']['launch_to_checkpoint_seconds']
                row['walltime']['original_static_limit_seconds']=30.0
                if not row['formal_15_verified']: row['analysis']['passed']=False;row['analysis']['reasons'].append('formal15_report_mismatch')
            else:
                # Old diagnostics would read recovery payload; leave disabled. Original safe
                # ready files and close responses are schema-limited and owned by this fixture.
                for directory,dirs,names in os.walk(runroot/'fixtures',followlinks=False):
                    if Path(directory).name!='control': continue
                    control=Path(directory)
                    ready=control.parent/'ready.json'
                    binding=None
                    if ready.is_file():
                        raw,_=archive(ready);binding=json.loads(raw)
                    for name in names:
                        if not re.fullmatch(r'[0-9a-f]{32}\.response\.json',name): continue
                        raw,artifact=archive(control/name);value=receipt_projection(json.loads(raw))
                        value['artifact']=artifact
                        value['request_filename_matches']=value['request_id']==name.split('.')[0]
                        value['ready_binding_matches']=(binding is not None and value['room']==binding.get('id',binding.get('room_id')) and value['pid']==binding.get('pid') and value['instance']==binding.get('instance',binding.get('instance_id')) and value['authority_host_mode']==binding.get('authority_host_mode'))
                        row['control_receipts'].append(value)
                safe_evidence=runroot/'fixtures/evidence.json'
                if suite=='server_shutdown_close_handoff_test' and safe_evidence.is_file():
                    raw,artifact=archive(safe_evidence);doc=json.loads(raw)
                    row['fixture_safe_evidence']=artifact
                    for item in doc.get('evidence',[]):
                        if item.get('stage')!='console-close-stop': continue
                        value=receipt_projection(item['receipt']);binding=item['binding']
                        value['original_binding_matches']=all(value[k]==binding[b] for k,b in [('room','room'),('pid','pid'),('instance','instance_id'),('authority_host_mode','authority_host_mode')]) and value['request_id']==item['request_id']
                        value['closed_binding_matches']=item['closed']==dict(binding,request_id=item['request_id'])
                        row['control_receipts'].append(value)
                row['save_proof_layer']='original CHECK/RESULT plus archived same-instance close responses; exit and Job0 are separate'
                row['transient_diagnostic_gap']='No safe explicit handoff for each deleted/overwritten transient attempt; no recovery payload inspection enabled.'
            if row['control_receipts']:
                row['receipt_binding_validated']=all(x.get('request_filename_matches') is True and x.get('ready_binding_matches') is True or x.get('original_binding_matches') is True and x.get('closed_binding_matches') is True for x in row['control_receipts'])
                if not row['receipt_binding_validated']: row['evidence_gaps'].append('control receipt binding mismatch')
            if row['errors']:
                row['analysis']['passed']=False;row['analysis']['reasons'].append('all_log_error_scan')
            checkpoint();print(json.dumps({'suite':suite,'analysis':row['analysis'],'seconds':row['walltime']['seconds'],'errors':len(row['errors'])},ensure_ascii=False),flush=True)
            # First product failure is kept; never repeat it to obtain a green sample.
            if not row['analysis']['passed'] or row.get('executor_error'):
                m.setdefault('first_failure',suite)
        combined=(initial['suites'] if initial is not None else [])+m['suites']
        m['correctness_passed']=len(combined)==len(SUITES) and all(x['analysis']['passed'] for x in combined)
        m['selected_correctness_passed']=len(m['suites'])==len(selected) and all(x['analysis']['passed'] for x in m['suites'])
    except Exception as exc:
        m['error']=str(exc)
    finally:
        try:
            require_exit(m)
            # Archive setup/user logs only after all jobs have released every log handle.
            for directory,dirs,names in os.walk(g/'setup',followlinks=False):
                r.no_links(directory)
                for name in names:
                    if name.endswith('.log'): archive(Path(directory)/name)
            m['all_errors']=[]
            for p in ev.rglob('*.log'):
                text=p.read_text(encoding='utf-8',errors='replace')
                m['all_errors'].extend({'log':p.relative_to(ev).as_posix(),'line':i,'text':line} for i,line in enumerate(text.splitlines(),1) if ERROR.search(line))
            if m['all_errors']: m['correctness_passed']=False
            m['source_drift']=[name for name,h in hashes.items() if digest(REPO/name)!=h]
            m['frozen_drift']=[name for name,h in m.get('frozen_hashes',{}).items() if digest(g/'project'/name)!=h]
            if m['frozen_drift']: m['correctness_passed']=False
            m['artifact_readback_bad']=[x['path'] for x in m['artifacts'] if digest(ev/x['path'])!=x['sha256'] or (ev/x['path']).stat().st_size!=x['bytes']]
            m['log_hashes']={p.relative_to(ev).as_posix():digest(p) for p in ev.rglob('*.log')}
            m['total_checks']=sum(x.get('analysis',{}).get('result',{}).get('checks',0) for x in m['suites'] if x.get('analysis',{}).get('result'))
            m['job0_verified']=True;m['cleanup']='pending';checkpoint()
            if not m['artifact_readback_bad'] and not m['frozen_drift']:
                r.delete_owned(g,owner);m['runtime_consumed']=not g.exists();m['cleanup']='complete'
            else: m['cleanup']='retained_integrity_failure'
        except Exception as exc:
            m['cleanup']='retained_unproven_exit_or_evidence';m['finalization_error']=str(exc)
        checkpoint()
    print(json.dumps({'scope':str(owner),'correctness_passed':m['correctness_passed'],'checks':m.get('total_checks'),'evidence_complete':m['evidence_complete'],'runtime_consumed':m['runtime_consumed'],'error':m.get('error'),'finalization_error':m.get('finalization_error')},ensure_ascii=False),flush=True)
    return 0 if m['correctness_passed'] and m['runtime_consumed'] else 1


def verify_archives(paths):
    r=load_runner(REPO/'tools/run_isolated_godot_test.py')
    manifests=[];details=[];suites=[];bad=[];errors=[]
    for path in paths:
        path=r.physical_e(path)
        m=json.loads(path.read_text(encoding='utf-8'));require_exit(m)
        if path.name!='manifest.json' or path.parent.name!='isolated-'+m['run_id']:
            raise ValueError('not an exact owned round71 manifest')
        ev=path.parent/'evidence'
        if Path(m['generated']).exists() or m['runtime_consumed'] is not True:
            bad.append('runtime not consumed: '+str(path))
        for row in m['artifacts']:
            target=r.contained(ev/row['path'],ev)
            if digest(target)!=row['sha256'] or target.stat().st_size!=row['bytes']: bad.append(str(target))
        for name,h in m['log_hashes'].items():
            target=r.contained(ev/name,ev)
            if digest(target)!=h: bad.append(str(target))
            errors.extend({'manifest':str(path),'log':name,'line':i,'text':line} for i,line in enumerate(target.read_text(encoding='utf-8',errors='replace').splitlines(),1) if ERROR.search(line))
        source_bad=[name for name,h in m['source_hashes'].items() if digest(r.contained(ev/'frozen-source'/name,ev/'frozen-source'))!=h]
        bad.extend(source_bad)
        for s in m['suites']:
            out=(ev/(s['suite']+'.stdout.log')).read_text(encoding='utf-8')
            err=(ev/(s['suite']+'.stderr.log')).read_text(encoding='utf-8')
            proc=next(x for x in m['processes'] if x['label']==s['suite'])
            actual=r.analyze(out,err,proc['exit_code'])
            if actual['result']!=s['analysis']['result']: bad.append('original RESULT mismatch')
            for receipt in s['control_receipts']:
                if receipt.get('request_filename_matches') is not True or receipt.get('ready_binding_matches') is not True:
                    bad.append('same-instance control receipt mismatch')
            suites.append({'suite':s['suite'],'checks':actual['result']['checks'],'failures':actual['result']['failures'],'exit_code':proc['exit_code'],'seconds':proc['duration_seconds'],'budget_failure':proc.get('budget_failure')})
        manifests.append(m)
        details.append({'manifest':str(path),'manifest_sha256':digest(path),'artifacts':len(m['artifacts']),'logs':len(m['log_hashes']),'source_files':len(m['source_hashes']),'source_readback_bad':source_bad,'generated_absent':not Path(m['generated']).exists()})
    if len({x['suite'] for x in suites})!=len(suites): bad.append('duplicate suite attempt')
    same_source=all(x['source_hashes']==manifests[0]['source_hashes'] for x in manifests)
    same_frozen=all(x['frozen_hashes']==manifests[0]['frozen_hashes'] for x in manifests)
    timing=manifests[0]['suites'][0]['timings']['real_task']
    value={'archive_integrity_passed':not bad and not errors and same_source and same_frozen,
           'correctness_passed':len(suites)==4 and all(not x['failures'] and x['exit_code']==0 for x in suites),
           'evidence_complete':False,'same_source_hashes':same_source,'same_frozen_hashes':same_frozen,
           'manifests':details,'suites':suites,'total_checks':sum(x['checks'] for x in suites),'errors':errors,'bad':bad,
           'walltime_correction':{'whole_preparation_seconds':timing['total_seconds'],'worker_from_launch_seconds':timing['total_seconds']-timing['task_launch_offset_seconds'],'worker_deadline_seconds':45,'static_checkpoint_from_launch_seconds':timing['launch_to_checkpoint_seconds'],'static_limit_seconds':30},
           'verifier_sha256':digest(__file__),'historical_root_cause':'UNKNOWN'}
    save(paths[0].parent/'offline-verification.json',value)
    print(json.dumps(value,ensure_ascii=False,indent=2))
    return 0 if value['archive_integrity_passed'] else 1


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute',action='store_true')
    parser.add_argument('--self-test',action='store_true')
    parser.add_argument('--continue-unrun',type=Path,help='initial retained manifest; execute ONLY never-attempted suites from its exact source freeze')
    parser.add_argument('--verify',nargs='+',type=Path,help='offline exact archive readback; never starts Godot')
    args=parser.parse_args()
    if args.self_test: self_test()
    elif args.verify: raise SystemExit(verify_archives(args.verify))
    elif args.execute: raise SystemExit(run(args.continue_unrun))
    else: parser.print_help()
