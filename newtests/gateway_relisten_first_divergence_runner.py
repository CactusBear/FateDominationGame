"""Exact gateway relisten scene; immutable source freeze, two-attempt ceiling.

Only metadata is inspected while the owned Job runs. Worker engine logs are
archived after Job0; config, tickets and recovery payloads are never printed.
Current-source drift is recorded for frozen-input diagnostics, never a GREEN.
"""
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
ENGINE = Path('E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7/generated/Godot.exe')
SCENE = 'res://tests/gateway_relisten_acceptance_test.tscn'
spec = importlib.util.spec_from_file_location('isolated', PROJECT/'tools/run_isolated_godot_test.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save(owner, manifest):
    (owner/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')

def main():
    phase = sys.argv[1]
    if phase not in {'prepare','probe','import','attempt1','attempt2'}:
        raise ValueError('unknown phase')
    if phase == 'prepare':
        runner.physical_e(PROJECT)
        runner.physical_e(ENGINE)
        if (PROJECT/'override.cfg').exists():
            raise ValueError('uncovered settings override')
        config = (PROJECT/'project.godot').read_text(encoding='utf-8')
        if re.search(r'^\s*config/project_settings_override',config,re.M):
            raise ValueError('uncovered settings override')
        token = uuid.uuid4().hex
        owner = Path('E:/scratch')/('isolated-'+token)
        generated = owner/'generated'
        target = generated/'project'
        target.mkdir(parents=True)
        (owner/'evidence').mkdir()
        manifest = {'run_id':token,'owner':str(owner),'generated':str(generated),
            'project':str(target),'engine':str(ENGINE),'engine_sha256':digest(ENGINE),
            'scene':SCENE,'processes':[],'results':{},'source_hashes':{},
            'budgets':{'seconds':300,'bytes':4*1024**3,'min_free':1024**3},
            'cleanup':'retained_evidence','max_business_attempts':2}
        save(owner,manifest)
        includes = ['project.godot','scripts','assets','data','addons',
            'tests/gateway_relisten_acceptance_test.gd','tests/gateway_relisten_acceptance_test.tscn',
            'tests/match_journal_test.gd']
        for rel in runner.source_files(PROJECT,includes):
            if rel.name.startswith('~') and rel.suffix == '.dll':
                continue
            source = PROJECT/rel
            destination = target/rel
            destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(source,destination)
            sha = digest(destination)
            if digest(source) != sha:
                raise ValueError('source changed during freeze: '+rel.as_posix())
            manifest['source_hashes'][rel.as_posix()] = sha
        cfg = target/'project.godot'
        cfg.write_text(config.replace('version_control/autoload_on_startup=true',
            'version_control/autoload_on_startup=false'),encoding='utf-8',newline='\n')
        manifest['frozen_project_sha256'] = digest(cfg)
        manifest['editor_transform'] = 'only isolated VCS autoload disabled'
        save(owner,manifest)
        print('OWNER='+owner.as_posix())
        return 0
    owner = runner.physical_e(sys.argv[2])
    manifest = json.loads((owner/'manifest.json').read_text(encoding='utf-8'))
    if phase in manifest['results'] or any(r['label']==phase for r in manifest['processes']):
        raise ValueError('refusing repeated phase/evidence overwrite')
    if phase.startswith('attempt') and not all(manifest['results'].get(x,{}).get('passed') for x in ['probe','import']):
        raise ValueError('probe/import prerequisite failed')
    target = Path(manifest['project'])
    generated = Path(manifest['generated'])
    evidence = owner/'evidence'
    if digest(ENGINE) != manifest['engine_sha256']:
        raise ValueError('engine drift')
    if digest(target/'project.godot') != manifest['frozen_project_sha256']:
        raise ValueError('frozen project drift')
    manifest.setdefault('current_source_drift_before_phase', {})[phase] = [
        rel for rel,sha in manifest['source_hashes'].items()
        if digest(PROJECT/rel) != sha]
    for rel,sha in manifest['source_hashes'].items():
        if rel != 'project.godot' and digest(target/rel) != sha:
            raise ValueError('freeze drift: '+rel)
    fixture = generated/phase
    fixture.mkdir(exist_ok=True)
    env = os.environ.copy()
    for key,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','tmp'),('TMP','tmp'),('TMPDIR','tmp')]:
        path = fixture/sub
        path.mkdir(exist_ok=True)
        env[key] = path.as_posix()
    env['FATE_TEST_SCRATCH_ROOT'] = fixture.as_posix()
    if phase == 'probe':
        probe = fixture/'probe'
        probe.mkdir()
        config = (target/'project.godot').read_text(encoding='utf-8')
        application = re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)
        threading = re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)
        config = 'config_version=5\n[application]\n'+application[1]
        config = re.sub(r'^run/main_scene=.*\n','',config,flags=re.M)
        if threading:
            config += '\n[threading]\n'+threading[1]
        (probe/'project.godot').write_text(config,encoding='utf-8')
        (probe/'probe.gd').write_text(runner.PROBE_SCRIPT,encoding='utf-8')
        cmd = [str(ENGINE),'--headless','--fixed-fps','60','--path',probe.as_posix(),
            '--script','res://probe.gd','--',manifest['run_id'],'main',generated.as_posix()]
    else:
        cmd = [str(ENGINE),'--headless','--fixed-fps','60','--path',target.as_posix()]
        cmd += ['--editor','--import'] if phase == 'import' else ['--scene',SCENE]
    manifest['results'][phase] = {'status':'launch_registered'}
    save(owner,manifest)
    try:
        out,err,code = runner.execute(cmd,env,generated,evidence,phase,manifest['budgets'],manifest['processes'])
        errors = [line for line in (out+'\n'+err).splitlines() if 'SCRIPT ERROR' in line or line.startswith('ERROR:')]
        result = {'exit':code,'engine_errors':errors}
        if phase == 'probe':
            result['user_probes'] = runner.verify_probe(out,generated,manifest['run_id'])
            result['passed'] = code == 0 and not errors
        elif phase == 'import':
            result['passed'] = code == 0 and not errors
        else:
            result.update(runner.analyze(out,err,code))
            checks = [(i,line) for i,line in enumerate(out.splitlines(),1) if line.startswith('CHECK ')]
            failed = [(i,line) for i,line in checks if line.endswith(' false')]
            result['check_count'] = len(checks)
            result['first_false'] = failed[0] if failed else None
            result['public_observations'] = [(i,line) for i,line in enumerate(out.splitlines(),1) if line.startswith(('RELISTEN_WORKER ','RELISTEN_CLOSE '))]
            result['worker_logs'] = []
            for index,path in enumerate(sorted((fixture/'worker-rooms').glob('*/engine.*.log'))):
                archive = evidence/(phase+'-worker-'+str(index)+'.engine.log')
                shutil.copy2(path,archive)
                text = archive.read_text(encoding='utf-8')
                sequence = [{'line':i,'stage':m[1],'result':int(m[2])}
                    for i,line in enumerate(text.splitlines(),1)
                    if (m:=re.fullmatch(r'SERVER_ROOM_STARTUP stage=([a-z_]+) result=(-1|0|1)',line))]
                result['worker_logs'].append({'archive':archive.name,'sha256':digest(archive),
                    'sequence':sequence,'last_completed':next((x for x in reversed(sequence) if x['result']==0),None),
                    'ready_banner':any(line.startswith('SERVER_ROOM_READY ') for line in text.splitlines()),
                    'errors':[{'line':i,'text':line} for i,line in enumerate(text.splitlines(),1) if line.startswith('ERROR:') or 'SCRIPT ERROR' in line]})
            result['passed'] = result['passed'] and len(result['worker_logs'])==1 and not any(x['errors'] for x in result['worker_logs'])
        result['current_source_matches_freeze'] = not manifest['current_source_drift_before_phase'][phase] and all(
            digest(PROJECT/rel)==sha for rel,sha in manifest['source_hashes'].items())
        if phase.startswith('attempt') and not result['current_source_matches_freeze']:
            result['passed'] = False
            result.setdefault('reasons', []).append('current_source_drift_diagnostic_only')
        manifest['results'][phase] = result
        print(json.dumps(result,ensure_ascii=False))
        print('\n'.join(line for line in out.splitlines() if line.startswith(('CHECK ','RESULT ','RELISTEN_WORKER ','RELISTEN_CLOSE '))))
    except Exception as exc:
        manifest['results'][phase] = {'error':type(exc).__name__+': '+str(exc),'passed':False}
        raise
    finally:
        manifest['source_unchanged_after_phase'] = all(digest(PROJECT/rel)==sha for rel,sha in manifest['source_hashes'].items())
        save(owner,manifest)
        print('MANIFEST='+ (owner/'manifest.json').as_posix())
    return 0 if result['passed'] else 1

if __name__ == '__main__':
    sys.exit(main())
