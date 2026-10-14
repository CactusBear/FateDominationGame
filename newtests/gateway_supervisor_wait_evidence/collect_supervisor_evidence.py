import json, pathlib, hashlib, shutil, re
REPO=pathlib.Path('E:/Projects/Godot/FateDominationGame-master')
ROOT=pathlib.Path('E:/scratch/gateway-supervisor-triage')
SOURCE=pathlib.Path('E:/scratch/gateway-approved-triage/fixed/project')
DEST=REPO/'newtests/gateway_supervisor_wait_evidence'
FIXTURE='tests/net_server_match_test.gd'
HELPER='tests/gateway_client_content_maintenance.gd'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def copy(source,name):
    target=DEST/name
    if target.exists():
        if sha(source)==sha(target): return
        raise RuntimeError('refuse changed overwrite '+str(target))
    shutil.copy2(source,target)
def safe_loss(path):
    data=json.loads(path.read_text(encoding='utf-8'))
    out={k:data.get(k) for k in ['ok','room','pid','instance','authority_host_mode','reason']}
    result=data.get('result',{})
    out['result']={k:result.get(k) for k in ['closing','saved','room_state_saved']}
    return {'source':str(path),'source_sha256':sha(path),'content':out}
def stats(path,err,receipt):
    out=path.read_text(encoding='utf-8'); error=err.read_text(encoding='utf-8')
    checks=[x for x in out.splitlines() if x.startswith('CHECK ')]
    rows=[x for x in checks if 'all approved client files assemble and verify before ready' in x]
    record=json.loads(receipt.read_text(encoding='utf-8'))
    assert all(x['active_owned_processes']==0 and x['exited'] for x in record['job_records'])
    return {'check_true':sum(x.endswith('true') for x in checks),'check_false':sum(x.endswith('false') for x in checks),'approved_assertions':rows,'exit':record['exit'],'engine_errors':sum(bool(re.match(r'^\s*(?:SCRIPT\s+)?ERROR:',x)) for x in (out+'\n'+error).splitlines()),'job_active':[x['active_owned_processes'] for x in record['job_records']],'result':record['analysis']['result'],'stdout_sha256':sha(path),'stderr_sha256':sha(err),'receipt_sha256':sha(receipt)}
