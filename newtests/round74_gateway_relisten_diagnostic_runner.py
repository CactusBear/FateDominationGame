"""One bounded gateway relisten scene, current frozen production, real owned worker."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import uuid

PROJECT = Path('E:/Projects/Godot/FateDominationGame-master')
spec = importlib.util.spec_from_file_location('isolated', PROJECT/'tools/run_isolated_godot_test.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
ENGINE = Path('E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/generated/Godot.exe')
TEST = 'tests/gateway_relisten_acceptance_test'
BASE = 'tests/match_journal_test.gd'
phase = sys.argv[1]
if phase not in {'prepare', 'import', 'run'}:
    raise ValueError('unknown phase')
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
if phase == 'prepare':
    runner.physical_e(ENGINE)
    token = uuid.uuid4().hex
    owner = runner.physical_e('E:/scratch')/('isolated-'+token)
    generated = owner/'generated'
    project = generated/'project'
    evidence = owner/'evidence'
    project.mkdir(parents=True)
    evidence.mkdir()
    files = runner.source_files(PROJECT, ['project.godot','scripts','assets','data','addons',TEST+'.gd',TEST+'.tscn',BASE])
    hashes = {}
    for rel in files:
        if rel.name.startswith('~') and rel.suffix == '.dll':
            continue
        target = project/rel
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(PROJECT/rel,target)
        hashes[rel.as_posix()] = sha(target)
    cfg = project/'project.godot'
    text = cfg.read_text(encoding='utf-8').replace('version_control/autoload_on_startup=true','version_control/autoload_on_startup=false')
    cfg.write_text(text,encoding='utf-8',newline='\n')
    original = (project/(TEST+'.gd')).read_text(encoding='utf-8')
    body = original[original.index('func check_real_worker_close('):original.index('\nfunc run()')]
    anchor = '\tvar gateway = Gateway.new()\n'
    assert body.count(anchor) == 1 and body.count('+40000') == 1
    body = body.replace(anchor, anchor + '''\tvar deployment = preload("res://scripts/net/server/server_bootstrap.gd").read_configuration("res://assets/config/server.cfg")
\tcheck(deployment is Dictionary and deployment.has("startup_seconds"), "冻结部署启动期限必须显式声明")
\tif not deployment is Dictionary or not deployment.has("startup_seconds"): return
\tvar startup:float = float(deployment.startup_seconds)
\tcheck(is_finite(startup) and startup > 0.0, "部署启动期限为有限正数")
\tif not is_finite(startup) or startup <= 0.0: return
\tgateway.manager.startup_seconds = startup
\tprint("RELISTEN_DEPLOYMENT startup_seconds=", startup)
''').replace('+40000', '+int((gateway.manager.startup_seconds+10.0)*1000.0)')
    assert re.findall(r'^\s*check\(.*$', body, re.M)[2:] == re.findall(r'^\s*check\(.*$', original[original.index('func check_real_worker_close('):original.index('\nfunc run()')], re.M)
    acceptance = project/'newtests/gateway_deployment_relisten_test.gd'
    acceptance.parent.mkdir(exist_ok=True)
    acceptance.write_text('extends "res://'+TEST+'.gd"\n\n'+body,encoding='utf-8')
    scene = acceptance.with_suffix('.tscn')
    scene.write_text('[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://newtests/gateway_deployment_relisten_test.gd" id="1"]\n\n[node name="DeploymentRelisten" type="Node"]\nscript = ExtResource("1")\n',encoding='utf-8')
    manifest = {'run_id':token,'generated':str(generated),'owner':str(owner),'project':str(project),
        'engine':str(ENGINE),'engine_sha256':sha(ENGINE),'source_hashes':hashes,
        'frozen_project_sha256':sha(cfg),'processes':[],'results':{},'retained':True,
        'budget_seconds':1200,'maximum_business_attempts':1,
        'acceptance_scene':'res://newtests/gateway_deployment_relisten_test.tscn',
        'acceptance_hashes':{str(p.relative_to(project)):sha(p) for p in (acceptance,scene)}}
    (owner/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print('OWNER='+owner.as_posix())
    sys.exit(0)
owner = runner.physical_e(sys.argv[2])
manifest_path = owner/'manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
if phase in manifest['results'] or any(x['label']==phase for x in manifest['processes']):
    raise ValueError('refusing repeated launch/evidence overwrite')
generated = Path(manifest['generated'])
project = Path(manifest['project'])
evidence = owner/'evidence'
if sha(ENGINE) != manifest['engine_sha256'] or sha(project/'project.godot') != manifest['frozen_project_sha256']:
    raise ValueError('engine/settings drift')
for rel,digest in {**manifest['source_hashes'],**manifest['acceptance_hashes']}.items():
    if rel != 'project.godot' and sha(project/rel) != digest:
        raise ValueError('freeze drift: '+rel)
fixture = generated/phase
fixture.mkdir(exist_ok=True)
for sub in ('appdata','localappdata','tmp'):
    (fixture/sub).mkdir(exist_ok=True)
env = os.environ.copy()
for k,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','tmp'),('TMP','tmp'),('TMPDIR','tmp')]:
    env[k] = (fixture/sub).as_posix()
env['FATE_TEST_SCRATCH_ROOT'] = fixture.as_posix()
cmd = [str(ENGINE),'--headless','--fixed-fps','60','--path',project.as_posix()]
cmd += ['--editor','--import'] if phase=='import' else ['--scene',manifest['acceptance_scene']]
result = {}
manifest['results'][phase] = {'status':'launch_registered'}
manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
try:
    out,err,code = runner.execute(cmd,env,generated,evidence,phase,
        {'seconds':manifest['budget_seconds'],'bytes':4*1024**3,'min_free':1024**3},manifest['processes'])
    result = {'exit':code,'engine_errors':[x for x in (out+'\n'+err).splitlines() if 'SCRIPT ERROR' in x or x.startswith('ERROR:')]}
    if phase=='run':
        result.update(runner.analyze(out,err,code))
        logs = list((fixture/'worker-rooms').glob('*/engine.*.log'))
        children = []
        for index,log in enumerate(logs):
            archive = evidence/('worker-'+str(index)+'-engine.log')
            shutil.copy2(log,archive)
            text = archive.read_text(encoding='utf-8')
            stages = re.findall(r'^SERVER_ROOM_STARTUP stage=(\w+) result=(-?\d+)$',text,re.M)
            complete = [s for s,r in stages if r=='0']
            children.append({'log':archive.as_posix(),'sha256':sha(archive),'stages':stages,
                'last_complete':complete[-1] if complete else None,
                'errors':[x for x in text.splitlines() if 'SCRIPT ERROR' in x or x.startswith('ERROR:')],
                'server_room_ready':any(x.startswith('SERVER_ROOM_READY') for x in text.splitlines())})
        result['children'] = children
        result['first_false'] = next((x for x in out.splitlines() if x.startswith('CHECK ') and x.endswith(' false')),None)
        result['observations'] = [json.loads(x.split(' ',1)[1]) for x in out.splitlines() if x.startswith(('RELISTEN_WORKER ','RELISTEN_CLOSE '))]
        result['production_source_drift'] = [rel for rel,d in manifest['source_hashes'].items() if rel.startswith(('scripts/','addons/')) and sha(PROJECT/rel)!=d]
        result['passed'] = result.get('passed') is True and result['result']['checks']==40 and len(children)==1 and children[0]['server_room_ready'] and not children[0]['errors'] and not result['production_source_drift']
    result['active_owned_processes'] = manifest['processes'][-1]['active_owned_processes']
    manifest['results'][phase] = result
    print(json.dumps(result,ensure_ascii=False))
    print('\n'.join(x for x in (out+'\n'+err).splitlines() if x.startswith(('CHECK ','RESULT ','RELISTEN_','ERROR:','SCRIPT ERROR:'))))
except Exception as exc:
    manifest['results'][phase] = {'exception':str(exc)}
    raise
finally:
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('MANIFEST='+manifest_path.as_posix())
sys.exit(0 if (phase=='import' and result.get('exit')==0 and not result['engine_errors']) or result.get('passed') is True else 1)
