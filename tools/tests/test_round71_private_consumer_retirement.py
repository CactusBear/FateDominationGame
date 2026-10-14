"""Owned Round71: prove three read-only public substitutions before source edits."""
import sys
sys.dont_write_bytecode = True
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import uuid
import difflib
from collections import Counter

PROJECT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('round71_helpers', PROJECT/'tools/tests/test_round64_private_fixture_retirement.py')
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
a, r = h.a, h.r
NAME = 'net_guard_rollback_test'
REL = 'tests/'+NAME+'.gd'
ROOT = Path('E:/scratch')
SITES = [
 ('var checkpoint = EffectManager._guard_transactions.get(effect)', 'var checkpoint = EffectManager.capture_transaction_state().transaction_bindings.get(effect)', 'EffectManager._guard_transactions'),
 ('EffectManager._paused_runs.is_empty()', 'EffectManager.paused_runs_snapshot().is_empty()', 'EffectManager._paused_runs'),
 ('EffectManager._guard_continuations.is_empty()', 'EffectManager.capture_transaction_state().continuation_queue.is_empty()', 'EffectManager._guard_continuations'),
]
OBSERVER = '''
func round71_observe(stage:String) -> void:
	var token:Dictionary = EffectManager.capture_transaction_state()
	var resources:Array = []
	var windows:Array = []
	for id in EffectManager.get_all_players_id():
		var d:Dictionary = GameData.player_data_library[id]
		resources.append([id, d.magic.number, d.score.number, d.deck.size(), d.hand_cards.size(), d.discard.size(), d.servant_skills.size()])
		windows.append([id, d.current_time_points.duplicate(), d.dynamic_time_points.duplicate()])
	var roots:Array = []
	for effect in token.transaction_bindings:
		var checkpoint = token.transaction_bindings[effect]
		roots.append([effect._name, checkpoint.root._name, checkpoint.ready, checkpoint.settled, checkpoint.error, checkpoint.random])
	var facts:Array = []
	for row in GameLog.query({}, null):
		facts.append([row.type, row.get("actor", -1)])
	var audit:Array = []
	for row in MatchJournal.audit_records: audit.append(row.event)
	var paused:Array = []
	for effect in EffectManager.paused_runs_snapshot(): paused.append(effect._name)
	print("ROUND71_OBSERVER ", JSON.stringify({"stage":stage, "resources":resources, "random":preload("res://scripts/match/rule_random.gd").snapshot(), "facts":facts, "transactions":roots, "audit":audit, "paused":paused, "batch_count":token.batch_transactions.size(), "tail_count":token.continuation_queue.size(), "tail_owners":token.continuation_transactions.size(), "guard":EffectManager.runtime_guard_status(), "windows":windows, "waiting":EffectManager.is_waiting_for_choice(), "time_point_id":EffectManager.time_point_id, "decision_count":EffectManager.decision_queue.size(), "activation_count":EffectManager.activation_pool.size()}))
'''

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def gate():
    spec = importlib.util.spec_from_file_location('round71_gate', PROJECT/'tools/check_layer_deps.py')
    g = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = g
    spec.loader.exec_module(g)
    findings = g.scan(PROJECT)
    new, stale = g.evaluate(findings)
    return {'findings':len(findings), 'allowlist':len(g.ALLOWLIST), 'private':sum(x.rule=='private' for x in findings), 'layer':sum(x.rule=='layer' for x in findings), 'new':[vars(x) for x in new], 'stale':[vars(x) for x in stale], 'selected':[vars(x) for x in findings if x.path==REL], 'sha256':a.digest(PROJECT/'tools/check_layer_deps.py')}

def candidate(text):
    for old, new, target in SITES:
        if text.count(old)!=1: raise r.SafetyError('not unique: '+old)
        text = text.replace(old,new)
    return text

def instrument(text):
    # Identical real public seeded fixture for original/candidate only, not final GD.
    anchor='\tvar selection_ready:bool = host.selection.setup('
    if text.count(anchor)!=1: raise r.SafetyError('start seed anchor absent')
    text=text.replace(anchor,'\tpreload("res://scripts/match/rule_random.gd").start_seed(7105)\n'+anchor)
    anchors=[('\tvar checkpoint = ', '\tround71_observe(stage)'),
             ('\tcheck(not EffectManager.effect_pool.has(chain_effect)', '\tround71_observe("chain_rollback")'),
             ('\tcheck(host.match_authority._restart_seed == seed_before and not old_tail', '\tround71_observe("restart_complete")')]
    lines=text.splitlines()
    for anchor, call in anchors:
        matches=[i for i,line in enumerate(lines) if line.startswith(anchor)]
        if len(matches)!=1: raise r.SafetyError('observer anchor not unique: '+anchor)
        lines.insert(matches[0]+1,call)
    return '\n'.join(lines)+'\n'+OBSERVER

