import sys
sys.dont_write_bytecode=True
import os,re,json,hashlib,shutil,importlib.util,concurrent.futures,traceback,ast
from pathlib import Path
P=Path('E:/Projects/Godot/FateDominationGame-master'); owner=Path('E:/scratch/isolated-68b556faf22044668ffd2caae802b640'); gen=owner/'generated'; ev=owner/'evidence'; target=gen/'project'
spec=importlib.util.spec_from_file_location('isolated_runner',P/'tools/run_isolated_godot_test.py'); r=importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
m=json.loads((owner/'manifest.json').read_text(encoding='utf-8'))
if not m['all_job0'] or not m['mutation']['restored_original_bytes']: raise RuntimeError('prior Job0 and restore required')
snapshot_index=1
while (owner/('snapshot'+str(snapshot_index))).exists(): snapshot_index+=1
archive=owner/('snapshot'+str(snapshot_index)); archive.mkdir(); shutil.copyfile(owner/'manifest.json',archive/'manifest.json')
for f in list(ev.iterdir()): shutil.move(str(f),str(archive/f.name))
m['prior_snapshot']=archive.name+'/manifest.json'; m['prior_source_fingerprint']=m['source_fingerprint']; m['refresh_reason']='Concurrent source write observed; new current-source freeze, do not combine snapshots.'
m['processes']=[]; m['suites']=[]; m.pop('mutation',None); m.pop('error',None)
env=os.environ.copy()
for k,c in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','temp'),('TMP','temp'),('TMPDIR','temp')]: env[k]=str(gen/c)
B={'seconds':600,'bytes':8589934592,'min_free':1073741824}
tree=ast.parse(Path('E:/scratch/a06-a07-compare-executor/run.py').read_text(encoding='utf-8'))
exec(compile(ast.Module(body=[x for x in tree.body if isinstance(x,ast.FunctionDef)],type_ignores=[]),'runner_functions','exec'),globals())
try:
    paths=set(m['source_hashes'])
    paths.update(q.relative_to(P).as_posix() for q in (P/'scripts').rglob('*') if q.is_file() and q.suffix in {'.gd','.uid'})
    new={n:digest(r.contained(P/n,P)) for n in sorted(paths)}
    m['refresh_changes']=[{'path':n,'before':m['source_hashes'].get(n),'after':h} for n,h in new.items() if m['source_hashes'].get(n)!=h]
    for row in m['refresh_changes']:
        n=row['path']; dst=target/n; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(P/n,dst)
        if digest(dst)!=row['after'] or os.path.samefile(dst,P/n): raise RuntimeError('refresh copy')
    m['source_hashes']=new
    m['source_fingerprint']=hashlib.sha256(json.dumps(new,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    save(ev/'source-before.json',{'hashes':new,'fingerprint':m['source_fingerprint'],'engine':m['engine_sha256']})
    save(owner/'manifest.json',m)
    if any(digest(P/n)!=h for n,h in new.items()): raise RuntimeError('refresh source drift')
    out,err,code,_=execute([str(gen/'Godot.exe'),'--headless','--fixed-fps','60','--editor','--import','--path',str(target)],'import-refreshed-source')
    m['import_current']={'exit_code':code,'errors':[x for x in (out+'\n'+err).splitlines() if re.search(r'SCRIPT ERROR|ERROR:',x)]}
    if code or m['import_current']['errors']: raise RuntimeError('refreshed import failed')
    if any(digest(target/n)!=h for n,h in new.items() if n!='project.godot'): raise RuntimeError('refresh input drift')
    original_try=next(x for x in tree.body if isinstance(x,ast.Try))
    start=next(i for i,x in enumerate(original_try.body) if isinstance(x,ast.With) and 'ThreadPoolExecutor' in ast.unparse(x.items[0].context_expr))
    exec(compile(ast.Module(body=original_try.body[start:],type_ignores=[]),'compare_and_negative','exec'),globals())
except Exception as exc:
    m['error']=type(exc).__name__+': '+str(exc); m['traceback']=traceback.format_exc()
finally:
    exec(compile(ast.Module(body=next(x for x in tree.body if isinstance(x,ast.Try)).finalbody,type_ignores=[]),'final_readback','exec'),globals())