def main():
    if (DEST/'verification-summary.json').exists():
        raise RuntimeError('collection already finalized; preserve completed evidence')
    summary={}
    for mode,label,name in [('fixed','scene','fixed'),('paced-fixed-v2','scene','paced-fixed'),('paced-fixed-v2','rollback','rollback'),('clean','scene','clean'),('diagnostic','scene','diagnostic-incomplete'),('paced-fixed','scene','fault-script-invalid')]:
        base=ROOT/mode/'evidence'
        receipt=base/(label+'.receipt.json')
        if not receipt.exists() and mode=='diagnostic': receipt=base/'receipt.json'
        summary[name]=stats(base/(label+'.stdout.log'),base/(label+'.stderr.log'),receipt)
        for suffix,source in [('stdout.log',base/(label+'.stdout.log')),('stderr.log',base/(label+'.stderr.log')),('receipt.json',receipt)]: copy(source,name+'.'+suffix)
        if name in ['fixed','paced-fixed','rollback','clean']:
            fixture_key='rollback-fixture' if label=='rollback' else 'fixture'
            out=(base/(label+'.stdout.log')).read_text(encoding='utf-8')
            ready=[json.loads(x.split(' ',1)[1]) for x in out.splitlines() if x.startswith('GATEWAY_NATIVE_READY ')]
            for item in ready:
                worker=pathlib.Path(item['directory'])
                for engine in sorted(worker.glob('engine.*.log')):
                    copy(engine,name+'.'+engine.name)
                loss=worker/'supervisor-loss.json'
                if loss.exists(): summary[name]['supervisor_loss']=safe_loss(loss)
    restore=ROOT/'paced-fixed-v2/evidence/rollback-restoration.json'
    copy(restore,'rollback-restoration.json')
    summary['rollback_restore']=json.loads(restore.read_text(encoding='utf-8'))
    interrupted=ROOT/'paced-fixed/evidence/rollback-interrupted.gd'
    previously_restored=ROOT/'paced-fixed/project'/FIXTURE
    summary['discarded_interrupted_restore']={'interrupted_sha256':sha(interrupted),'restored_sha256_before_cleanup':sha(previously_restored),'expected':'fc014f485c38e317a1915e47ce03070e189cfad49927d14b8cee8cf09351a353','outer_tool_timeout_seconds':420,'valid_fault_proof':False}
    assert summary['discarded_interrupted_restore']['restored_sha256_before_cleanup']==summary['discarded_interrupted_restore']['expected']
    copy(interrupted,'discarded-interrupted-fixture.gd')
    assert summary['rollback_restore']['restored']
    assert summary['rollback_restore']['before_sha256']==summary['rollback_restore']['restored_sha256']
    historical=pathlib.Path('E:/scratch/gateway-approved-triage/fixed')
    worker=historical/'fixture/server-match-38784-5837207/workers/d19619ca9705a50fa36cb15d809332f0'
    summary['historical_loss']=safe_loss(worker/'supervisor-loss.json')
    config=json.loads((worker/'config.json').read_text(encoding='utf-8'))
    summary['historical_config']={'source_sha256':sha(worker/'config.json'),'fields':{k:config.get(k) for k in ['id','port','instance_id','authority_host_mode','supervisor_timeout_seconds']}}
    receipt=json.loads((historical/'evidence/restart-first-failure.json').read_text(encoding='utf-8'))
    summary['historical_retired_bindings']={'source_sha256':sha(historical/'evidence/restart-first-failure.json'),'bindings':receipt['bindings']}
    logs=(historical/'evidence/scene.stdout.log').read_text(encoding='utf-8').splitlines()
    events=[]
    ordinal=0
    for line,text in enumerate(logs,1):
        if text.startswith('R60_CLIENT_EVENT '):
            ordinal+=1
            item=json.loads(text.split(' ',1)[1])
            if item.get('client')==1:
                events.append({'stdout_line':line,'event_ordinal':ordinal,'content':item})
    summary['historical_client1_events']=events
    for name in ['scene.stdout.log','scene.stderr.log']: copy(historical/'evidence'/name,'historical.'+name)
    copy(worker/'engine.e9b5e7d0e23628fd08a06fd5f2788b5a.log','historical.engine.log')
    copy(SOURCE/FIXTURE,'fixture-before.gd')
    # All owned jobs have exited; remove test-only injection/observer and restore input baselines.
    restoration=[]
    for mode in ['diagnostic','fixed','paced-fixed','paced-fixed-v2','clean']:
        project=ROOT/mode/'project'
        for relative,base in [(FIXTURE,REPO/FIXTURE),('tests/net_server_gateway_restart_test.gd',SOURCE/'tests/net_server_gateway_restart_test.gd')]:
            target=project/relative
            before=sha(target); target.write_bytes(base.read_bytes())
            restoration.append({'mode':mode,'file':relative,'before':before,'after':sha(target),'baseline':sha(base),'equal':sha(target)==sha(base)})
        for relative in ['newtests/supervisor_slow_assembly_fault.gd','newtests/gateway_supervisor_wait_evidence/gateway_route_branch_observer.gd']:
            target=project/relative
            if target.exists(): target.unlink()
    assert all(x['equal'] for x in restoration)
    summary['instrumentation_restoration']=restoration
    # Freeze content equality, allowing only the already observed CRLF/LF representation difference.
    production=[]
    for file in sorted((SOURCE/'scripts').rglob('*.gd')):
        relative=file.relative_to(SOURCE); current=REPO/relative
        if not current.exists(): continue
        same=file.read_bytes()==current.read_bytes()
        semantic=file.read_text(encoding='utf-8')==current.read_text(encoding='utf-8')
        production.append({'file':str(relative),'freeze_sha256':sha(file),'repository_sha256':sha(current),'byte_equal':same,'newline_normalized_equal':semantic})
    summary['production_comparison']={'compared':len(production),'byte_equal':sum(x['byte_equal'] for x in production),'newline_normalized_equal':sum(x['newline_normalized_equal'] for x in production),'differences':[x for x in production if not x['byte_equal']]}
    summary['changed_inputs']={x:sha(REPO/x) for x in [FIXTURE,HELPER,'newtests/gateway_supervisor_wait_evidence/run_supervisor_triage.py','newtests/gateway_supervisor_wait_evidence/gateway_route_branch_observer.gd']}
    (DEST/'verification-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in summary.items() if k not in ['instrumentation_restoration','historical_client1_events','rollback_restore']},ensure_ascii=False,indent=2))
if __name__=='__main__': main()