def paths():
    old=a.load(h.OLD)
    selected={p for p in old['freeze_before'] if not p.startswith('tests/')}
    selected.update(p.relative_to(PROJECT).as_posix() for p in (PROJECT/'scripts').rglob('*') if p.is_file() and p.suffix in {'.gd','.uid'})
    pending=['tests/'+NAME+'.gd','tests/'+NAME+'.tscn']
    seen=set()
    while pending:
        name=pending.pop()
        if name in seen: continue
        seen.add(name)
        src=r.contained(PROJECT/name,PROJECT)
        selected.add(name)
        if src.suffix in {'.gd','.tscn'}:
            pending.extend(x[6:] for x in re.findall(r'res://tests/[^"\s)]+\.(?:gd|tscn)',src.read_text(encoding='utf-8-sig')))
    return sorted(selected)

def execute(m, command, label):
    return h.execute(m,command,label)

def scene(m,label):
    gen=Path(m['owner'])/'generated'
    command=[str(gen/'Godot.exe'),'--headless','--fixed-fps','60','--path',str(gen/'project'),'--scene','res://tests/'+NAME+'.tscn']
    out,err,code=execute(m,command,label)
    row=dict(a.analyze(out,err,code),label=label,exit_code=code,command=command)
    row['observers']=[json.loads(x[len('ROUND71_OBSERVER '):]) for x in out.splitlines() if x.startswith('ROUND71_OBSERVER ')]
    m['suites'].append(row)
    save(Path(m['owner'])/'manifest.json',m)
    print(json.dumps({'label':label,'exit':code,'checks':row['observed_checks'],'passed':row['passed'],'errors':row['errors']},ensure_ascii=False),flush=True)
    return row

