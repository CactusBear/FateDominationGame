"""Round52 current production role candidate execution (owned E root only)."""
from __future__ import annotations
import argparse, hashlib, json, os, re, shutil, subprocess, sys, time
from pathlib import Path
sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools/release'))
import freeze_prepare as freeze
import package_audit as audit
import release_contract as contract
from path_safety import checked

ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
TEMPLATES = Path('C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable')
DLL = 'addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll'
PRESETS = {'client':'FateDomination_demo_v1', 'server':'FateServer Windows', 'signaling':'FateSignaling Windows'}
EXES = {'client':'FateDomination.exe','server':'FateServer.exe','signaling':'FateSignaling.exe'}


def digest_json(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()


def save(root, manifest):
    (root / 'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')


def environment(root):
    env = os.environ.copy()
    for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR'):
        path = checked(root / 'user' / key)
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    return env


def run(root, m, name, command, cwd, timeout=180, allow_errors=False):
    log = root / 'evidence' / (name+'.log')
    log.parent.mkdir(parents=True,exist_ok=True)
    row = {'name':name,'command':[str(x) for x in command],'cwd':str(cwd),'timeout_seconds':timeout,'log':str(log)}
    start=time.monotonic()
    with log.open('wb') as stream:
        proc=subprocess.Popen(row['command'],cwd=cwd,env=environment(root),stdout=stream,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        row['pid']=proc.pid
        m['steps'].append(row);save(root,m)
        try:
            code=proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            row['timed_out']=True;proc.kill();code=proc.wait(timeout=5)
    row.update(exit_code=code,exit_hex=f'0x{code & 0xffffffff:08X}',seconds=time.monotonic()-start,exited=proc.poll() is not None,log_sha256=freeze.sha(log))
    text=log.read_text(encoding='utf-8',errors='replace')
    row['error_lines']=[line for line in text.splitlines() if 'ERROR:' in line or 'SCRIPT ERROR' in line]
    save(root,m)
    if code != 0 or row.get('timed_out', False):
        raise RuntimeError(f'{name} failed: {row}')
    if row['error_lines'] and not allow_errors:
        raise RuntimeError(f'{name} ERROR log: {row["error_lines"]}')
    return row


def selected_source():
    return [p for p in freeze.inventory(REPO) if not p.startswith('.godot/') and '.hermes-tmp.' not in p]


def source_check(m):
    rels=selected_source()
    previous=m['source_files']
    drift={'added':sorted(set(rels)-set(previous)),'removed':sorted(set(previous)-set(rels)),
           'changed':[p for p in previous if not (REPO/p).is_file() or freeze.sha(REPO/p)!=previous[p]]}
    if any(drift.values()):
        m['source_drift']=drift
        raise RuntimeError('RUNTIME_SOURCE_DRIFT: '+str(drift))
    m['source_drift']=drift


def transformed_presets(snapshot, role, rels):
    if role=='signaling':
        text=freeze.transform(snapshot,'FateServer Windows',rels,'signaling')['export_presets.cfg']
        text=text.replace('name="FateServer Windows"','name="FateSignaling Windows"').replace('custom_features="fate_server"','custom_features="fate_server,fate_signaling"')
        return text
    return freeze.transform(snapshot,PRESETS[role],rels,role)['export_presets.cfg']


def prepare(root):
    checked(root)
    if root.drive.upper()!='E:' or root.exists():raise ValueError('fresh physical E root required')
    root.mkdir(parents=True)
    m={'owner':'sa-1-round52-current-production-release','source':str(REPO),'root':str(root),'status':'PREPARING','steps':[],
       'engine':{'path':str(ENGINE),'sha256':freeze.sha(ENGINE)},'templates':{},'source_drift':{},'roles':{},
       'classification':'CURRENT_ORIGINAL_DLL_HEADLESS_CANDIDATE_NOT_FINAL_INTEGRATED_HUMAN_PACKAGE',
       'remaining':['full_current_headless_suite','GUI_owned_by_sa-2-c4f0f589','default_settings_full_worker_incident','full_cleanup_integration','multi_machine_cross_network_full_match'],
       'native_unreleased':['process_tree_owner_core new source not built into original production DLL','temporary_cleanup_core new source not built into original production DLL']}
    save(root,m)
    try:
        assert m['engine']['sha256']=='ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424'
        rels=selected_source(); hashes={p:freeze.sha(REPO/p) for p in rels}
        m['source_files']=hashes;m['source_fingerprint']=digest_json(hashes)
        assert hashes[DLL]=='92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd'
        transformed=freeze.transform(REPO,None,rels)
        snap=root/'source-snapshot';snap.mkdir()
        for rel in rels:
            src=checked(REPO/rel);dst=snap/rel;dst.parent.mkdir(parents=True,exist_ok=True)
            if freeze.sha(src)!=hashes[rel]:raise RuntimeError('copy drift: '+rel)
            if rel in transformed:dst.write_text(transformed[rel],encoding='utf-8',newline='\n')
            else:shutil.copyfile(src,dst)
        source_check(m)
        m['snapshot_files']=audit.manifest(snap);m['snapshot_fingerprint']=digest_json(m['snapshot_files'])
        m['transforms']={rel:{'source_sha256':hashes[rel],'target_sha256':freeze.sha(snap/rel),'purpose':'disable development helpers/plugins and trim Windows presets only'} for rel in transformed}
        assert not (snap/'.godot').exists()
        env=environment(root);target=Path(env['APPDATA'])/'Godot/export_templates/4.7.2.stable';target.mkdir(parents=True)
        for name in ('windows_debug_x86_64.exe','windows_release_x86_64.exe','windows_debug_x86_64_console.exe','windows_release_x86_64_console.exe'):
            src=checked(TEMPLATES/name);dst=target/name;shutil.copyfile(src,dst)
            assert freeze.sha(src)==freeze.sha(dst)
            m['templates'][name]={'source':str(src),'copy':str(dst),'sha256':freeze.sha(src)}
        save(root,m)
        formal=root/'imported-formal';shutil.copytree(snap,formal)
        assert not (formal/'.godot').exists()
        assert audit.manifest(formal)==m['snapshot_files']
        run(root,m,'fresh-formal-cold-import',[ENGINE,'--headless','--verbose','--rendering-method','gl_compatibility','--editor','--path',formal,'--import','--log-file',root/'evidence/cold-engine.log'],formal)
        source_check(m);save(root,m)
        for role in ('client','server','signaling'):
            source_check(m)
            project=root/('project-'+role)
            if role!='signaling':shutil.copytree(formal,project)
            else:
                # Exact production closure, no rules/data or inherited editor cache.
                srels=freeze.inventory(snap,[],role,cold=True)
                project.mkdir()
                for rel in srels:
                    dst=project/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(snap/rel,dst)
                (project/'project.godot').write_text(freeze.transform_project(snap,role),encoding='utf-8',newline='\n')
            prole=list(audit.manifest(project))
            (project/'export_presets.cfg').write_text(transformed_presets(snap,role,prole),encoding='utf-8',newline='\n')
            runtime=[{'source':DLL,'target':Path(DLL).name}]
            if role!='signaling':
                wr='addons/webrtc_native/lib/libwebrtc_native.windows.template_release.x86_64.dll'
                runtime.append({'source':wr,'target':Path(wr).name})
            declaration={'preset':PRESETS[role],'platform':'windows','role':role,'executable':EXES[role],'runtime_files':runtime}
            (project/contract.NAME).write_text(freeze.contract_text(declaration),encoding='utf-8',newline='\n')
            package=root/'artifacts'/role;package.mkdir(parents=True)
            m['roles'][role]={'project':str(project),'package':str(package),'declaration':declaration,'prepared_files':audit.manifest(project)}
            save(root,m)
            if role=='signaling':
                assert not (project/'.godot').exists()
                run(root,m,'fresh-signaling-cold-import',[ENGINE,'--headless','--verbose','--rendering-method','gl_compatibility','--editor','--path',project,'--import','--log-file',root/'evidence/signaling-import-engine.log'],project)
            run(root,m,'export-'+role,[ENGINE,'--headless','--rendering-method','gl_compatibility','--path',project,'--export-release',PRESETS[role],package/EXES[role],'--log-file',root/'evidence'/('export-'+role+'-engine.log')],project,600)
            if role!='signaling':
                run(root,m,'copy-data-'+role,[sys.executable,'-B',REPO/'tools/copy_data_after_export.py','--project',project,'--output-dir',package],project)
            contract.copy_runtime(project,package,PRESETS[role],'windows',role)
            output=root/'evidence'/('package-'+role+'.json')
            rc=audit.audit(project,package,output,PRESETS[role],'windows',role)
            m['roles'][role]['static_audit']=str(output);m['roles'][role]['static_exit_code']=rc
            m['roles'][role]['package_files']=audit.manifest(package)
            save(root,m)
            if rc:raise RuntimeError('package audit failed: '+role)
            source_check(m);save(root,m)
        m['status']='THREE_ARTIFACTS_STATIC_PASS_RUNTIME_PENDING'
    except BaseException as exc:
        m['status']='STOPPED_WITH_ORIGINAL_EVIDENCE';m['error']=repr(exc);save(root,m)
        raise
    save(root,m);print(json.dumps({'status':m['status'],'manifest':str(root/'manifest.json'),'artifacts':{k:v['package'] for k,v in m['roles'].items()}},ensure_ascii=False))


def complete_unexecuted_signaling(root):
    """Only static preparation was rejected; never rerun an import/export."""
    root=checked(root)
    m=json.loads((root/'manifest.json').read_text(encoding='utf-8'))
    if m['status']!='STOPPED_WITH_ORIGINAL_EVIDENCE' or not m['error'].startswith("ValueError('缺少白名单/依赖文件: .godot/imported/icon.svg-"):
        raise ValueError('resume scope is not the proved static cold-inventory failure')
    if 'signaling' in m['roles'] or any('signaling' in s['name'] for s in m['steps']):
        raise ValueError('refuse any signaling execution retry')
    original=root/'evidence/first-static-preparation-failure.json'
    shutil.copyfile(root/'manifest.json',original)
    m['incidents']=[{'original':str(original),'sha256':freeze.sha(original),'error':m['error'],'resolved':'explicit cold inventory only; no failed Godot execution retried'}]
    try:
        source_check(m)
        snap=root/'source-snapshot'
        if audit.manifest(snap)!=m['snapshot_files']:raise ValueError('snapshot drift')
        role='signaling';project=root/'project-signaling'
        rels=freeze.inventory(snap,[],role,cold=True)
        project.mkdir()
        for rel in rels:
            dst=project/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(snap/rel,dst)
        (project/'project.godot').write_text(freeze.transform_project(snap,role),encoding='utf-8',newline='\n')
        (project/'export_presets.cfg').write_text(transformed_presets(snap,role,rels),encoding='utf-8',newline='\n')
        runtime=[{'source':DLL,'target':Path(DLL).name}]
        declaration={'preset':PRESETS[role],'platform':'windows','role':role,'executable':EXES[role],'runtime_files':runtime}
        (project/contract.NAME).write_text(freeze.contract_text(declaration),encoding='utf-8',newline='\n')
        package=root/'artifacts'/role;package.mkdir(parents=True)
        m['roles'][role]={'project':str(project),'package':str(package),'declaration':declaration,'prepared_files':audit.manifest(project)}
        save(root,m)
        assert not (project/'.godot').exists()
        run(root,m,'fresh-signaling-cold-import',[ENGINE,'--headless','--verbose','--rendering-method','gl_compatibility','--editor','--path',project,'--import','--log-file',root/'evidence/signaling-import-engine.log'],project)
        source_check(m)
        run(root,m,'export-signaling',[ENGINE,'--headless','--rendering-method','gl_compatibility','--path',project,'--export-release',PRESETS[role],package/EXES[role],'--log-file',root/'evidence/export-signaling-engine.log'],project,600)
        contract.copy_runtime(project,package,PRESETS[role],'windows',role)
        output=root/'evidence/package-signaling.json'
        rc=audit.audit(project,package,output,PRESETS[role],'windows',role)
        m['roles'][role].update(static_audit=str(output),static_exit_code=rc,package_files=audit.manifest(package))
        if rc:raise RuntimeError('signaling package audit failed')
        source_check(m)
        m['status']='THREE_ARTIFACTS_STATIC_PASS_RUNTIME_PENDING'
        m.pop('error',None)
    except BaseException as exc:
        m['status']='STOPPED_WITH_ORIGINAL_EVIDENCE';m['error']=repr(exc);save(root,m)
        raise
    save(root,m)
    print(json.dumps({'status':m['status'],'manifest':str(root/'manifest.json'),'artifacts':{k:v['package'] for k,v in m['roles'].items()}},ensure_ascii=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--complete-unexecuted-signaling',action='store_true')
    args=parser.parse_args()
    (complete_unexecuted_signaling if args.complete_unexecuted_signaling else prepare)(args.root)
