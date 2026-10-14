"""Round64 owned four-site migration: original/public observers, RED, small GREEN."""
import sys
sys.dont_write_bytecode = True
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import uuid

PROJECT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('round64_evidence', PROJECT / 'tools/tests/test_round29_integrated_evidence.py')
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)
r = a.runner
NAMES = ['audit_commit_test', 'deferred_transaction_facts_test']
OLD = Path('E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50/manifest.json')
ENGINE = Path('E:/scratch/round51-engine/Godot_v4.7.2-stable_win64.exe')
ROOT = Path('E:/scratch')
SITES = {
    NAMES[0]: [('check(EffectManager._begin_guard_transaction(root), "真实根事务 start")', 'check(EffectManager.pay_effect_cost(root), "真实根事务 start")', 'root-start'),
               ('EffectManager._release_guard_transactions()', 'EffectManager.run_pipeline(true)', 'root-release')],
    NAMES[1]: [('EffectManager._queue_time_point_batch(effect, 0)', 'EffectManager.run_time_point(effect, 0)', 'pending-batch'),
               ('EffectManager._release_guard_transactions()', 'EffectManager.run_pipeline(true)', 'repeat-release')],
}
OBSERVER = '''
func round64_observe(stage:String) -> void:
	var token:Dictionary = EffectManager.capture_transaction_state()
	var resources:Array = []
	var windows:Array = []
	for id in EffectManager.get_all_players_id():
		var d:Dictionary = GameData.player_data_library[id]
		resources.append([id, d.magic.number, d.score.number, d.deck.size(), d.discard.size()])
		windows.append([id, d.current_time_points.duplicate(), d.dynamic_time_points.duplicate()])
	var roots:Array = []
	for root in token.transaction_bindings:
		var checkpoint = token.transaction_bindings[root]
		roots.append([root._name, checkpoint.root._name, checkpoint.ready, checkpoint.settled])
	var audit:Array = []
	for row in MatchJournal.audit_records: audit.append(row.event)
	var fact_types:Array = []
	for fact in GameLog.query({}, null): fact_types.append(fact.type)
	print("ROUND64_OBSERVER ", JSON.stringify({"stage":stage, "resources":resources, "windows":windows, "roots":roots, "audit":audit, "facts":fact_types, "random":preload("res://scripts/match/rule_random.gd").snapshot(), "batch_count":token.batch_transactions.size(), "continuation_count":token.continuation_queue.size(), "guard":EffectManager.runtime_guard_status(), "waiting":EffectManager.is_waiting_for_choice(), "time_point_id":EffectManager.time_point_id, "decision_count":EffectManager.decision_queue.size(), "activation_count":EffectManager.activation_pool.size(), "paused_count":EffectManager.paused_runs_snapshot().size()}))
'''

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def dependencies(old):
    paths = {x for x in old['freeze_before'] if not x.startswith('tests/')}
    paths.update(x.relative_to(PROJECT).as_posix() for x in (PROJECT / 'scripts').rglob('*') if x.is_file() and x.suffix in {'.gd', '.uid'})
    pending = ['tests/' + n + e for n in NAMES for e in ('.gd', '.tscn')]
    seen = set()
    while pending:
        name = pending.pop()
        if name in seen: continue
        seen.add(name)
        r.contained(PROJECT / name, PROJECT)
        paths.add(name)
        if Path(name).suffix in {'.gd', '.tscn'}:
            text = (PROJECT / name).read_text(encoding='utf-8-sig')
            pending.extend(x[6:] for x in re.findall(r'res://tests/[^"\s)]+', text))
    return sorted(paths)

def gate_scan():
    s = importlib.util.spec_from_file_location('round64_gate', PROJECT / 'tools/check_layer_deps.py')
    g = importlib.util.module_from_spec(s)
    sys.modules[s.name] = g
    s.loader.exec_module(g)
    findings = g.scan(PROJECT)
    new, stale = g.evaluate(findings)
    def site(x):
        d = dict(vars(x))
        if hasattr(x, 'code'): d['occurrences'] = 1
        return d
    return {'findings':len(findings), 'allowlist':len(g.ALLOWLIST), 'private':sum(x.rule == 'private' for x in findings),
            'selected_findings':[site(x) for x in findings if x.path in ['tests/'+n+'.gd' for n in NAMES]],
            'new':[site(x) for x in new], 'stale':[site(x) for x in stale], 'gate_sha256':a.digest(PROJECT/'tools/check_layer_deps.py')}