def prepare(original_manifest=None):
    r.physical_e(ROOT); r.physical_e(h.ENGINE)
    owner=ROOT/('round71-private-'+uuid.uuid4().hex); owner.mkdir()
    gen=owner/'generated'; gen.mkdir(); evidence=owner/'evidence'; evidence.mkdir()
    m={'owner':str(owner),'firstroot':str(owner),'phase':'prepare','passed':False,'processes':[],'suites':[],'timeout':180,'selected':[REL],'gate_before':gate()}
    save(owner/'owner.json',{'token':owner.name,'generated':str(gen)})
    try:
        deps=paths()
        m['source_hashes']={p:a.digest(PROJECT/p) for p in deps}
        m['source_fingerprint']=a.round50_source_fingerprint(m['source_hashes'])
        m['engine_sha256']=a.digest(h.ENGINE)
        if m['engine_sha256']!=a.load(h.OLD)['engine_sha256']: raise r.SafetyError('engine drift')
        target=gen/'project'
        for name in deps:
            src=r.contained(PROJECT/name,PROJECT); dst=target/name
            before_hash=a.digest(src)
            dst.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(src,dst)
            if a.digest(dst)!=before_hash or a.digest(src)!=before_hash: raise r.SafetyError('freeze drift: '+name)
            m['source_hashes'][name]=before_hash
        m['source_fingerprint']=a.round50_source_fingerprint(m['source_hashes'])
        shutil.copyfile(h.ENGINE,gen/'Godot.exe')
        if original_manifest:
            prior_path=r.contained(Path(original_manifest),r.physical_e(ROOT))
            prior=a.load(prior_path)
            if not re.fullmatch(r'round71-private-[a-f0-9]{32}',prior_path.parent.name): raise r.SafetyError('prior ownership')
            m['prior_unowned_source_drift']=[p for p,hsh in prior['source_hashes'].items() if p!=REL and a.digest(PROJECT/p)!=hsh]
            original=(prior_path.parent/'evidence'/'original.gd').read_bytes()
            if a.digest(prior_path.parent/'evidence'/'original.gd')!=prior['source_hashes'][REL]: raise r.SafetyError('original archive drift')
            m['prior_manifest']=str(prior_path)
            m['prior_manifest_sha256']=a.digest(prior_path)
        else:
            original=(PROJECT/REL).read_bytes()
        (evidence/'original.gd').write_bytes(original)
        m['original_sha256']=a.digest(evidence/'original.gd')
        changed=candidate(original.decode('utf-8-sig'))
        (evidence/'candidate.gd').write_text(changed,encoding='utf-8',newline='')
        config=(target/'project.godot').read_text(encoding='utf-8-sig')
        if (PROJECT/'override.cfg').exists() or 'config/project_settings_override=' in config: raise r.SafetyError('override')
        transformed,m['editor_transform']=a.transform_isolated_editor_vcs(config)
        (target/'project.godot').write_text(transformed,encoding='utf-8')
        probe=gen/'probe'; probe.mkdir()
        app=re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)
        thread=re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)
        pconfig='config_version=5\n[application]\n'+re.sub(r'^run/main_scene=.*\n','',app[1],flags=re.M)
        if thread: pconfig+='\n[threading]\n'+thread[1]
        (probe/'project.godot').write_text(pconfig,encoding='utf-8'); (probe/'probe.gd').write_text(r.PROBE_SCRIPT,encoding='utf-8')
        out,err,code=execute(m,[str(gen/'Godot.exe'),'--headless','--path',str(probe),'--script','res://probe.gd','--',owner.name,'main',str(gen)],'probe')
        if code or re.search(r'SCRIPT ERROR|ERROR:',out+err): raise r.SafetyError('probe failed')
        m['user_probes']=r.verify_probe(out,gen,owner.name)
        out,err,code=execute(m,[str(gen/'Godot.exe'),'--headless','--editor','--import','--path',str(target)],'import')
        m['import']={'exit':code,'errors':[x for x in (out+err).splitlines() if re.search(r'SCRIPT ERROR|ERROR:',x)]}
        if code or m['import']['errors']: raise r.SafetyError('import failed')
        for label,text in [('original-observer',original.decode('utf-8-sig')),('candidate-observer',changed)]:
            (target/REL).write_text(instrument(text),encoding='utf-8')
            if not scene(m,label)['passed']: raise r.SafetyError('scene not green: '+label)
        before,after=m['suites'][-2:]
        m['equivalence']={'equal':before['observers']==after['observers'],'before':before['observers'],'after':after['observers']}
        if not m['equivalence']['equal'] or len(before['observers'])!=4: raise r.SafetyError('four-stop equivalence failed')
        m['phase']='candidate_proven_before_source_write'
    except Exception as exc:
        m['error']=type(exc).__name__+': '+str(exc)
    save(owner/'manifest.json',m)
    print(json.dumps({'manifest':str(owner/'manifest.json'),'phase':m['phase'],'error':m.get('error')},ensure_ascii=False))
    return 0 if m['phase']=='candidate_proven_before_source_write' else 1

def reprove(path):
    path=r.contained(Path(path),r.physical_e(ROOT)); owner=path.parent
    if not re.fullmatch(r'round71-private-[a-f0-9]{32}',owner.name): raise r.SafetyError('ownership')
    m=a.load(path); gen=owner/'generated'; target=gen/'project'; evidence=owner/'evidence'
    if m['phase']!='prepare' or m.get('error')!='SafetyError: four-stop equivalence failed': raise r.SafetyError('reprove phase')
    m['historical_error']=m.pop('error'); m['historical_equivalence']=m.pop('equivalence')
    for label,name in [('original-observer-seeded','original.gd'),('candidate-observer-seeded','candidate.gd')]:
        (target/REL).write_text(instrument((evidence/name).read_text(encoding='utf-8-sig')),encoding='utf-8')
        if not scene(m,label)['passed']: raise r.SafetyError('reprove scene failed')
    before,after=m['suites'][-2:]
    m['equivalence']={'equal':before['observers']==after['observers'],'before':before['observers'],'after':after['observers']}
    if not m['equivalence']['equal'] or len(before['observers'])!=4:
        m['error']='SafetyError: reseeded equivalence failed'
    else: m['phase']='candidate_proven_before_source_write'
    save(path,m)
    print(json.dumps({'manifest':str(path),'phase':m['phase'],'error':m.get('error')},ensure_ascii=False))
    return 0 if m['phase']=='candidate_proven_before_source_write' else 1

