"""Only the two save/restore diagnostics, once each, one frozen input.

No production writes, old identities, global ERROR exemptions, or whole config archives.
"""
import sys
sys.dont_write_bytecode = True
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import time
import uuid

PROJECT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('r60_isolation', PROJECT/'tools/run_isolated_godot_test.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
SUITES = [('server_shutdown_close_handoff_test', 180), ('net_server_gateway_restart_test', 600)]
OLD = Path('E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50')
ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def dependencies():
    names = set()
    queue = [Path('tests')/(name+ext) for name, _ in SUITES for ext in ('.gd','.tscn')]
    # Resolve explicit test imports transitively. Production assets/scripts are
    # explicit directory includes, not the entire tests tree or historical records.
    while queue:
        rel = queue.pop()
        if rel in names:
            continue
        path = PROJECT/rel
        runner.contained(path, PROJECT)
        names.add(rel)
        if path.suffix in ('.gd','.tscn'):
            for ref in re.findall(r'res://(tests/[^"\s]+\.(?:gd|tscn))',path.read_text(encoding='utf-8-sig')):
                queue.append(Path(ref))
        uid = Path(str(rel)+'.uid')
        if (PROJECT/uid).is_file():
            names.add(uid)
    files = runner.source_files(PROJECT, ['project.godot','scripts','assets','addons','data',*[x.as_posix() for x in names]])
    return [x for x in files if not (x.name.startswith('~') and x.suffix.lower()=='.dll')]


def transform(text):
    # Exactly the existing isolated editor VCS authorization; no gameplay fields.
    blocks = re.split(r'(?m)^(?=\[[^\n]+\]\s*$)',text)
    for index, block in enumerate(blocks):
        if not block.startswith('[editor]'):
            continue
        block, count1 = re.subn(r'(?m)^version_control/plugin_name=.*\n','',block)
        block, count2 = re.subn(r'(?m)^version_control/autoload_on_startup=.*$', 'version_control/autoload_on_startup=false',block)
        if (count1,count2)!=(1,1):
            raise runner.SafetyError('VCS authorization count mismatch')
        blocks[index]=block
    result=''.join(blocks)
    if not re.search(r'(?m)^worker_pool/max_threads=20$',result):
        raise runner.SafetyError('pool must stay20')
    return result


def safe_document(value):
    # Secrets never enter artifact copies, including seemingly harmless hashes of keys.
    forbidden={'private_key','public_key','actor_key','identity_key','member_identities','resume_hashes','resume_previous','room_password','process_token','key_pem','join_password'}
    if isinstance(value,dict):
        for key, item in value.items():
            if key.lower() in forbidden or ('secret' in key.lower() and key != 'raw_nonsecret'):
                raise runner.SafetyError('secret field refused in diagnostic artifact')
            safe_document(item)
    elif isinstance(value,list):
        for item in value:
            safe_document(item)


def archive_files(fixtures, evidence):
    copied=[]
    for path in fixtures.rglob('*'):
        if not path.is_file():
            continue
        runner.no_links(path)
        approved = (path.name=='godot.log' or re.fullmatch(r'engine\.[a-f0-9]{32}\.log',path.name) or path.name=='evidence.json' or re.fullmatch(r'continuation-[01]\.json',path.name))
        if not approved:
            continue
        if path.suffix=='.json':
            safe_document(json.loads(path.read_text(encoding='utf-8')))
        dest=evidence/'worker'/path.relative_to(fixtures)
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(path,dest)
        if sha(path)!=sha(dest):
            raise runner.SafetyError('artifact copy changed')
        copied.append({'path':dest.relative_to(evidence).as_posix(),'sha256':sha(dest)})
    return copied


def late_receipts(fixtures,evidence):
    """Read only the same captured request bindings after real Job0; no replacements."""
    index=[]
    source=evidence/'server_shutdown_close_handoff_test/shutdown-evidence.json'
    if source.exists():
        doc=json.loads(source.read_text(encoding='utf-8'))
        bindings={}
        originals={event['request_id']:event['binding'] for event in doc['evidence'] if event.get('stage')=='console-close-stop'}
        for event in doc['evidence']:
            for entry in event.get('rooms',[]):
                request=entry.get('request_id','')
                receipt=entry.get('receipt',{})
                # After release live pid=-1 is not the immutable submitted pid.
                b=entry.get('submitted_binding',{}).get('binding',originals.get(request,entry.get('binding',{})))
                expected={'room':b.get('room'),'pid':b.get('pid'),'instance':b.get('instance_id'),'authority_host_mode':b.get('authority_host_mode'),'request_id':request}
                if receipt and all(receipt.get(k)==v for k,v in expected.items()):
                    bindings[(entry['directory'],request)]=dict(entry,binding=b)
        for (directory,request),entry in bindings.items():
            path=Path(directory)/'control'/(request+'.response.json')
            row={'request_id':request,'binding':entry['binding'],'path':path.as_posix(),'exists':path.is_file()}
            if path.is_file():
                value=json.loads(path.read_text(encoding='utf-8'));safe_document(value)
                digest=sha(path)
                row['sha256']=digest
                row['unchanged']=digest==entry['receipt_sha256']
                b=entry['binding']
                row['bound']=all(value.get(k)==expected for k,expected in {'room':b['room'],'pid':b['pid'],'instance':b['instance_id'],'authority_host_mode':b['authority_host_mode'],'request_id':request}.items())
                dest=evidence/'late'/f'{request}.response.json'
                dest.parent.mkdir(exist_ok=True)
                shutil.copyfile(path,dest)
                row['copy_readback']=sha(dest)==digest==sha(path)
                if not all(row[k] for k in ('unchanged','bound','copy_readback')):
                    raise runner.SafetyError('late receipt replacement or binding failure')
            else:
                raise runner.SafetyError('late captured receipt missing')
            index.append(row)
    return index


def finalize_existing(manifest, approved_root):
    """Archive-only recovery. It is forbidden to start/import/retry a Godot case."""
    manifest=runner.contained(manifest,approved_root)
    owner=manifest.parent
    m=json.loads(manifest.read_text(encoding='utf-8'))
    if owner.name!='isolated-'+m.get('run_id','') or Path(m['generated'])!=owner/'generated':
        raise runner.SafetyError('existing owner mismatch')
    if len(m.get('suites',[]))!=2 or {r['suite'] for r in m['suites']}!={s for s,_ in SUITES}:
        raise runner.SafetyError('archive-only requires the two existing actual case rows')
    if any(p.get('exited') is not True or p.get('active_owned_processes')!=0 or p.get('log_handles_released') is not True for p in m['processes']):
        raise runner.SafetyError('existing Job0/log release not proven')
    generated=Path(m['generated']);evidence=owner/'evidence'
    m['previous_archive_attempt']={'cleanup':m.get('cleanup'),'error':m.get('error')}
    # The retained first archive used .log broadly. Remove only those exact
    # self-copied journals, never original generated/source/old evidence paths.
    for row in m.get('worker_archive',[]):
        path=evidence/row['path']
        if path.name in {'match.log','transactions.log'}:
            runner.contained(path,evidence)
            if sha(path)!=row['sha256']: raise runner.SafetyError('journal archive changed; retain')
            path.unlink()
    m['worker_archive']=archive_files(generated/'f',evidence)
    m['late_receipts']=late_receipts(generated/'f',evidence)
    for path in evidence.rglob('*.json'):
        if 'frozen-inputs' not in path.parts:
            safe_document(json.loads(path.read_text(encoding='utf-8')))
    m['artifact_index']=[{'path':p.relative_to(evidence).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size} for p in evidence.rglob('*') if p.is_file()]
    m['artifact_readback']=all(sha(evidence/x['path'])==x['sha256'] for x in m['artifact_index'])
    if not m['artifact_readback']: raise runner.SafetyError('existing readback failed')
    m['archive_only_finalizer_sha256']=sha(__file__)
    save(manifest,m)
    runner.delete_owned(generated,owner)
    m['cleanup']='generated_removed'
    m['archive_only_finalized']=True
    m['passed']=all(r['passed'] for r in m['suites']) and not m.get('error') and not m.get('source_drift') and not m.get('frozen_drift')
    save(manifest,m)
    print(json.dumps({'manifest':manifest.as_posix(),'passed':m['passed'],'cleanup':m['cleanup'],'archive_only':True},ensure_ascii=False))
    return 0 if m['passed'] else 1


def readback_existing(manifest, approved_root):
    """Read archived facts only; it cannot promote earlier missing evidence."""
    manifest=runner.contained(manifest,approved_root)
    owner=manifest.parent
    m=json.loads(manifest.read_text(encoding='utf-8'))
    if owner.name!='isolated-'+m.get('run_id',''):
        raise runner.SafetyError('readback owner mismatch')
    evidence=owner/'evidence'
    hashes=all(sha(runner.contained(evidence/x['path'],evidence))==x['sha256'] for x in m['artifact_index'])
    if not hashes or any(p.get('active_owned_processes')!=0 or p.get('exited') is not True for p in m['processes']):
        raise runner.SafetyError('archive hash/Job0 mismatch')
    restart=evidence/'net_server_gateway_restart_test/restart-first-failure.json'
    d=json.loads(restart.read_text(encoding='utf-8'));safe_document(d)
    target='tests/net_server_recovery_midmatch_test.gd'
    target_path=evidence/'frozen-inputs'/target
    shutdown=evidence/'server_shutdown_close_handoff_test/shutdown-evidence.json'
    sd=json.loads(shutdown.read_text(encoding='utf-8'))
    receipts=[]
    for event in sd['evidence']:
        for entry in event.get('rooms',[]):
            raw=entry.get('receipt',{})
            if not raw or not entry.get('receipt_copy_ok'): continue
            b=entry.get('submitted_binding',{}).get('binding',entry.get('binding',{}))
            expected={'room':b.get('room'),'pid':b.get('pid'),'instance':b.get('instance_id'),'authority_host_mode':b.get('authority_host_mode'),'request_id':entry.get('request_id')}
            path=evidence/'server_shutdown_close_handoff_test'/('response-%d-%s.json'%(event['serial'],entry['request_id']))
            copied=json.loads(path.read_text(encoding='utf-8'))
            receipts.append({'stage':event['stage'],'request_id':entry['request_id'],'submitted_binding':b,'live_binding':entry['binding'],'immutable_request_bound':all(copied.get(k)==v for k,v in expected.items()),'copied_sha256':sha(path),'source_capture_sha256':entry['receipt_sha256'],'readback':sha(path)==entry['receipt_sha256'],'copy':path.relative_to(owner).as_posix(),'response':copied})
    clients=[]
    for x in d['clients']:
        v=x['view']
        clients.append({'client':x['client'],'error':x['error'],'seq':v.get('seq'),'phase':v.get('phase'),'round':v.get('round'),'game_over':v.get('game_over'),'observer':v.get('observer'),'current_player':v.get('current_player'),'pending':x['pending'],'battle_broadcast':v.get('battle_broadcast'),'can_end':x['actions'].get('can_end'),'target_round_ge_2':int(v.get('round',0))>=2,'target_game_over_false':v.get('game_over',True) is False,'decisions_at_failure':'not captured by baseline inherited fixture; round condition already false'})
    result={'manifest_sha256':sha(manifest),'fingerprint':m['fingerprint'],'artifact_hash_readback':hashes,'artifact_count':len(m['artifact_index']),'job0':True,'source_drift':m.get('source_drift'),'frozen_drift':m.get('frozen_drift'),'generated_exists':(owner/'generated').exists(),'suites':m['suites'],'target_source':target,'target_source_sha256':sha(target_path),'target_frozen_hash_matches':sha(target_path)==m['frozen_hashes'][target],'target_predicate':target_path.read_text(encoding='utf-8').splitlines()[3],'restart_first_failure':{'path':restart.relative_to(owner).as_posix(),'sha256':sha(restart),'reason':d['reason'],'stage':d['stage'],'events':d['events'],'clients':clients,'poll_count':d['poll_count'],'max_poll_gap_msec':d['max_poll_gap_msec']},'shutdown_archived_receipts':receipts,'late_original_file_readback':m.get('late_receipts',[]),'gap':'Live-pid binding flag rejects successful receipt after release pid=-1; immutable submitted binding independently verified here, but only the original late index is a post-Job0 live-file read. Do not manufacture a lost historical receipt or seed causality.'}
    out=owner/'round60-first-failure-readback.json';save(out,result)
    if json.loads(out.read_text(encoding='utf-8'))!=result: raise runner.SafetyError('readback report changed')
    print(json.dumps({'readback':out.as_posix(),'sha256':sha(out),'hashes':hashes,'jobs':len(m['processes']),'clients':clients},ensure_ascii=False))
    return 0


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--approved-root',required=True)
    parser.add_argument('--preflight-only',action='store_true')
    parser.add_argument('--finalize-existing',help='Only archive/read back a finished retained run; never retry')
    parser.add_argument('--readback-existing',help='Only verify existing hashes/first failure; never start Godot')
    args=parser.parse_args()
    root=runner.physical_e(args.approved_root)
    if args.readback_existing:
        return readback_existing(args.readback_existing,root)
    if args.finalize_existing:
        return finalize_existing(args.finalize_existing,root)
    files=dependencies()
    before={p.as_posix():sha(PROJECT/p) for p in files}
    fingerprint=hashlib.sha256(json.dumps(before,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    if args.preflight_only:
        print(json.dumps({'selected':[s for s,_ in SUITES],'source_files':len(files),'fingerprint':fingerprint}))
        return 0
    token=uuid.uuid4().hex
    owner=root/('isolated-'+token)
    generated=owner/'generated';evidence=owner/'evidence';target=generated/'project';fixtures=generated/'f'
    target.mkdir(parents=True);fixtures.mkdir();evidence.mkdir()
    m={'run_id':token,'generated':str(generated),'fingerprint':fingerprint,'source_hashes':before,'executor_sha256':sha(__file__),'suites':[],'processes':[],'cleanup':'not_started','sourcePASS':False,'releasePASS':False}
    manifest=owner/'manifest.json';save(manifest,m)
    print(json.dumps({'started_manifest':manifest.as_posix(),'fingerprint':fingerprint}),flush=True)
    env=os.environ.copy()
    for key in list(env):
        if key.startswith(('HERMES_ASSEMBLY_','FATE_','FD_','ROUND')) or key=='HERMES_RECOVERY_VALIDATION_ROOT':
            env.pop(key,None)
    for key,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','tmp'),('TMP','tmp'),('TMPDIR','tmp')]:
        (generated/sub).mkdir(exist_ok=True);env[key]=(generated/sub).as_posix()
    (generated/'localappdata/hermes/cache/scratch').mkdir(parents=True)
    budgets={'seconds':180,'bytes':8*1024**3,'min_free':1024**3}
    engine=generated/'Godot.exe'
    try:
        for rel in files:
            dest=target/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(PROJECT/rel,dest)
            if sha(dest)!=before[rel.as_posix()]:
                raise runner.SafetyError('source changed during freeze')
            if rel.suffix in {'.gd','.tscn','.gdextension'}:
                archive=evidence/'frozen-inputs'/rel;archive.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(dest,archive)
        config=(target/'project.godot').read_text(encoding='utf-8-sig')
        transformed=transform(config)
        (target/'project.godot').write_text(transformed,encoding='utf-8',newline='')
        frozen={p.as_posix():sha(target/p) for p in files};m['frozen_hashes']=frozen
        shutil.copyfile(ENGINE,engine);m['engine_sha256']=sha(engine)
        if sha(ENGINE)!=sha(engine): raise runner.SafetyError('engine copy mismatch')
        m['historical_logs']=[]
        for name,_ in SUITES:
            for ext in ('stdout','stderr'):
                old=OLD/'evidence'/f'complete-{name}.{ext}.log'
                archive=evidence/'historical'/old.name;archive.parent.mkdir(exist_ok=True)
                shutil.copyfile(old,archive)
                m['historical_logs'].append({'original':old.as_posix(),'sha256':sha(old),'readback':sha(old)==sha(archive)})
        probe=generated/'probe';probe.mkdir()
        app=re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)',transformed,re.M|re.S)[1]
        thread=re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)',transformed,re.M|re.S)[0]
        (probe/'project.godot').write_text('config_version=5\n[application]\n'+app+'\n'+thread,encoding='utf-8')
        (probe/'probe.gd').write_text(runner.PROBE_SCRIPT,encoding='utf-8')
        out,err,code=runner.execute([engine.as_posix(),'--headless','--path',probe.as_posix(),'--script','res://probe.gd','--',token,'main',generated.as_posix()],env,generated,evidence,'probe',budgets,m['processes'])
        if code or re.search(r'SCRIPT ERROR|ERROR:',out+err): raise runner.SafetyError('main worker probe failed')
        m['user_probes']=runner.verify_probe(out,generated,token)
        out,err,code=runner.execute([engine.as_posix(),'--headless','--editor','--import','--path',target.as_posix()],env,generated,evidence,'import',budgets,m['processes'])
        m['import']={'exit':code,'errors':[l for l in (out+err).splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|ERROR:',l)]}
        if code or m['import']['errors']: raise runner.SafetyError('cold import failed')
        for name,seconds in SUITES:
            if any(sha(target/p)!=frozen[p.as_posix()] for p in files): raise runner.SafetyError('frozen drift before case')
            fixture=fixtures/name;fixture.mkdir()
            artifact=evidence/name;artifact.mkdir()
            local=env.copy()
            for key,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata')]:
                (fixture/sub).mkdir();local[key]=(fixture/sub).as_posix()
            (fixture/'localappdata/hermes/cache/scratch').mkdir(parents=True)
            local.update(FATE_TEST_SCRATCH_ROOT=fixture.as_posix(),ROUND56_HANDOFF_ROOT=fixture.as_posix(),FATE_R60_ARTIFACT_ROOT=artifact.as_posix())
            if name=='net_server_gateway_restart_test': local['FATE_R39_CORRECTNESS']='1'
            command=[engine.as_posix(),'--headless','--fixed-fps','60','--path',target.as_posix(),'--scene','res://tests/'+name+'.tscn','--',fixture.as_posix()]
            row={'suite':name,'command':command,'budget_seconds':seconds,'runs':1}
            try:
                out,err,code=runner.execute(command,local,generated,evidence,name,dict(budgets,seconds=seconds),m['processes'])
            except Exception as exc:
                out=(evidence/(name+'.stdout.log')).read_text(encoding='utf-8');err=(evidence/(name+'.stderr.log')).read_text(encoding='utf-8')
                code=m['processes'][-1].get('exit_code');row['execution_error']=str(exc)
            row.update(exit=code,**runner.analyze(out,err,code))
            row['observed_checks']=len(re.findall(r'(?m)^CHECK\b',out))
            row['first_failed_check']=next((line for line in out.splitlines() if line.startswith('CHECK ') and line.endswith(' false')),None)
            row['errors']=[line for line in (out+err).splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',line)]
            row['performance_gate']=[json.loads(line.split(' ',1)[1]) for line in out.splitlines() if line.startswith('GATEWAY_PERFORMANCE_GATE ')]
            m['suites'].append(row);save(manifest,m)
            print(json.dumps(row,ensure_ascii=False),flush=True)
            if not m['processes'][-1]['exited'] or m['processes'][-1]['budget_failure']:
                raise runner.SafetyError('owned job/budget safety stop')
        m['source_drift']=[p.as_posix() for p in files if sha(PROJECT/p)!=before[p.as_posix()]]
        m['frozen_drift']=[p.as_posix() for p in files if sha(target/p)!=frozen[p.as_posix()]]
    except Exception as exc:
        m['error']=type(exc).__name__+': '+str(exc)
    finally:
        try:
            if not m['processes'] or any(p.get('exited') is not True or p.get('active_owned_processes')!=0 or p.get('log_handles_released') is not True for p in m['processes']):
                raise runner.SafetyError('Job0/log release not proven; no cleanup')
            m['worker_archive']=archive_files(fixtures,evidence)
            m['late_receipts']=late_receipts(fixtures,evidence)
            for path in evidence.rglob('*.json'):
                if 'frozen-inputs' not in path.parts:
                    safe_document(json.loads(path.read_text(encoding='utf-8')))
            m['artifact_index']=[{'path':p.relative_to(evidence).as_posix(),'sha256':sha(p),'bytes':p.stat().st_size} for p in evidence.rglob('*') if p.is_file()]
            m['artifact_readback']=all(sha(evidence/x['path'])==x['sha256'] for x in m['artifact_index'])
            save(manifest,m)
            if not m['artifact_readback']: raise runner.SafetyError('artifact readback failed')
            runner.delete_owned(generated,owner)
            m['cleanup']='generated_removed'
        except Exception as exc:
            m['cleanup']='retained: '+str(exc)
        m['passed']=len(m['suites'])==2 and all(r['passed'] for r in m['suites']) and not m.get('error') and not m.get('source_drift') and not m.get('frozen_drift') and m['cleanup']=='generated_removed'
        save(manifest,m)
    print(json.dumps({'manifest':manifest.as_posix(),'passed':m['passed'],'error':m.get('error'),'cleanup':m['cleanup']},ensure_ascii=False),flush=True)
    return 0 if m['passed'] else 1


if __name__=='__main__':
    raise SystemExit(main())