def instrument(name, text, migrated):
    for old, new, stage in SITES[name]:
        line = new if migrated else old
        if text.count(line) != 1: raise r.SafetyError('nonunique observer anchor: ' + line)
        text = text.replace(line, line + '\n\tround64_observe("' + stage + '")')
    return text + OBSERVER

def execute(m, command, label):
    owner = Path(m['owner']); generated = owner/'generated'; evidence = owner/'evidence'
    env = os.environ.copy()
    for key, child in [('APPDATA','appdata'), ('LOCALAPPDATA','localappdata'), ('TEMP','temp'), ('TMP','temp'), ('TMPDIR','temp')]:
        folder = generated/child; folder.mkdir(exist_ok=True); env[key] = str(folder)
    env['FATE_TEST_SCRATCH_ROOT'] = str(generated/'fixture')
    (generated/'fixture').mkdir(exist_ok=True)
    return r.execute(command, env, generated, evidence, label, {'seconds':180,'bytes':8589934592,'min_free':1073741824}, m['processes'])

def scene(m, name, label):
    gen = Path(m['owner'])/'generated'
    command = [str(gen/'Godot.exe'),'--headless','--fixed-fps','60','--path',str(gen/'project'),'--scene','res://tests/'+name+'.tscn']
    if name == NAMES[0]: command += ['--', str(gen/'fixture')]
    out, err, code = execute(m, command, label)
    row = dict(a.analyze(out,err,code), suite=name, label=label, command=command, exit_code=code)
    row['observers'] = [json.loads(x[len('ROUND64_OBSERVER '):]) for x in out.splitlines() if x.startswith('ROUND64_OBSERVER ')]
    m['suites'].append(row)
    save(Path(m['owner'])/'manifest.json',m)
    print(json.dumps({'label':label,'exit':code,'passed':row['passed'],'checks':row['observed_checks'],'errors':row['errors']},ensure_ascii=False),flush=True)
    return row

def prepare():
    old = a.load(OLD)
    r.physical_e(ROOT); r.physical_e(ENGINE)
    if a.digest(ENGINE) != old['engine_sha256']: raise r.SafetyError('original engine drift')
    owner = ROOT/('round64-private-'+uuid.uuid4().hex); owner.mkdir()
    gen = owner/'generated'; gen.mkdir(); (owner/'evidence').mkdir()
    m = {'owner':str(owner),'processes':[],'suites':[],'phase':'prepare','passed':False,'gate_before':gate_scan(),
         'engine_sha256':a.digest(ENGINE),'timeout':180,'selected':NAMES}
    save(owner/'owner.json',{'token':owner.name,'generated':str(gen)})
    try:
        paths = dependencies(old)
        m['source_hashes'] = {p:a.digest(PROJECT/p) for p in paths}
        m['source_fingerprint'] = a.round50_source_fingerprint(m['source_hashes'])
        m['native_old_hashes'] = {}
        for name in paths:
            src = r.contained(PROJECT/name,PROJECT); dst=gen/'project'/name
            if src.suffix == '.dll':
                expected = old['freeze_before'][name]
                if m['source_hashes'][name] != expected: raise r.SafetyError('old DLL drift: '+name)
                m['native_old_hashes'][name] = expected
            dst.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(src,dst)
            if a.digest(dst) != m['source_hashes'][name]: raise r.SafetyError('freeze drift: '+name)
        for n in NAMES:
            src=PROJECT/'tests'/(n+'.gd'); dst=owner/'evidence'/'original'/(n+'.gd')
            dst.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(src,dst)
        target = gen/'project'
        config=(target/'project.godot').read_text(encoding='utf-8-sig')
        if (PROJECT/'override.cfg').exists() or 'config/project_settings_override=' in config: raise r.SafetyError('unprobed override')
        transformed,m['editor_transform']=a.transform_isolated_editor_vcs(config)
        (target/'project.godot').write_text(transformed,encoding='utf-8')
        shutil.copyfile(ENGINE,gen/'Godot.exe')
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
        for n in NAMES:
            path=target/'tests'/(n+'.gd')
            path.write_text(instrument(n,(owner/'evidence'/'original'/(n+'.gd')).read_text(encoding='utf-8-sig'),False),encoding='utf-8')
            if not scene(m,n,'original-'+n)['passed']: raise r.SafetyError('original not green: '+n)
        m['phase']='original_complete_job0'
    except Exception as exc:
        m['error']=type(exc).__name__+': '+str(exc)
    save(owner/'manifest.json',m)
    print(json.dumps({'manifest':str(owner/'manifest.json'),'phase':m['phase'],'error':m.get('error')},ensure_ascii=False))
    return 0 if m['phase']=='original_complete_job0' else 1