def diagnose(path):
    path=r.contained(Path(path),r.physical_e(ROOT)); owner=path.parent
    if not re.fullmatch(r'round71-private-[a-f0-9]{32}',owner.name): raise r.SafetyError('ownership')
    m=a.load(path); target=owner/'generated'/'project'
    text=(owner/'evidence'/'original.gd').read_text(encoding='utf-8-sig')
    anchor='\treport_checkpoint("initial_mutation_pause")'
    diagnostic='\tprint("ROUND71_DIAG host_error=",host.error," guest_error=",guest.error," host_actions=",host.read_actions()," guest_actions=",guest.read_actions()," guest_match_keys=",guest.read_match().keys()," host_match_keys=",host.read_match().keys())\n\tvar round71_mirror := MatchViewMirror.new()\n\tround71_mirror.reset(host.match_authority.observer_for(1))\n\tvar round71_accepted:bool = round71_mirror.accept(host.match_authority.view_for(1))\n\tprint("ROUND71_MIRROR accepted=",round71_accepted," error=",round71_mirror.error)'
    if text.count(anchor)!=1: raise r.SafetyError('diagnostic anchor')
    (target/REL).write_text(instrument(text.replace(anchor,anchor+'\n'+diagnostic)),encoding='utf-8')
    row=scene(m,'first-root-diagnostic-mirror')
    return 0 if row['passed'] else 1

