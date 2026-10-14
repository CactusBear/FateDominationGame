import sys
sys.dont_write_bytecode=True
import os,re,json,hashlib,shutil,importlib.util,concurrent.futures,traceback,ast
from pathlib import Path
P=Path('E:/Projects/Godot/FateDominationGame-master'); owner=Path('E:/scratch/isolated-68b556faf22044668ffd2caae802b640'); gen=owner/'generated'; ev=owner/'evidence'; target=gen/'project'
spec=importlib.util.spec_from_file_location('isolated_runner',P/'tools/run_isolated_godot_test.py'); r=importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
m=json.loads((owner/'manifest.json').read_text(encoding='utf-8'))
m['historical_initial_import_error']=m.pop('error',None); m.pop('traceback',None)
env=os.environ.copy()
for k,c in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','temp'),('TMP','temp'),('TMPDIR','temp')]: env[k]=str(gen/c)
B={'seconds':600,'bytes':8589934592,'min_free':1073741824}
source=Path('E:/scratch/a06-a07-compare-executor/run.py').read_text(encoding='utf-8')
tree=ast.parse(source)
functions=[x for x in tree.body if isinstance(x,ast.FunctionDef)]
exec(compile(ast.Module(body=functions,type_ignores=[]),'reused_runner_functions','exec'),globals())
try:
    if m['repository_drift']: raise RuntimeError('initial source drift')
    current_drift=[n for n,h in m['source_hashes'].items() if digest(P/n)!=h]
    if current_drift: raise RuntimeError('source changed before resume '+str(current_drift))
    out,err,code,_=execute([str(gen/'Godot.exe'),'--headless','--fixed-fps','60','--editor','--import','--path',str(target)],'import-second-real')
    m['import_second']={'exit_code':code,'errors':[x for x in (out+'\n'+err).splitlines() if re.search(r'SCRIPT ERROR|ERROR:',x)],'note':'Same freeze; first cold import already created image resources. Initial preload errors preserved, not treated as clean cold import.'}
    save(owner/'manifest.json',m)
    if code or m['import_second']['errors']: raise RuntimeError('second import failed')
    m['freeze_after_import_drift']=[n for n,h in m['source_hashes'].items() if n!='project.godot' and digest(target/n)!=h]
    if m['freeze_after_import_drift']: raise RuntimeError('import changed inputs')
    original_try=next(x for x in tree.body if isinstance(x,ast.Try))
    start=next(i for i,x in enumerate(original_try.body) if isinstance(x,ast.With) and 'ThreadPoolExecutor' in ast.unparse(x.items[0].context_expr))
    exec(compile(ast.Module(body=original_try.body[start:],type_ignores=[]),'reused_compare_and_negative','exec'),globals())
except Exception as exc:
    m['error']=type(exc).__name__+': '+str(exc); m['traceback']=traceback.format_exc()
finally:
    final=next(x for x in tree.body if isinstance(x,ast.Try)).finalbody
    exec(compile(ast.Module(body=final,type_ignores=[]),'reused_final_readback','exec'),globals())