def verify(path):
    path=r.contained(Path(path),r.physical_e(ROOT)); owner=path.parent
    if path.name!='manifest.json' or not re.fullmatch(r'round64-private-[a-f0-9]{32}',owner.name): raise r.SafetyError('ownership mismatch')
    m=a.load(path); gen=owner/'generated'; target=gen/'project'
    if a.load(owner/'owner.json')!={'token':owner.name,'generated':str(gen)} or m['phase']!='original_complete_job0': raise r.SafetyError('invalid receipt/phase')
    try:
        m['gate_after']=gate_scan()
        m['new_hashes']={n:a.digest(PROJECT/'tests'/(n+'.gd')) for n in NAMES}
        m['unowned_source_drift']=[p for p,h in m['source_hashes'].items() if p not in ['tests/'+n+'.gd' for n in NAMES] and a.digest(PROJECT/p)!=h]
        m['equivalence']=[]; m['negatives']=[]
        for n in NAMES:
            text=(PROJECT/'tests'/(n+'.gd')).read_text(encoding='utf-8-sig')
            archive=owner/'evidence'/'migrated'/(n+'.gd'); archive.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(PROJECT/'tests'/(n+'.gd'),archive)
            gd=target/'tests'/(n+'.gd'); gd.write_text(instrument(n,text,True),encoding='utf-8')
            row=scene(m,n,'public-observer-'+n)
            baseline=next(x for x in m['suites'] if x['label']=='original-'+n)
            eq={'suite':n,'equal':baseline['observers']==row['observers'],'before':baseline['observers'],'after':row['observers']}
            m['equivalence'].append(eq)
            if not row['passed'] or not eq['equal'] or len(row['observers'])!=2: raise r.SafetyError('observer mismatch: '+n)
            if n==NAMES[0]:
                anchor='\twriter.max_records = writer._sequence\n\tEffectManager.run_pipeline(true)'
                negative=text.replace(anchor,'\tcheck(false, "round64 negative before failed commit")\n'+anchor)
            else:
                anchor='\tcheck(EffectManager.skip_runtime_guard(), "真实连锁根事务恢复")'
                negative=text.replace(anchor,'\tcheck(false, "round64 negative before rollback")\n'+anchor)
            if negative==text: raise r.SafetyError('negative anchor absent')
            gd.write_text(negative,encoding='utf-8'); row=scene(m,n,'negative-'+n)
            valid=row['exit_code']==1 and not row['errors'] and row['result'] and row['observed_checks']==row['result']['checks'] and any('round64 negative' in str(x) for x in row['result']['failures'])
            m['negatives'].append({'suite':n,'valid_real_red':bool(valid)})
            if not valid: raise r.SafetyError('negative observer swallowed/error: '+n)
            shutil.copyfile(archive,gd)
            if a.digest(gd)!=m['new_hashes'][n]: raise r.SafetyError('green bytes mismatch')
        for n in NAMES:
            if not scene(m,n,'green-'+n)['passed']: raise r.SafetyError('green failed: '+n)
        m['passed']=True; m['phase']='verified'
    except Exception as exc:
        m['error']=type(exc).__name__+': '+str(exc)
    finally:
        m['logs']=[{'path':str(x.relative_to(owner/'evidence')),'sha256':a.digest(x)} for x in (owner/'evidence').rglob('*.log')]
        m['all_owned_job0']=bool(m['processes']) and all(x.get('exited') and x.get('active_owned_processes')==0 and x.get('log_handles_released') for x in m['processes'])
        save(path,m)
        if m['all_owned_job0']:
            r.tree_bytes(gen)
            shutil.rmtree(gen)
            m['cleanup']='generated_removed'; m['generated_exists_after_cleanup']=gen.exists()
        else: m['cleanup']='retained_process_exit_unproven'; m['passed']=False
        save(path,m)
    print(json.dumps({'passed':m['passed'],'manifest':str(path),'error':m.get('error'),'job0':m['all_owned_job0'],'cleanup':m['cleanup']},ensure_ascii=False))
    return 0 if m['passed'] else 1

