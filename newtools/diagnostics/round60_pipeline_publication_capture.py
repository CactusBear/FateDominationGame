"""Two one-shot owned E scopes: real pipeline MoveFileW and fresh relay CFG.

Production/native/full executors are read-only. No attach, retry, Sleep, engine
replacement, controlled lock substitution, records or secret archival.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PureWindowsPath
import re
import shutil
import struct
import sys
import uuid

sys.dont_write_bytecode = True
PROJECT = Path(__file__).resolve().parents[2]
HISTORY = Path('E:/scratch/isolated-1105873e41cd4f6a94a999e65ac6af50')
ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
NAMES = ('validation_pipeline_performance_test', 'net_server_relay_cfg_test')


def module(name, relative):
    spec = importlib.util.spec_from_file_location(name, PROJECT / relative)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def digest(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def save(path, value):
    text = json.dumps(value, ensure_ascii=False, indent=2)
    path.write_text(text, encoding='utf-8')
    if path.read_text(encoding='utf-8') != text:
        raise ValueError('JSON artifact readback mismatch')


def exports(path):
    """Read the official declared DLL PE export names, not guessed RVAs."""
    data = path.read_bytes()
    pe = struct.unpack_from('<I', data, 60)[0]
    opt = pe + 24
    size = struct.unpack_from('<H', data, pe+20)[0]
    count = struct.unpack_from('<H', data, pe+6)[0]
    sections = [struct.unpack_from('<8sIIII', data, opt+size+i*40) for i in range(count)]
    def offset(rva):
        return next(raw+rva-va for _, vs, va, rs, raw in sections if va <= rva < va+max(vs,rs))
    rva = struct.unpack_from('<I', data, opt+112)[0]
    table = offset(rva)
    number = struct.unpack_from('<I', data, table+24)[0]
    names = offset(struct.unpack_from('<I', data, table+32)[0])
    result = []
    for i in range(number):
        start = offset(struct.unpack_from('<I', data, names+i*4)[0])
        result.append(data[start:data.index(0,start)].decode('ascii'))
    return result


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('readonly capture contract changed: '+old[:80])
    return text.replace(old,new)


def capture_cpp(capture, debug):
    """Derive a new owned debugger; do not mutate the reviewed original tool."""
    cpp = capture.CPP
    cpp = replace_once(cpp, 'res://tests/round47_assembly_targeted_capture_test.tscn', 'res://tests/validation_pipeline_performance_test.tscn')
    cpp = cpp.replace('preparation-work','full-preparation')
    cpp = replace_once(cpp, 'GetTickCount64()+180000', 'GetTickCount64()+600000')
    cpp = replace_once(cpp, 'if(preserveFailure)must(TerminateProcess(process,124)!=0,"preserve_failed_owned_engine");break;', '(void)preserveFailure;break; // Let original production rejection, CHECKs and cleanup run.')
    cpp = replace_once(cpp, 'identity(L"parent-before",parent(call.dst));', 'identity(L"parent-before",parent(call.dst));identity(L"published-parent-before",parent(parent(call.dst)));snapshot(pi.dwProcessId,call.seq,"before-call");')
    cpp = replace_once(cpp, 'if(!(DWORD)context.Rax)snapshot(pi.dwProcessId,call.seq,"failed-return");', 'snapshot(pi.dwProcessId,call.seq,"after-return");')
    cpp = replace_once(cpp, 'identity(L"parent-after",parent(call.dst));', 'identity(L"parent-after",parent(call.dst));identity(L"published-parent-after",parent(parent(call.dst)));')
    cpp = replace_once(cpp, 'match++;std::printf("OWNED_FILE seq=%u phase=%s pid=%lu handle=%llu access=%lu path=%s\\n",seq,phase,pid,(unsigned long long)e.handle,e.access,utf8(p).c_str());', 'match++;FILE_STANDARD_INFO info{};must(GetFileInformationByHandleEx(copy,FileStandardInfo,&info,sizeof(info))!=0,"owned_file_kind");std::printf("OWNED_FILE seq=%u phase=%s pid=%lu handle=%llu access=%lu directory=%d path=%s\\n",seq,phase,pid,(unsigned long long)e.handle,e.access,info.Directory,utf8(p).c_str());')
    # The gate and API root must also belong to this UUID generated tree.
    cpp = replace_once(cpp, 'fixture_root=argv[3];source_root=argv[4];gate_root=argv[10];api_root=argv[11];', 'fixture_root=argv[3];source_root=argv[4];gate_root=argv[10];api_root=argv[11];must(inside(source_root,parent(argv[2]))&&inside(fixture_root,parent(argv[2])),"owned_UUID_root");')
    result = debug.DEBUGGER_CPP.split('int wmain(',1)[0] + cpp
    if 'DebugActiveProcess(' in result or 'Sleep(' in result:
        raise ValueError('attach/Sleep prohibited')
    return result


def parse_api(capture, text, root, binding):
    rows = capture.parse_capture(text)
    lines = {}
    for prefix in ('API_BEGIN ', 'API_PATH ', 'API_END '):
        values = [dict(re.findall(r'(\w+)=([^\s]+)',x)) for x in text.splitlines() if x.startswith(prefix)]
        if len(values) != len(rows):
            raise ValueError('incomplete raw API pairs')
        lines[prefix] = {int(x['seq']):x for x in values}
    if len(rows) != 1 or rows[0]['target'] != 'preparation-204':
        raise ValueError('exactly one actual formal pipeline call required')
    for row in rows:
        begin,pair,end = (lines[k][row['seq']] for k in ('API_BEGIN ','API_PATH ','API_END '))
        src,dst,base = [PureWindowsPath(x[4:] if x.startswith('\\\\?\\') else x) for x in (pair['source'],pair['destination'],str(root))]
        if not src.is_relative_to(base/'full-preparation') or src.parent != dst.parent or not src.name.startswith(dst.name+'.building-') or dst.name != 'data' or not src.name[len(dst.name+'.building-'):].isdecimal():
            raise ValueError('not actual approved pipeline staging/destination')
        if begin['rva'] not in binding['movefile_call_rvas'] or int(end['return_rva'],16) != int(begin['rva'],16)+6 or begin['teb'] != end['teb']:
            raise ValueError('wrong thread/return instruction')
        row.update(source=pair['source'], destination=pair['destination'], call_rva=begin['rva'], return_rva=end['return_rva'], failure_error=row['last_error'] if row['return_value']==0 else None)
    return rows


def gather_files(runner, history):
    # Explicit previously approved source list. No runtime/records discovery.
    files = set(Path(x) for x in history['freeze_before'])
    pending = list(files)
    while pending:
        rel = pending.pop()
        p = runner.contained(PROJECT/rel, PROJECT)
        if any(x.lower() in {'records','secrets','identities','runtime_reports'} for x in rel.parts):
            raise ValueError('private/runtime input prohibited')
        if p.suffix not in {'.gd','.tscn','.tres','.godot'}:
            continue
        for ref in re.findall(r'res://([^\s\"\'<>]+)',p.read_text(encoding='utf-8-sig')):
            dep = Path(ref)
            if (PROJECT/dep).is_file() and dep not in files and not any(x in runner.EXCLUDED for x in dep.parts):
                runner.contained(PROJECT/dep,PROJECT)
                files.add(dep);pending.append(dep)
    return sorted(files)


def archive_outputs(runner, generated, evidence):
    """Only diagnostics/log/report/manifest bytes; never control or identities."""
    allowed = []
    for directory, dirs, names in os.walk(generated,followlinks=False):
        runner.no_links(directory)
        dirs[:] = [x for x in dirs if x.lower() not in {'records','control','identities','secrets','.git'}]
        for name in names:
            p = Path(directory)/name
            runner.no_links(p)
            if p.suffix == '.log' or name in {'report.json','manifest.json','pipeline-plan.json','scope.json'} or p.parent.name == 'gates':
                if 'identity' in name.lower() or 'secret' in name.lower():
                    continue
                dest = evidence/'runtime'/p.relative_to(generated)
                dest.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(p,dest)
                allowed.append({'path':str(dest.relative_to(evidence)),'sha256':digest(dest)})
    return allowed


def execute_scope(name, files, hashes, history, binding, dll, tools, frozen_config):
    runner,capture,debug = tools
    token = uuid.uuid4().hex
    owner = runner.physical_e('E:/scratch')/('isolated-'+token)
    owner.mkdir()
    generated,evidence = owner/'generated',owner/'evidence'
    generated.mkdir();evidence.mkdir()
    report = {'run_id':token,'generated':str(generated),'suite':name,'processes':[], 'passed':False,
              'runs':1,'source_hashes':hashes,'historical_manifest_sha256':digest(HISTORY/'manifest.json'),
              'binding':binding,'official_dll':dll,'parentbudget0':0,'historical_FAIL_retained':True,
              'root_cause':'UNKNOWN','budgets':{'seconds':600 if name==NAMES[0] else 180,'bytes':8*1024**3,'min_free':1024**3}}
    def checkpoint():
        save(owner/'manifest.json',report);save(evidence/'capture-manifest.json',report)
    print('ROUND60_SCOPE '+str(owner),flush=True)
    checkpoint()
    try:
        project = generated/'project';project.mkdir()
        for rel in files:
            source = runner.contained(PROJECT/rel,PROJECT)
            if digest(source) != hashes[rel.as_posix()]:
                raise ValueError('source drift before scope: '+str(rel))
            dst = project/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dst)
            if digest(dst) != hashes[rel.as_posix()]:
                raise ValueError('copy drift: '+str(rel))
        (project/'project.godot').write_text(frozen_config,encoding='utf-8',newline='')
        engine = generated/'Godot.exe';shutil.copy2(ENGINE,engine)
        if digest(engine)!=binding['engine_sha256']:
            raise ValueError('engine copy mismatch')
        # Reuse current imported resources; no warm retry/import cycle.
        cache = []
        for rel in ('.godot/global_script_class_cache.cfg','.godot/uid_cache.bin','.godot/extension_list.cfg'):
            p = runner.contained(PROJECT/rel,PROJECT);dst = project/rel
            dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dst)
            cache.append({'path':rel,'sha256':digest(p)})
        for p in (PROJECT/'.godot/imported').rglob('*'):
            runner.no_links(p)
            if p.is_file():
                rel = p.relative_to(PROJECT);dst = project/rel
                dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dst)
                cache.append({'path':str(rel),'sha256':digest(p)})
        report['reused_imported_cache']=cache
        report['frozen_hashes']={x.as_posix():digest(project/x) for x in files}
        fixture = generated/'f/complete-0';fixture.mkdir(parents=True)
        env = os.environ.copy()
        for key in list(env):
            if key.startswith('HERMES_ASSEMBLY_') or key in {'HERMES_RECOVERY_VALIDATION_ROOT','FATE_TEST_SCRATCH_ROOT'}:
                env.pop(key,None)
        for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR'):
            p = fixture/key.lower();p.mkdir();env[key]=p.as_posix()
        approved = fixture/'localappdata/hermes/cache/scratch';approved.mkdir(parents=True)
        api_root = approved/('pipeline-'+token)
        env['HERMES_RECOVERY_VALIDATION_ROOT']=api_root.as_posix()
        env['FATE_TEST_SCRATCH_ROOT']=fixture.as_posix()
        report['explicit_environment']={k:env[k] for k in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR','FATE_TEST_SCRATCH_ROOT','HERMES_RECOVERY_VALIDATION_ROOT')}
        # Real main/child E user:// probe, in a separate short Job.
        probe=generated/'probe';probe.mkdir()
        config = frozen_config
        app=re.search(r'^\[application\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)[1]
        threads=re.search(r'^\[threading\]\s*\n(.*?)(?=^\[|\Z)',config,re.M|re.S)[0]
        (probe/'project.godot').write_text('config_version=5\n[application]\n'+app+'\n'+threads,encoding='utf-8')
        (probe/'probe.gd').write_text(runner.PROBE_SCRIPT,encoding='utf-8')
        short=dict(report['budgets'],seconds=180)
        out,err,code=runner.execute([str(engine),'--headless','--path',str(probe),'--script','res://probe.gd','--',token,'main',str(generated)],env,generated,evidence,'user-probe',short,report['processes'])
        if code or re.search(r'SCRIPT ERROR|ERROR:',out+err):
            raise ValueError('E main/child probe rejected')
        report['user_probes']=runner.verify_probe(out,generated,token)
        if any(x['worker_pool_max_threads']!=20 for x in report['user_probes']):
            raise ValueError('20 worker threads required')
        if name == NAMES[0]:
            helper=generated/'assembly_native_probe.py';shutil.copy2(PROJECT/'tools/diagnostics/assembly_native_probe.py',helper)
            gate=generated/'gates';gate.mkdir()
            env.update(HERMES_ASSEMBLY_CAPTURE_GATE=gate.as_posix(),HERMES_ASSEMBLY_PROBE=str(helper),HERMES_ASSEMBLY_PYTHON=sys.executable,_NO_DEBUG_HEAP='1')
            cpp=generated/'capture.cpp';cpp.write_text(capture_cpp(capture,debug),encoding='utf-8')
            shutil.copy2(cpp,evidence/'capture.cpp')
            build=generated/'build.cmd'
            build.write_text(f'@call "D:/VS2022/Common7/Tools/VsDevCmd.bat" -arch=x64 -host_arch=x64\n@cl /nologo /EHsc /std:c++17 /W4 "{cpp}" /Fe:"{generated / "capture.exe"}" /Fo:"{generated / "capture.obj"}" /link dbghelp.lib bcrypt.lib\n',encoding='utf-8')
            out,err,code=capture.compile_owned(runner,['cmd.exe','/d','/c',str(build)],env,generated,evidence,report['processes'])
            if code:
                raise ValueError('owned capture compilation failed')
            shutil.copy2(generated/'capture.exe',evidence/'capture.exe')
            command=[str(generated/'capture.exe'),str(engine),str(project),str(fixture),str(project/'data'),str(generated/'scope.json'),token,digest(helper),binding['engine_sha256'],'600000',str(gate),str(api_root)]
        else:
            command=[str(engine),'--headless','--fixed-fps','60','--path',str(project),'--scene','res://tests/'+name+'.tscn']
        report['command']=command
        report['parent_bytes_before_runtime']=runner.tree_bytes(owner)
        report['parentbudget0']=0  # zero bytes from previous suites/other scopes
        checkpoint()
        execution_error=None
        try:
            out,err,code=runner.execute(command,env,generated,evidence,name,report['budgets'],report['processes'])
        except Exception as exc:
            execution_error=str(exc)
            out=(evidence/(name+'.stdout.log')).read_text(encoding='utf-8',errors='replace')
            err=(evidence/(name+'.stderr.log')).read_text(encoding='utf-8',errors='replace')
            code=next(x.get('exit_code') for x in reversed(report['processes']) if x['label']==name)
        report.update(exit_code=code,execution_error=execution_error,analysis=runner.analyze(out,err,code),
                      actual_checks=[x for x in out.splitlines() if x.startswith('CHECK ')],
                      errors=[x for x in (out+'\n'+err).splitlines() if re.search(r'ERROR:|SCRIPT ERROR|SHADER ERROR|CAPTURE_BLOCK|SECOND_CHANCE',x)],
                      raw_results=[x for x in out.splitlines() if x.startswith('RESULT ')])
        report['actual_check_count']=len(report['actual_checks'])
        report['classification']='executor_environment_abort' if execution_error else 'product_exit'
        if name == NAMES[0]:
            report['api_calls']=parse_api(capture,out,api_root,binding)
            report['raw_native_lines']=[x for x in out.splitlines() if x.startswith(('API_','IDENTITY ','OWNED_FILE ','HANDLE_','OWNED_ENGINE ','ENGINE_EXIT ','DEBUGGER_EXIT ','MODULE ','CALL_FRAME ','CAPTURE_','PIPELINE_CAPTURE_BOUNDARY '))]
            report['formal_failure_captured']=any(x['return_value']==0 for x in report['api_calls'])
            report['root_cause']='actual formal failure captured; attribution not yet proven' if report['formal_failure_captured'] else 'UNKNOWN; fresh success did not reproduce historical formal failure'
            plan=json.loads((generated/'gates/pipeline-plan.json').read_text(encoding='utf-8'))
            report['formal_manifest_files']=len(plan['files'])
            if report['formal_manifest_files']!=204:
                raise ValueError('formal manifest no longer original 204')
            report['no_control_lock_substitution']=True
        report['source_drift_after']=[x.as_posix() for x in files if digest(PROJECT/x)!=hashes[x.as_posix()]]
        report['frozen_drift_after']=[x.as_posix() for x in files if digest(project/x)!=report['frozen_hashes'][x.as_posix()]]
        report['passed']=report['analysis']['passed'] and not report['errors'] and not report['source_drift_after'] and not report['frozen_drift_after']
    except Exception as exc:
        report['blocked']=str(exc)
        report['classification']='SKIP_permission_or_prerequisite' if isinstance(exc,PermissionError) or 'error=5' in str(exc) else 'diagnostic_blocked'
        report['passed']=False
    finally:
        report['archived_outputs']=archive_outputs(runner,generated,evidence)
        # Preserve exact executed scripts/config and readonly helper provenance.
        for rel in ('project.godot','tests/'+name+'.gd'):
            p=generated/'project'/rel
            if p.exists():
                dst=evidence/'executed-source'/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dst)
        for name2 in ('scope.json','assembly_native_probe.py','build.cmd'):
            p=generated/name2
            if p.exists():shutil.copy2(p,evidence/name2)
        shutil.copy2(Path(__file__),evidence/Path(__file__).name)
        report['parent_bytes_after_runtime']=runner.tree_bytes(owner)
        report['generated_tree_metadata']=[{'path':str(p.relative_to(generated)),'size':p.stat().st_size} for p in generated.rglob('*') if p.is_file()]
        report['artifact_hashes']={str(p.relative_to(evidence)):digest(p) for p in evidence.rglob('*') if p.is_file() and p.name!='capture-manifest.json'}
        report['Job0']=all(x.get('exited') is True and x.get('active_owned_processes')==0 and x.get('log_handles_released') is True for x in report['processes'])
        checkpoint()
        for rel,sha in report['artifact_hashes'].items():
            if digest(evidence/rel)!=sha:raise ValueError('artifact SHA readback failed')
        report['artifacts_readback_verified']=True
        report['deleted_generated_bytes']=runner.tree_bytes(generated)
        runner.delete_owned(generated,owner)
        report['generated_exists_after_cleanup']=generated.exists()
        checkpoint()
        print(json.dumps({k:report.get(k) for k in ('suite','run_id','passed','blocked','exit_code','classification','actual_check_count','api_calls','Job0','generated_exists_after_cleanup')},ensure_ascii=False),flush=True)
    return owner,report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute',action='store_true')
    parser.add_argument('--preflight',action='store_true')
    args=parser.parse_args()
    if args.execute == args.preflight:parser.error('exactly one mode required')
    runner=module('round60_runner','tools/run_isolated_godot_test.py')
    capture=module('round60_capture','tools/diagnostics/assembly_publish_failure_capture.py')
    debug=module('round60_debug','tools/diagnostics/native_cold_import_debug.py')
    integrated=module('round60_integrated','tools/tests/test_round29_integrated_evidence.py')
    history=json.loads((HISTORY/'manifest.json').read_text(encoding='utf-8'))
    binding=capture.engine_binding(ENGINE)
    runner.physical_e('E:/scratch');runner.no_links(ENGINE)
    source=Path('E:/scratch/round38-assembly-owner/dir_access_windows-official.cpp')
    if digest(source)!=capture.SOURCE_HASH:raise ValueError('reviewed official Windows source hash changed')
    dllpath=PROJECT/'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll'
    dll={'path':str(dllpath),'sha256':digest(dllpath),'exports':exports(dllpath)}
    if 'fate_server_signals_init' not in dll['exports']:raise ValueError('official extension entry absent')
    files=gather_files(runner,history)
    files=[p for p in files if not p.name.startswith('~') or p.suffix.lower()!='.dll']
    hashes={x.as_posix():digest(PROJECT/x) for x in files}
    config,transform=integrated.transform_isolated_editor_vcs((PROJECT/'project.godot').read_text(encoding='utf-8-sig'))
    if 'worker_pool/max_threads=20' not in config:raise ValueError('thread budget changed')
    server=(PROJECT/'assets/config/server.cfg').read_text(encoding='utf-8-sig')
    if not re.search(r'(?m)^random_sim_budget_sec\s*=\s*15(?:\.0)?\s*$',server):raise ValueError('formal default budget changed')
    capture_cpp(capture,debug)
    readonly=[PROJECT/'tools/run_isolated_godot_test.py',PROJECT/'tools/diagnostics/assembly_publish_failure_capture.py',PROJECT/'tools/diagnostics/assembly_native_probe.py',PROJECT/'tools/diagnostics/native_cold_import_debug.py',PROJECT/'tools/tests/test_round29_integrated_evidence.py',ENGINE,dllpath]
    readonly_hashes={str(x):digest(x) for x in readonly}
    preflight={'files':len(files),'engine_binding':binding,'dll':dll,'transform':transform,'same_source_hashes':hashes,
               'source_delta_vs_round58':[x for x in history['freeze_before'] if hashes.get(x)!=history['freeze_before'][x]],
               'official_source_sha256':digest(source),'runs_each':1,'no_attach':True,'no_retry':True,
               'readonly_hashes':readonly_hashes,'history_original_preserved':True}
    if args.preflight:
        print(json.dumps({k:v for k,v in preflight.items() if k!='same_source_hashes'},ensure_ascii=False,indent=2));return 0
    results=[]
    for name in NAMES:
        owner,report=execute_scope(name,files,hashes,history,binding,dll,(runner,capture,debug),config)
        results.append({'owner':str(owner),'manifest':str(owner/'evidence/capture-manifest.json'),'passed':report['passed'],'blocked':report.get('blocked')})
    summary={'preflight':preflight,'scopes':results,'readonly_drift':[str(p) for p in readonly if digest(p)!=readonly_hashes[str(p)]],
             'historical_FAIL_retained':True,'root_cause':'UNKNOWN until actual failing call captured and causal lifecycle proven'}
    destination=Path(results[0]['owner'])/'two-scope-readback.json'
    save(destination,summary)
    print('ROUND60_TWO_SCOPE '+str(destination),flush=True)
    return 0 if all(x['passed'] for x in results) and not summary['readonly_drift'] else 2


if __name__=='__main__':
    raise SystemExit(main())
