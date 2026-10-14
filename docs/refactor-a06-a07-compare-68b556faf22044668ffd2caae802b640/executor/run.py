import sys
sys.dont_write_bytecode = True
import os, re, json, hashlib, shutil, uuid, importlib.util, concurrent.futures, traceback
from pathlib import Path
P=Path('E:/Projects/Godot/FateDominationGame-master')
ROOT=Path('E:/scratch')
ENGINE=Path('E:/scratch/round51-engine/Godot_v4.7.2-stable_win64.exe')
spec=importlib.util.spec_from_file_location('isolated_runner',P/'tools/run_isolated_godot_test.py')
r=importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v): p.write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
run_id=uuid.uuid4().hex
owner=ROOT/('isolated-'+run_id); owner.mkdir()
gen=owner/'generated'; gen.mkdir()
ev=owner/'evidence'; ev.mkdir()
m={'run_id':run_id,'owner':str(owner),'generated':str(gen),'processes':[],'suites':[],'mode':'compare','timeout':600,'capture_used':False,'protected_pids':[17120,28100]}
save(owner/'manifest.json',m)
env=os.environ.copy()
for k,c in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','temp'),('TMP','temp'),('TMPDIR','temp')]:
    q=gen/c; q.mkdir(exist_ok=True); env[k]=str(q)
B={'seconds':600,'bytes':8589934592,'min_free':1073741824}
def execute(cmd,label):
    if 'capture' in cmd: raise RuntimeError('capture forbidden')
    for attempt in (1,2):
        lab=label if attempt==1 else label+'-retry'
        try: return (*r.execute(cmd,env,gen,ev,lab,B,m['processes']),lab)
        except r.SafetyError as e:
            save(owner/'manifest.json',m)
            if str(e)!='timeout': raise
            if attempt==2:
                return (ev/(lab+'.stdout.log')).read_bytes().decode('utf-8'),(ev/(lab+'.stderr.log')).read_bytes().decode('utf-8'),m['processes'][-1]['exit_code'],lab