def readback(path):
    from collections import Counter
    import difflib
    path = r.contained(Path(path), r.physical_e(ROOT)); owner = path.parent
    if path.name != 'manifest.json' or not re.fullmatch(r'round64-private-[a-f0-9]{32}', owner.name):
        raise r.SafetyError('readback ownership mismatch')
    m = a.load(path)
    receipt = {'manifest':str(path), 'manifest_sha256':a.digest(path), 'gate_current':gate_scan(),
               'runner_sha256':a.digest(Path(__file__)), 'tests':[], 'log_drift':[],
               'unowned_source_drift':m.get('unowned_source_drift'), 'all_owned_job0':m['all_owned_job0'],
               'cleanup':m['cleanup'], 'generated_exists':(owner/'generated').exists(),
               'engine_sha256':m['engine_sha256'], 'native_old_hashes':m['native_old_hashes'],
               'processes':m['processes'], 'equivalence':m['equivalence'], 'negatives':m['negatives']}
    patches = []
    for n in NAMES:
        old_path = owner/'evidence'/'original'/(n+'.gd'); new_path = PROJECT/'tests'/(n+'.gd')
        old = old_path.read_text(encoding='utf-8-sig'); new = new_path.read_text(encoding='utf-8-sig')
        normalized = old
        for before, after, stage in SITES[n]: normalized = normalized.replace(before, after)
        # Assertions include repeated labels as a multiset, with only the approved API substitution.
        checks = lambda text: Counter(x.strip() for x in text.splitlines() if x.strip().startswith('check('))
        missing = list((checks(normalized)-checks(new)).elements())
        added = list((checks(new)-checks(normalized)).elements())
        locations = [{'line':i,'code':line.strip()} for i,line in enumerate(new.splitlines(),1)
                     if any(after in line for before,after,stage in SITES[n])]
        patches.extend(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='original/tests/'+n+'.gd',tofile='current/tests/'+n+'.gd'))
        receipt['tests'].append({'path':'tests/'+n+'.gd','old_sha256':a.digest(old_path),'new_sha256':a.digest(new_path),
                                 'old_archive_matches_freeze':a.digest(old_path)==m['source_hashes']['tests/'+n+'.gd'],
                                 'current_matches_verified_green':a.digest(new_path)==m['new_hashes'][n],
                                 'missing_assertions':missing,'added_assertions':added,'locations':locations})
    for row in m['logs']:
        if a.digest(owner/'evidence'/row['path']) != row['sha256']: receipt['log_drift'].append(row['path'])
    receipt['scenes'] = [{'label':x['label'],'suite':x['suite'],'exit':x['exit_code'],
                          'actual_checks':x['observed_checks'],'declared_checks':x['result']['checks'],
                          'failures':x['result']['failures'],'errors':x['errors']} for x in m['suites']]
    receipt['green_actual'] = sum(x['label'].startswith('green-') for x in m['suites'])
    receipt['green_unique'] = len({x['suite'] for x in m['suites'] if x['label'].startswith('green-')})
    receipt['green_checks'] = sum(x['observed_checks'] for x in m['suites'] if x['label'].startswith('green-'))
    (owner/'evidence'/'migration.patch').write_text(''.join(patches),encoding='utf-8')
    receipt['patch_sha256'] = a.digest(owner/'evidence'/'migration.patch')
    receipt['passed'] = bool(m['passed'] and receipt['all_owned_job0'] and not receipt['generated_exists']
        and not receipt['log_drift'] and receipt['green_actual']==receipt['green_unique']==2
        and all(not t['missing_assertions'] and not t['added_assertions'] and t['old_archive_matches_freeze']
                and t['current_matches_verified_green'] for t in receipt['tests'])
        and receipt['gate_current']['gate_sha256']==m['gate_before']['gate_sha256']
        and not receipt['gate_current']['new'])
    save(owner/'evidence'/'readback.json',receipt)
    print(json.dumps(receipt,ensure_ascii=False,indent=2))
    return 0 if receipt['passed'] else 1

if __name__=='__main__':
    if len(sys.argv)==1: raise SystemExit(prepare())
    if len(sys.argv)==3 and sys.argv[1]=='--verify': raise SystemExit(verify(sys.argv[2]))
    if len(sys.argv)==3 and sys.argv[1]=='--readback': raise SystemExit(readback(sys.argv[2]))
    raise SystemExit('Use no args to prepare; --verify/--readback <exact owned manifest>')
