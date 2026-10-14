"""Single owned RED/GREEN startup projection, reusing the existing Job runner."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import uuid

PROJECT = Path('E:/Projects/Godot/FateDominationGame-master')
spec = importlib.util.spec_from_file_location('isolated', PROJECT/'tools/run_isolated_godot_test.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
ENGINE = Path('E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/generated/Godot.exe')
phase = sys.argv[1]
if phase not in {'prepare','import','import-fixed','red','green','smoke'}:
    raise ValueError('unknown startup verification phase')
if phase == 'prepare':
    token = uuid.uuid4().hex
    owner = Path('E:/scratch')/('isolated-'+token)
    generated = owner/'generated'
    project = generated/'project'
    evidence = owner/'evidence'
    project.mkdir(parents=True)
    evidence.mkdir()
    files = runner.source_files(PROJECT,['project.godot','scripts','assets','data','addons',
        'newtests/round74_worker_startup_error_test.gd','newtests/round74_worker_startup_error_test.tscn'])
    hashes = {}
    for rel in files:
        if rel.name.startswith('~') and rel.suffix == '.dll':
            continue
        target = project/rel
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(PROJECT/rel,target)
        hashes[rel.as_posix()] = hashlib.sha256(target.read_bytes()).hexdigest()
    cfg = project/'project.godot'
    text = cfg.read_text(encoding='utf-8')
    text = text.replace('version_control/autoload_on_startup=true','version_control/autoload_on_startup=false')
    cfg.write_text(text,encoding='utf-8',newline='\n')
    manifest = {'run_id':token,'generated':str(generated),'owner':str(owner),
        'project':str(project),'engine':str(ENGINE),'engine_sha256':hashlib.sha256(ENGINE.read_bytes()).hexdigest(),
        'source_hashes':hashes,'processes':[],'results':{},'retained':True}
    (owner/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print('OWNER='+owner.as_posix())
    sys.exit(0)
owner = runner.physical_e(sys.argv[2])
manifest_path = owner/'manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
if phase in manifest['results']:
    raise ValueError('refusing to overwrite original phase evidence')
generated = Path(manifest['generated'])
project = Path(manifest['project'])
evidence = owner/'evidence'
fixture = generated/phase
fixture.mkdir(exist_ok=True)
for sub in ('appdata','localappdata','tmp'):
    (fixture/sub).mkdir(exist_ok=True)
env = os.environ.copy()
for k,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','tmp'),('TMP','tmp'),('TMPDIR','tmp')]:
    env[k] = (fixture/sub).as_posix()
env['FATE_TEST_SCRATCH_ROOT'] = fixture.as_posix()
env['ROUND74_STARTUP_CASE'] = 'smoke' if phase == 'smoke' else 'diagnostic'
cmd = [str(ENGINE),'--headless','--fixed-fps','60','--path',project.as_posix()]
if phase.startswith('import'):
    cmd += ['--editor','--import']
else:
    cmd += ['--scene','res://newtests/round74_worker_startup_error_test.tscn']
try:
    out,err,code = runner.execute(cmd,env,generated,evidence,phase,
        {'seconds':180,'bytes':4*1024**3,'min_free':1024**3},manifest['processes'])
    result = {'exit':code,'engine_errors':[line for line in (out+'\n'+err).splitlines() if 'SCRIPT ERROR' in line or line.startswith('ERROR:')]}
    if not phase.startswith('import'):
        result.update(runner.analyze(out,err,code))
    manifest['results'][phase] = result
    print(json.dumps(result,ensure_ascii=False))
    print('\n'.join(line for line in (out+'\n'+err).splitlines() if line.startswith(('CHECK ','RESULT ','ERROR:','SCRIPT ERROR:','STARTUP_ERROR ','SETUP_ERROR '))))
finally:
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('MANIFEST='+manifest_path.as_posix())
sys.exit(0 if (phase.startswith('import') and code == 0 and not result['engine_errors']) or result.get('passed') is True else 1)
