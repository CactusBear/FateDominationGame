import os, sys, json, shutil, hashlib, importlib.util, time
from pathlib import Path
REPO=Path('E:/Projects/Godot/FateDominationGame-master')
SOURCE=Path('E:/scratch/e08-e12-budget-rerun-job0-20261011/net_server_gateway_restart_test/project')
ROOT=Path('E:/scratch/gateway-approved-triage')
ENGINE=Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
spec=importlib.util.spec_from_file_location('runner',REPO/'tools/run_isolated_godot_test.py'); runner=importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    mode=sys.argv[1]
    scope=ROOT/mode
    if scope.exists(): raise RuntimeError('refuse overwrite')
    project=scope/'project'; evidence=scope/'evidence'; evidence.mkdir(parents=True)
    # Exact existing bounded dependency freeze; independent bytes, never hardlinks.
    shutil.copytree(SOURCE,project)
    fixture=scope/'fixture'; fixture.mkdir()
    source=project/'tests/net_server_match_test.gd'; raw=source.read_text(encoding='utf-8'); old_sha=sha(source)
    (evidence/'fixture-original.gd').write_bytes(source.read_bytes())
    before='\t\tvar accepted: bool = sync.complete and sync.error.is_empty() and agents[index].session.error.is_empty() and agents[index].session.install_room_assets(root)'
    observe='\t\tprint("APPROVED_SYNC_OBSERVATION ",JSON.stringify({"client":index,"complete":sync.complete,"running":sync.running,"completed_files":sync.completed_files,"files":agents[index].session.room_files.size(),"bytes":agents[index].session.room_files.reduce(func(total,item): return total+item.size,0),"sync_error":sync.error,"session_error":agents[index].session.error,"deadline_reached":Time.get_ticks_msec()>=deadline,"active_index":sync._index,"active_hash_present":not sync._active_hash.is_empty(),"pending_offset":sync._receiver.offset_for(1,sync._active_hash) if sync._receiver != null and not sync._active_hash.is_empty() else -1,"no_progress_msec":Time.get_ticks_msec()-sync._last_progress,"connected":agents[index].session.transport.is_connected_to_host()}))\n'+before
    assert raw.count(before)==1
    raw=raw.replace(before,observe)
    if mode == 'diagnostic':
        # Observer only; keep 45000ms predicate and original assertion untouched.
        pass
    elif mode in ['paced-legacy','paced-fixed','fixed','paced-legacy-v2','paced-fixed-v2']:
        if mode in ['paced-fixed','fixed','paced-fixed-v2']:
            old='\t\tdeadline = Time.get_ticks_msec() + 45000'
            new='\t\t# 同步器声明的是单文件无进度期限，不是整个批准清单的总期限。\n\t\t# 夹具按已验证文件数声明有限总上界；单文件超时与完整安装断言均保留。\n\t\tvar sync_wait_budget_msec:int = maxi(45000, int(ceil(sync.timeout_seconds * 1000.0)) * agents[index].session.room_files.size())\n\t\tdeadline = Time.get_ticks_msec() + sync_wait_budget_msec'
            assert raw.count(old)==1
            raw=raw.replace(old,new)
        if mode.startswith('paced-'):
            # Test-only scheduling delay: same real gateway, transfer, hashing and install.
            old='\t\t\tsync.poll()\n'
            new='\t\t\tif index == 0:\n\t\t\t\tvar pace_until:int = Time.get_ticks_msec() + 250\n\t\t\t\twhile Time.get_ticks_msec() < pace_until:\n\t\t\t\t\tawait pump(gateway,agents)\n\t\t\tsync.poll()\n'
            assert raw.count(old)==1
            raw=raw.replace(old,new)
    else: raise RuntimeError('unknown mode')
    source.write_text(raw,encoding='utf-8',newline='\n')
    manifest={str(p.relative_to(project)):sha(p) for p in project.rglob('*') if p.is_file() and '.godot' not in p.parts}
    (evidence/'freeze.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    env=os.environ.copy()
    for k in ['APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR']:
        path=scope/'runtime'/k.lower(); path.mkdir(parents=True); env[k]=str(path)
    env['FATE_TEST_SCRATCH_ROOT']=fixture.as_posix()
    env['FATE_R60_ARTIFACT_ROOT']=evidence.as_posix()
    cmd=[str(ENGINE),'--headless','--fixed-fps','60','--path',str(project),'--scene','res://tests/net_server_gateway_restart_test.tscn','--',fixture.as_posix()]
    records=[]
    try:
        out,err,code=runner.execute(cmd,env,scope,evidence,'scene',{'seconds':1200,'bytes':8*1024**3,'min_free':0},records)
        result={'mode':mode,'command':cmd,'exit':code,'analysis':runner.analyze(out,err,code),'job_records':records,'fixture_original_sha256':old_sha,'fixture_observer_sha256':sha(source),'observations':[json.loads(x.split(' ',1)[1]) for x in out.splitlines() if x.startswith('APPROVED_SYNC_OBSERVATION ')]}
    except Exception as exc:
        result={'error':repr(exc),'job_records':records}; raise
    finally:
        (evidence/'receipt.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(result,ensure_ascii=False),flush=True)
if __name__=='__main__': main()