def scene(name,label):
    cmd=[str(gen/'Godot.exe'),'--headless','--fixed-fps','60','--path',str(gen/'project'),'--scene','res://tests/'+name+'.tscn']
    out,err,code,lab=execute(cmd,label)
    timed=next(x for x in m['processes'] if x['label']==lab).get('budget_failure')=='timeout'
    row={'suite':'res://tests/'+name+'.tscn','label':lab,'command':cmd,'exit_code':code,'analysis':r.analyze(out,err,code),'checks':[x for x in out.splitlines() if x.startswith('CHECK ')],'errors':[x for x in (out+'\n'+err).splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',x)],'result_lines':[x for x in out.splitlines() if x.startswith('RESULT ')],'differences':[x for x in out.splitlines() if x.startswith('GOLDEN_DIFF ') or ('baseline equals actual queries:' in x and x.endswith(' false'))],'timed_out':timed}
    row['status']='inconclusive' if timed else ('PASS' if row['analysis']['passed'] else 'RED')
    m['suites'].append(row); save(owner/'manifest.json',m)
    print(json.dumps({k:row[k] for k in ['label','exit_code','status','errors','result_lines','differences']},ensure_ascii=False),flush=True)
    return row

try:
    for q in (P,ROOT,ENGINE): r.physical_e(q)
    paths={'project.godot','icon.svg','docs/refactoring-plan.md','docs/refactoring-golden/text.json','docs/refactoring-golden/areas.json'}
    paths.update('tests/'+n+e for n in ('refactor_text_golden_test','refactor_area_golden_test') for e in ('.gd','.tscn'))
    for folder,exts in [('scripts',{'.gd','.uid'}),('data',{'.json','.png','.jpg','.jpeg','.webp','.svg','.tres','.tscn','.uid'}),('addons/godot_ai',{'.gd','.uid'})]:
        paths.update(q.relative_to(P).as_posix() for q in (P/folder).rglob('*') if q.is_file() and q.suffix in exts)
    for folder in ('addons/fate_server_signals','addons/webrtc_native'):
        paths.update(q.relative_to(P).as_posix() for q in (P/folder).glob('*.gdextension'))
        paths.update(q.relative_to(P).as_posix() for q in (P/folder).rglob('*.dll') if 'x86_64' in q.name and not q.name.startswith('~'))
    # Explicit dependency closure from included source declarations; no historical trees or secrets.
    pending=list(paths); seen=set(); excluded=[]
    while pending:
        name=pending.pop()
        if name in seen: continue
        seen.add(name)
        q=P/name; r.no_links(q)
        if not q.is_file() or q.suffix not in {'.gd','.tscn','.tres','.gdshader','.gdshaderinc','.godot','.gdextension'}: continue
        text=q.read_text(encoding='utf-8-sig')
        for dep in re.findall(r'[\"\'](res://[^\"\'\n]+)[\"\']',text):
            rel=dep[6:]; f=P/rel
            if '..' in Path(rel).parts or not f.is_file(): continue
            if Path(rel).suffix in {'.cfg','.key','.pem'} or any(x in Path(rel).parts for x in ['.godot','scratch','reports','runtime_reports','test','window']):
                excluded.append(rel); continue
            if rel.startswith('tests/') and rel not in paths:
                # Only parse-time test dependencies are allowed.
                if not re.search(r'(preload|load)\(\"'+re.escape(dep)+r'\"\)',text): continue
            if rel not in paths: paths.add(rel); pending.append(rel)
    m['excluded_paths']=sorted(set(excluded))
    m['source_hashes']={name:digest(r.contained(P/name,P)) for name in sorted(paths)}
    m['source_fingerprint']=hashlib.sha256(json.dumps(m['source_hashes'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
    m['fingerprint_encoding']='SHA256 of UTF-8 json.dumps(source_hashes,sort_keys=True,separators=(comma,colon))'
    m['engine_sha256']=digest(ENGINE)
    save(ev/'source-before.json',{'hashes':m['source_hashes'],'fingerprint':m['source_fingerprint'],'engine':m['engine_sha256']})
    save(owner/'manifest.json',m)
    target=gen/'project'
    for name,sha in m['source_hashes'].items():
        q=target/name; q.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(P/name,q)
        if digest(q)!=sha or digest(P/name)!=sha or os.path.samefile(q,P/name): raise RuntimeError('freeze mismatch '+name)
    cfg=(target/'project.godot').read_text(encoding='utf-8-sig')
    if (P/'override.cfg').exists() or 'config/project_settings_override=' in cfg: raise RuntimeError('override refused')
    adjusted=cfg.replace('version_control/autoload_on_startup=true','version_control/autoload_on_startup=false')
    adjusted=re.sub(r'^enabled=PackedStringArray\("res://addons/godot_ai/plugin.cfg"\)$','enabled=PackedStringArray()',adjusted,flags=re.M)
    m['config_transform']={'original_sha256':m['source_hashes']['project.godot'],'reason':'isolated editor only: disable VCS autostart and MCP editor plugin; autoload/application/threading untouched','changes':['version_control/autoload_on_startup=false','editor_plugins/enabled=PackedStringArray()']}
    (target/'project.godot').write_text(adjusted,encoding='utf-8',newline='')
    m['config_transform']['isolated_sha256']=digest(target/'project.godot')
    shutil.copyfile(ENGINE,gen/'Godot.exe')
    if digest(gen/'Godot.exe')!=m['engine_sha256']: raise RuntimeError('engine copy drift')
    probe=gen/'probe'; probe.mkdir()
    app=re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)',cfg,re.M|re.S)
    threading=re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)',cfg,re.M|re.S)
    pc='config_version=5\n[application]\n'+re.sub(r'^run/main_scene(?:\.fate_server)?=.*\n','',app[1],flags=re.M)
    if threading: pc+='\n[threading]\n'+threading[1]
    (probe/'project.godot').write_text(pc,encoding='utf-8'); (probe/'probe.gd').write_text(r.PROBE_SCRIPT.replace("'--headless'","'--headless'"),encoding='utf-8')
    # Add fixed fps to the inherited real child probe, without changing its checks.
    (probe/'probe.gd').write_text(r.PROBE_SCRIPT.replace('["--headless", "--path"','["--headless", "--fixed-fps", "60", "--path"'),encoding='utf-8')
    out,err,code,_=execute([str(gen/'Godot.exe'),'--headless','--fixed-fps','60','--path',str(probe),'--script','res://probe.gd','--',run_id,'main',str(gen)],'probe')
    if code or re.search(r'SCRIPT ERROR|ERROR:',out+err): raise RuntimeError('probe failed')
    m['user_probes']=r.verify_probe(out,gen,run_id)
    out,err,code,_=execute([str(gen/'Godot.exe'),'--headless','--fixed-fps','60','--editor','--import','--path',str(target)],'import')
    m['import']={'exit_code':code,'errors':[x for x in (out+'\n'+err).splitlines() if re.search(r'SCRIPT ERROR|ERROR:',x)]}
    save(owner/'manifest.json',m)
    if code or m['import']['errors']: raise RuntimeError('import failed')
    m['freeze_after_import_drift']=[n for n,h in m['source_hashes'].items() if n!='project.godot' and digest(target/n)!=h]
    if m['freeze_after_import_drift']: raise RuntimeError('import changed frozen inputs')
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures=[pool.submit(scene,'refactor_text_golden_test','A06-compare'),pool.submit(scene,'refactor_area_golden_test','A07-compare')]
        for f in futures: f.result()
    rel='scripts/system/area_action_rules.gd'; q=target/rel
    original=q.read_bytes(); m['mutation']={'path':rel,'before_sha256':digest(q),'repository_sha256_before':digest(P/rel)}
    old=b'\tvar locked: BaseMapArea = SetLocation.locked_area_for_move(player_id, target_area)\n\tif locked == null:\n\t\treturn ""\n\tif locked == target_area:\n\t\treturn "\xe6\x97\xa0\xe6\xb3\x95\xe7\xa7\xbb\xe5\x8a\xa8\xe8\x87\xb3\xe3\x80\x90%s\xe3\x80\x91" % locked._area_name\n\treturn "\xe6\x97\xa0\xe6\xb3\x95\xe7\xa6\xbb\xe5\xbc\x80\xe3\x80\x90%s\xe3\x80\x91" % locked._area_name'
    if original.count(old)!=1: raise RuntimeError('mutation anchor not unique')
    mutated=original.replace(old,b'\treturn ""')
    (ev/'area_action_rules.original.gd').write_bytes(original)
    try:
        q.write_bytes(mutated); m['mutation']['mutated_sha256']=digest(q)
        red=scene('refactor_area_golden_test','A07-empty-lock-negative')
        m['mutation']['red']=red['status']=='RED' and red['exit_code']==1 and not red['errors']
        m['mutation']['lock_specific_failures']=[x for x in red['checks'] if ('locked target rejection text' in x or 'locked origin rejection text' in x) and x.endswith(' false')]
    finally:
        q.write_bytes(original)
        m['mutation']['restored_sha256']=digest(q)
        m['mutation']['restored_original_bytes']=q.read_bytes()==original
        m['mutation']['repository_sha256_after']=digest(P/rel)
        m['mutation']['repository_unchanged']=m['mutation']['repository_sha256_after']==m['mutation']['repository_sha256_before']
        save(owner/'manifest.json',m)
    if not m['mutation']['restored_original_bytes']: raise RuntimeError('restore failed')
    scene('refactor_area_golden_test','A07-restored-compare')
except Exception as exc:
    m['error']=type(exc).__name__+': '+str(exc); m['traceback']=traceback.format_exc()
finally:
    if 'source_hashes' in m:
        m['repository_drift']=[n for n,h in m['source_hashes'].items() if digest(P/n)!=h]
        m['golden_after']={n:digest(P/n) for n in ['docs/refactoring-golden/text.json','docs/refactoring-golden/areas.json']}
        m['copy_golden_after']={n:digest(gen/'project'/n) for n in ['docs/refactoring-golden/text.json','docs/refactoring-golden/areas.json'] if (gen/'project'/n).exists()}
    m['all_job0']=bool(m['processes']) and all(x.get('exited') and x.get('active_owned_processes')==0 and x.get('log_handles_released') for x in m['processes'])
    m['cleanup']='retained_for_readonly_diagnostics'
    m['logs']=[{'path':str(p.relative_to(ev)),'sha256':digest(p),'bytes':p.stat().st_size} for p in ev.glob('*.log')]
    save(owner/'manifest.json',m)
    print(json.dumps({'manifest':str(owner/'manifest.json'),'error':m.get('error'),'job0':m['all_job0'],'repository_drift':m.get('repository_drift'),'mutation':m.get('mutation')},ensure_ascii=False),flush=True)
