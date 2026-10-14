import os, sys, json, shutil, hashlib, importlib.util, re
from pathlib import Path
REPO = Path('E:/Projects/Godot/FateDominationGame-master')
SOURCE = Path('E:/scratch/gateway-approved-triage/fixed/project')
ROOT = Path('E:/scratch/gateway-supervisor-triage')
ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
spec = importlib.util.spec_from_file_location('runner', REPO/'tools/run_isolated_godot_test.py')
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
FIXTURE = 'tests/net_server_match_test.gd'
HELPER = 'tests/gateway_client_content_maintenance.gd'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def instrument(raw, paced):
    old = '\t\tvar accepted: bool = sync.complete and sync.error.is_empty() and agents[index].session.error.is_empty() and agents[index].session.install_room_assets(root)'
    assert raw.count(old) == 1
    raw = raw.replace(old, '\t\tvar probe_install_started:int = Time.get_ticks_msec()\n'+old+'\n\t\tprint("SUPERVISOR_INSTALL ",JSON.stringify({"client":index,"elapsed_msec":Time.get_ticks_msec()-probe_install_started,"accepted":accepted,"ticks_msec":Time.get_ticks_msec()}))')
    old = '\t\t\tsync.poll()\n'
    assert raw.count(old) == 1
    raw = raw.replace(old,'\t\t\tvar probe_started:int = Time.get_ticks_msec()\n'+old+'\t\t\tif Time.get_ticks_msec()-probe_started > 1000:\n\t\t\t\tprint("SUPERVISOR_SYNC_POLL ",JSON.stringify({"client":index,"elapsed_msec":Time.get_ticks_msec()-probe_started,"complete":sync.complete,"ticks_msec":Time.get_ticks_msec()}))\n')
    if paced:
        anchor = '\t\tvar root: String = directory.path_join("client-%s/data" % index)'
        assert raw.count(anchor) == 1
        raw = raw.replace(anchor,'\t\tpreload("res://newtests/supervisor_slow_assembly_fault.gd").bind(sync)\n'+anchor)
    return raw

def prepare(name, paced):
    scope = ROOT/name
    if scope.exists(): raise RuntimeError('refuse overwrite')
    evidence = scope/'evidence'; evidence.mkdir(parents=True)
    project = scope/'project'; shutil.copytree(SOURCE,project)
    fixture = scope/'fixture'; fixture.mkdir()
    for relative in [FIXTURE,HELPER]:
        target=project/relative; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(REPO/relative,target)
    raw=(project/FIXTURE).read_text(encoding='utf-8')
    (project/FIXTURE).write_text(raw if name in ['clean','cache-verified'] else instrument(raw,paced),encoding='utf-8',newline='\n')
    if paced:
        (project/'newtests/supervisor_slow_assembly_fault.gd').write_text('''extends RefCounted
const Maintenance = preload("res://tests/gateway_client_content_maintenance.gd")
class SlowAssembler extends "res://scripts/net/content/room_data_assembler.gd":
	func poll(files_per_poll:int = 2) -> void:
		OS.delay_msec(35)
		super.poll(files_per_poll)
class SlowCooperativeAssembler extends "res://tests/gateway_client_content_maintenance.gd".CooperativeAssembler:
	func poll(files_per_poll:int = 2) -> void:
		OS.delay_msec(35)
		super.poll(files_per_poll)
static func bind(sync) -> void:
	if sync.assembler is Maintenance.CooperativeAssembler:
		var replacement = SlowCooperativeAssembler.new()
		replacement.fixture_maintenance = sync.assembler.fixture_maintenance
		sync.assembler = replacement
	else:
		sync.assembler = SlowAssembler.new()
''',encoding='utf-8',newline='\n')
    return scope,project,evidence,fixture

def execute(scope,project,evidence,fixture,label):
    env=os.environ.copy()
    for k in ['APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR']:
        p=scope/'runtime'/k.lower(); p.mkdir(parents=True,exist_ok=True); env[k]=str(p)
    env['FATE_TEST_SCRATCH_ROOT']=fixture.as_posix(); env['FATE_R60_ARTIFACT_ROOT']=evidence.as_posix()
    cmd=[str(ENGINE),'--headless','--fixed-fps','60','--path',str(project),'--scene','res://tests/net_server_gateway_restart_test.tscn','--',fixture.as_posix()]
    records=[]
    out,err,code=runner.execute(cmd,env,scope,evidence,label,{'seconds':1200,'bytes':8*1024**3,'min_free':0},records)
    result={'command':cmd,'exit':code,'analysis':runner.analyze(out,err,code),'job_records':records,'check_true':sum(x.startswith('CHECK ') and x.endswith('true') for x in out.splitlines()),'check_false':sum(x.startswith('CHECK ') and x.endswith('false') for x in out.splitlines()),'error_count':sum(bool(re.match(r'^\s*(?:SCRIPT\s+)?ERROR:',x)) for x in (out+'\n'+err).splitlines()),'fixture_sha256':sha(project/FIXTURE),'helper_sha256':sha(project/HELPER)}
    (evidence/(label+'.receipt.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False),flush=True)
    return result

def main():
    mode=sys.argv[1]
    if mode not in ['fixed','clean','paced-fixed','paced-fixed-v2','rollback']: raise RuntimeError('invalid mode')
    if mode == 'rollback':
        scope=ROOT/'paced-fixed-v2'; project=scope/'project'; evidence=scope/'evidence'; fixture=scope/'rollback-fixture'; fixture.mkdir()
        target=project/FIXTURE; original=target.read_bytes(); before=sha(target)
        raw=instrument((SOURCE/FIXTURE).read_text(encoding='utf-8'),True)
        observer='newtests/gateway_supervisor_wait_evidence/gateway_route_branch_observer.gd'
        target_observer=project/observer; target_observer.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(REPO/observer,target_observer)
        old_gateway='preload("res://scripts/net/server/server_gateway.gd").new()'
        assert raw.count(old_gateway)==1
        raw=raw.replace(old_gateway,'preload("res://'+observer+'").new()')
        receipt={'before_sha256':before,'rollback_source_sha256':sha(SOURCE/FIXTURE),'observer_sha256':sha(target_observer),'observer_only_change':'return super._route_is_current unchanged; scalar log on false'}
        try:
            target.write_text(raw,encoding='utf-8',newline='\n'); receipt['injected_sha256']=sha(target)
            receipt['execution']=execute(scope,project,evidence,fixture,'rollback')
        finally:
            target.write_bytes(original); receipt['restored_sha256']=sha(target)
            receipt['restored']=before==sha(target)
            (evidence/'rollback-restoration.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
            assert receipt['restored']; print('ROLLBACK_RESTORED '+json.dumps(receipt,ensure_ascii=False),flush=True)
    else:
        scope,project,evidence,fixture=prepare(mode,mode.startswith('paced'))
        execute(scope,project,evidence,fixture,'scene')
if __name__=='__main__': main()