def blocked(path):
    path=r.contained(Path(path),r.physical_e(ROOT)); owner=path.parent
    if not re.fullmatch(r'round71-private-[a-f0-9]{32}',owner.name): raise r.SafetyError('ownership')
    m=a.load(path); gen=owner/'generated'; evidence=owner/'evidence'
    current=(PROJECT/REL).read_bytes()
    (evidence/'current.gd').write_bytes(current)
    (gen/'project'/REL).write_bytes(current)
    row=scene(m,'final-source-uninstrumented')
    m['final_source_result']=row
    m['final_gate']=gate()
    old=(evidence/'original.gd').read_text(encoding='utf-8-sig'); new=current.decode('utf-8-sig')
    normalized=candidate(old)
    checks=lambda s:Counter(x.strip() for x in s.splitlines() if x.strip().startswith('check('))
    m['assertion_difference']={'missing':list((checks(normalized)-checks(new)).elements()),'added':list((checks(new)-checks(normalized)).elements())}
    (evidence/'migration.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='original/'+REL,tofile='current/'+REL)),encoding='utf-8',newline='')
    m['patch_sha256']=a.digest(evidence/'migration.patch')
    m['final_source_sha256']=a.digest(PROJECT/REL)
    m['final_runner_sha256']=a.digest(Path(__file__))
    m['current_source_drift']=[p for p,hsh in m['source_hashes'].items() if p!=REL and a.digest(PROJECT/p)!=hsh]
    m['logs']=[{'path':str(x.relative_to(evidence)),'sha256':a.digest(x)} for x in evidence.rglob('*.log')]
    m['all_owned_job0']=bool(m['processes']) and all(x.get('exited') and x.get('active_owned_processes')==0 and x.get('log_handles_released') for x in m['processes'])
    m['negative_status']='not_run_current_original_blocked_before_skip'
    save(path,m)
    if m['all_owned_job0']:
        r.tree_bytes(gen); shutil.rmtree(gen); m['cleanup']='generated_removed'
    else: m['cleanup']='retained'
    save(path,m)
    print(json.dumps({'manifest':str(path),'passed':False,'final_exit':row['exit_code'],'checks':row['observed_checks'],'job0':m['all_owned_job0'],'cleanup':m['cleanup'],'stale':m['final_gate']['stale']},ensure_ascii=False))
    return 1

def verify(path):
    path=r.contained(Path(path),r.physical_e(ROOT)); owner=path.parent
    if not re.fullmatch(r'round71-private-[a-f0-9]{32}',owner.name): raise r.SafetyError('ownership')
    m=a.load(path); gen=owner/'generated'; target=gen/'project'; evidence=owner/'evidence'
    if a.load(owner/'owner.json')!={'token':owner.name,'generated':str(gen)} or m['phase']!='candidate_proven_before_source_write': raise r.SafetyError('unproven candidate')
    try:
        current=(PROJECT/REL).read_bytes()
        if current!=(evidence/'candidate.gd').read_bytes(): raise r.SafetyError('source differs from proven candidate')
        m['new_sha256']=a.digest(PROJECT/REL)
        m['unowned_source_drift']=[p for p,hsh in m['source_hashes'].items() if p!=REL and a.digest(PROJECT/p)!=hsh]
        if m['unowned_source_drift']: raise r.SafetyError('unowned source drift')
        text=current.decode('utf-8-sig')
        # Inject only after a real pause, then bypass the test's early-failure stop at this
        # one prereq. Preserve production host_skip and prove failure survives rollback.
        anchor='\tif not await act(host, "guard_skip"):'
        if text.count(anchor)!=2: raise r.SafetyError('skip count')
        negative=text.replace(anchor,'\tcheck(false, "round71 negative before actual host rollback")\n'+anchor,1)
        # Negative-only harness disables failure-driven early-stop, not readiness,
        # assertions, or production behavior: execute all 39 original business checks.
        negative=negative.replace('ready = ready and failures.is_empty()', 'ready = ready')
        (target/REL).write_text(negative,encoding='utf-8')
        row=scene(m,'negative-before-rollback')
        m['negative_valid']=bool(row['exit_code']==1 and not row['errors'] and row['result'] and row['observed_checks']==row['result']['checks']==m['suites'][0]['observed_checks']+1 and row['result']['failures']==['round71 negative before actual host rollback'])
        if not m['negative_valid']: raise r.SafetyError('negative swallowed/error')
        (target/REL).write_bytes(current)
        if a.digest(target/REL)!=m['new_sha256']: raise r.SafetyError('restore mismatch')
        if not scene(m,'green-uninstrumented')['passed']: raise r.SafetyError('green failed')
        m['gate_after']=gate()
        normalized=candidate((evidence/'original.gd').read_text(encoding='utf-8-sig'))
        checks=lambda s:Counter(x.strip() for x in s.splitlines() if x.strip().startswith('check('))
        m['missing_assertions']=list((checks(normalized)-checks(text)).elements())
        m['added_assertions']=list((checks(text)-checks(normalized)).elements())
        (evidence/'migration.patch').write_text(''.join(difflib.unified_diff((evidence/'original.gd').read_text(encoding='utf-8-sig').splitlines(True),text.splitlines(True),fromfile='original/'+REL,tofile='current/'+REL)),encoding='utf-8')
        m['patch_sha256']=a.digest(evidence/'migration.patch')
        if m['missing_assertions'] or m['added_assertions'] or m['gate_after']['new'] or m['gate_after']['sha256']!=m['gate_before']['sha256']: raise r.SafetyError('scope/gate drift')
        expected=[x for x in m['gate_after']['stale'] if x['path']==REL]
        if len(expected)!=3: raise r.SafetyError('expected exactly three owned stale')
        m['expected_stale']=expected
        m['passed']=True; m['phase']='verified'
    except Exception as exc:
        m['error']=type(exc).__name__+': '+str(exc)
    finally:
        m['logs']=[{'path':str(x.relative_to(evidence)),'sha256':a.digest(x)} for x in evidence.rglob('*.log')]
        m['all_owned_job0']=bool(m['processes']) and all(x.get('exited') and x.get('active_owned_processes')==0 and x.get('log_handles_released') for x in m['processes'])
        save(path,m)
        if m['all_owned_job0']:
            r.tree_bytes(gen); shutil.rmtree(gen); m['cleanup']='generated_removed'
        else: m['cleanup']='retained'; m['passed']=False
        save(path,m)
    print(json.dumps({'passed':m['passed'],'manifest':str(path),'error':m.get('error'),'job0':m['all_owned_job0'],'cleanup':m['cleanup']},ensure_ascii=False))
    return 0 if m['passed'] else 1

def cleanup(path):
    path=r.contained(Path(path),r.physical_e(ROOT)); owner=path.parent
    if not re.fullmatch(r'round71-private-[a-f0-9]{32}',owner.name): raise r.SafetyError('ownership')
    m=a.load(path); gen=owner/'generated'
    if a.load(owner/'owner.json')!={'token':owner.name,'generated':str(gen)}: raise r.SafetyError('receipt')
    if not all(x.get('exited') and x.get('active_owned_processes')==0 for x in m['processes']): raise r.SafetyError('job not zero')
    if gen.exists():
        r.tree_bytes(gen); shutil.rmtree(gen)
    m['cleanup']='generated_removed'; m['generated_exists_after_cleanup']=gen.exists()
    save(path,m)
    print(json.dumps({'manifest':str(path),'cleanup':m['cleanup'],'process_count':len(m['processes'])},ensure_ascii=False))
    return 0

def readback(path):
    path=r.contained(Path(path),r.physical_e(ROOT)); owner=path.parent; m=a.load(path)
    proof=path if m.get('passed') else Path(m['prior_manifest'])
    p=a.load(proof); evidence=owner/'evidence'
    current_gate=gate()
    scope={REL:a.digest(PROJECT/REL),'tools/tests/test_round71_private_consumer_retirement.py':a.digest(Path(__file__))}
    report=PROJECT/'docs/round71-private-consumer-retirement.md'
    if report.exists(): scope['docs/round71-private-consumer-retirement.md']=a.digest(report)
    negative=next((x for x in m['suites'] if x['label']=='negative-before-rollback'),None)
    strict_negative=bool(negative and negative['exit_code']==1 and negative['observed_checks']==negative['result']['checks']==m['suites'][0]['observed_checks']+1 and negative['result']['failures']==['round71 negative before actual host rollback'] and not negative['errors'])
    drift=[name for name,hsh in m['source_hashes'].items() if name!=REL and a.digest(PROJECT/name)!=hsh]
    record={'status':'PASS' if m.get('passed') else 'BLOCKED','manifest':str(path),'manifest_sha256':a.digest(path),'proof_manifest':str(proof),'proof_manifest_sha256':a.digest(proof),'scope_sha256':scope,'original_sha256':a.digest(evidence/'original.gd'),'patch_sha256':a.digest(evidence/'migration.patch'),'source_fingerprint':m['source_fingerprint'],'gate':current_gate,'equivalence':p['equivalence'],'negative_valid':strict_negative,'assertion_difference':m.get('assertion_difference',{'missing':m.get('missing_assertions',[]),'added':m.get('added_assertions',[])}),'job0':m['all_owned_job0'],'cleanup':m['cleanup'],'source_drift':drift,'processes':m['processes'],'proof_scenes':p['suites'],'current_scenes':m['suites'],'expected_stale':[dict(x,count=1) for x in current_gate['stale'] if x['path']==REL],'current_matches_verified':a.digest(PROJECT/REL)==m.get('new_sha256',m.get('final_source_sha256')),'log_drift':[x['path'] for x in m['logs'] if a.digest(evidence/x['path'])!=x['sha256']]}
    record['generated_exists']=(owner/'generated').exists()
    record['passed']=bool(m.get('passed') and strict_negative and not drift and not record['log_drift'] and record['current_matches_verified'] and record['job0'] and not record['generated_exists'] and len(record['expected_stale'])==3 and not current_gate['new'] and current_gate['sha256']==m['gate_before']['sha256'])
    record['status']='PASS' if record['passed'] else 'BLOCKED'
    save(evidence/'readback.json',record)
    print(json.dumps({k:record[k] for k in ['status','passed','manifest','manifest_sha256','original_sha256','patch_sha256','scope_sha256','job0','cleanup','log_drift','source_drift','negative_valid']},ensure_ascii=False))
    return 0 if record['passed'] else 1

if __name__=='__main__':
    if len(sys.argv)==1: raise SystemExit(prepare())
    if len(sys.argv)==3 and sys.argv[1]=='--restart': raise SystemExit(prepare(sys.argv[2]))
    if len(sys.argv)==3 and sys.argv[1]=='--reprove': raise SystemExit(reprove(sys.argv[2]))
    if len(sys.argv)==3 and sys.argv[1]=='--cleanup': raise SystemExit(cleanup(sys.argv[2]))
    if len(sys.argv)==3 and sys.argv[1]=='--readback': raise SystemExit(readback(sys.argv[2]))
    if len(sys.argv)==3 and sys.argv[1]=='--blocked': raise SystemExit(blocked(sys.argv[2]))
    if len(sys.argv)==3 and sys.argv[1]=='--diagnose': raise SystemExit(diagnose(sys.argv[2]))
    if len(sys.argv)==3 and sys.argv[1]=='--verify': raise SystemExit(verify(sys.argv[2]))
    raise SystemExit('prepare: no args; verify: --verify <owned manifest>')
