import importlib.util, json, os, hashlib
from pathlib import Path
ROOT=Path('E:/scratch/gateway-approved-triage')
spec=importlib.util.spec_from_file_location('triage',ROOT/'run_triage.py'); t=importlib.util.module_from_spec(spec); spec.loader.exec_module(t)
scope=ROOT/'paced-fixed-v2'; project=scope/'project'; evidence=scope/'rollback-evidence'; evidence.mkdir()
fixture=scope/'rollback-fixture'; fixture.mkdir()
source=project/'tests/net_server_match_test.gd'; saved=source.read_bytes(); before=t.sha(source)
old='\t\t# 同步器声明的是单文件无进度期限，不是整个批准清单的总期限。\n\t\t# 夹具按已验证文件数声明有限总上界；单文件超时与完整安装断言均保留。\n\t\tvar sync_wait_budget_msec:int = maxi(45000, int(ceil(sync.timeout_seconds * 1000.0)) * agents[index].session.room_files.size())\n\t\tdeadline = Time.get_ticks_msec() + sync_wait_budget_msec'
new='\t\tdeadline = Time.get_ticks_msec() + 45000'
raw=saved.decode('utf-8'); assert raw.count(old)==1
source.write_text(raw.replace(old,new),encoding='utf-8',newline='\n'); reverted=t.sha(source)
assert reverted == t.sha(ROOT/'paced-legacy-v2/project/tests/net_server_match_test.gd')
env=os.environ.copy()
for key in ['APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR']:
    path=scope/'rollback-runtime'/key.lower(); path.mkdir(parents=True); env[key]=str(path)
env['FATE_TEST_SCRATCH_ROOT']=fixture.as_posix(); env['FATE_R60_ARTIFACT_ROOT']=evidence.as_posix()
cmd=[str(t.ENGINE),'--headless','--fixed-fps','60','--path',str(project),'--scene','res://tests/net_server_gateway_restart_test.tscn','--',fixture.as_posix()]
records=[]; result={}
try:
    out,err,code=t.runner.execute(cmd,env,scope,evidence,'scene',{'seconds':1200,'bytes':8*1024**3,'min_free':0},records)
    result={'command':cmd,'exit':code,'analysis':t.runner.analyze(out,err,code),'job_records':records,'fixture_before_sha256':before,'fixture_rollback_sha256':reverted,'observations':[json.loads(x.split(' ',1)[1]) for x in out.splitlines() if x.startswith('APPROVED_SYNC_OBSERVATION ')]}
finally:
    source.write_bytes(saved)
    result['restored_sha256']=t.sha(source)
    result['hash_restored']=before==t.sha(source)
    assert result['hash_restored']
    (evidence/'receipt.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False),flush=True)
assert code==1 and result['analysis']['result']['failures']==['all approved client files assemble and verify before ready']
assert result['observations'][0]['deadline_reached'] and result['observations'][0]['running'] and result['observations'][0]['sync_error']=='' and result['observations'][0]['session_error']==''
