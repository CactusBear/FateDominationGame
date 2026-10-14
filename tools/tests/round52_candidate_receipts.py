"""Round52 no-new-engine final receipts and owned generated-cache archive."""
from __future__ import annotations
import ctypes, hashlib, json, shutil, sys, zipfile
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import round52_current_role_candidates as candidate

ROOT=Path('E:/FateCandidates/round52-current-roles-20261010-sa1')

def main():
    m=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8'))
    if m['status']!='STOPPED_WITH_ORIGINAL_EVIDENCE':raise ValueError('not the stopped candidate')
    candidate.source_check(m)
    m['native_source_build_contract']={'production_dll_sha256':candidate.freeze.sha(candidate.REPO/candidate.DLL),
      'current_source_not_claimed_as_production_build':True,
      'original_four_classes_source_methods':{
       'FateServerSignals':['enable','protect_worker','disable','take_request'],
       'FateProcessOwner':['available','spawn','state','verify','terminate','release'],
       'FateAtomicFileReplace':['replace_validated_file'],
       'FateCollectionIdentity':['is_supported','candidate_key']},
      'current_candidate_runtime_registration_readback':'NOT_RUN_AFTER_SIGNALING_COLD_FAILURE',
      'prior_round49_runtime':'23/23 original DLL, separate previous snapshot, not this candidate',
      'unreleased_exact_cpp_apis':{'WindowsJobLease':['assign','observe','release'],
           'TemporaryCleanupLease':['acquire','verify_and_delete'],'free_function':['delete_approved_temporary']},
      'source_hashes':{p:candidate.freeze.sha(candidate.REPO/p) for p in (
        'addons/fate_server_signals/SConstruct','addons/fate_server_signals/src/server_signals.cpp',
        'addons/fate_server_signals/src/process_owner_binding.cpp','addons/fate_server_signals/src/atomic_file_replace_binding.cpp',
        'addons/fate_server_signals/src/collection_identity_binding.cpp','addons/fate_server_signals/src/process_tree_owner_core.cpp',
        'addons/fate_server_signals/src/process_tree_owner_core.hpp','addons/fate_server_signals/src/temporary_cleanup_core.cpp',
        'addons/fate_server_signals/src/temporary_cleanup_core.hpp')},
      'packaging_cpp_source_included':False}
    m['formal_configuration']={'simulation_enabled':True,'simulation_budget_sec':15.0,'worker_pool_max_threads':20,
        'project_sha256':candidate.freeze.sha(ROOT/'source-snapshot/project.godot'),
        'server_cfg_sha256':candidate.freeze.sha(ROOT/'source-snapshot/assets/config/server.cfg'),
        'runtime_readback':'NOT_RUN_AFTER_SIGNALING_COLD_FAILURE'}
    cfg=(ROOT/'source-snapshot/assets/config/server.cfg').read_text(encoding='utf-8')
    project=(ROOT/'source-snapshot/project.godot').read_text(encoding='utf-8')
    assert 'random_sim_budget_sec = 15.0' in cfg and 'random_sim_enabled = true' in cfg
    assert 'worker_pool/max_threads=20' in project
    m['available_artifacts']={}
    for role in ('client','server'):
        info=m['roles'][role];package=Path(info['package'])
        files=candidate.audit.manifest(package)
        assert files==info['package_files']
        result=json.loads(Path(info['static_audit']).read_text(encoding='utf-8'))
        assert result['status']=='STATIC_PASS_RUNTIME_PENDING' and not result['blockers']
        cfg_name='res://assets/config/server.cfg'
        assert result['pck_index']['files'][cfg_name]['sha256']==m['formal_configuration']['server_cfg_sha256']
        assert not any(p.endswith(('.cpp','.hpp','.obj','.lib','.exp','.TMP')) for p in files)
        assert not any(name.startswith(('res://tests/','res://reports/','res://tools/','res://data/')) for name in result['pck_index']['files'])
        m['available_artifacts'][role]={'absolute_path':str(package),'executable_sha256':files[candidate.EXES[role]],
            'pck_sha256':files[Path(candidate.EXES[role]).with_suffix('.pck').name],
            'exact_package_files':files,'data_file_count':sum(p.startswith('data/') for p in files),
            'config_pck_matches_original':True,'status':'STATIC_PASS_RUNTIME_NOT_RUN'}
    m['not_available_artifact']={'role':'signaling','package':m['roles']['signaling']['package'],
        'reason':'FIRST_FRESH_ROLE_IMPORT_NATIVE_AV_NO_EXPORT_NO_RETRY','error_exit_hex':'0xC0000005'}
    m['runtime_missing_config_contract']={'signaling_current_source_exit':2,'requested_exit':1,
        'runtime_executed':False,'source':'scripts/net/server/server_bootstrap.gd:_signal_fail',
        'status':'SOURCE_CONTRACT_MISMATCH_NOT_REPAIRED_OUTSIDE_WRITE_SCOPE'}
    m['runtime_user_paths']={'configured_environment':candidate.environment(ROOT),
       'actual_runtime_user_receipt':'NOT_RUN_AFTER_SIGNALING_COLD_FAILURE',
       'no_claim_environment_equals_actual_user_dir':True}
    # Restrict readable environment record to path variables, never retain secrets.
    m['runtime_user_paths']['configured_environment']={k:v for k,v in m['runtime_user_paths']['configured_environment'].items() if k in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR')}
    k=ctypes.WinDLL('kernel32',use_last_error=True)
    k.OpenProcess.argtypes=[ctypes.c_uint32,ctypes.c_int,ctypes.c_uint32];k.OpenProcess.restype=ctypes.c_void_p
    k.GetExitCodeProcess.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_uint32)];k.GetExitCodeProcess.restype=ctypes.c_int
    k.CloseHandle.argtypes=[ctypes.c_void_p]
    post=[]
    for row in m['steps']:
        handle=k.OpenProcess(0x1000,False,row['pid'])
        if handle:
            code=ctypes.c_uint32();ok=bool(k.GetExitCodeProcess(handle,ctypes.byref(code)));k.CloseHandle(handle)
            post.append({'pid':row['pid'],'query_ok':ok,'current_pid_exit_code':code.value,'currently_alive':not ok or code.value==259})
        else:post.append({'pid':row['pid'],'open_error':ctypes.get_last_error(),'currently_alive':False})
    m['owned_pid_postcheck']=post
    if any(row['currently_alive'] for row in post):
        m['cleanup']={'status':'RETAINED_AMBIGUOUS_PID_NO_DELETE'};candidate.save(ROOT,m);return
    generated=[]
    for name in ('imported-formal','project-client','project-server','project-signaling'):
        folder=ROOT/name/'.godot'
        if folder.exists():
            for path in folder.rglob('*'):
                candidate.checked(path)
                if path.is_file():generated.append(path)
    for name in ('imported-formal','project-client','project-server','project-signaling'):
        for path in (ROOT/name).rglob('~*.dll'):
            candidate.checked(path);generated.append(path)
    records=[{'path':str(path),'relative':path.relative_to(ROOT).as_posix(),'sha256':candidate.freeze.sha(path),'bytes':path.stat().st_size} for path in generated]
    archive=ROOT/'evidence/owned-generated-cache-originals.zip'
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=1) as z:
        for path,row in zip(generated,records):z.write(path,row['relative'])
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        assert set(z.namelist())=={r['relative'] for r in records}
        for row in records:assert hashlib.sha256(z.read(row['relative'])).hexdigest()==row['sha256']
    for path,row in zip(generated,records):
        assert candidate.freeze.sha(path)==row['sha256']
    for name in ('imported-formal','project-client','project-server','project-signaling'):
        folder=ROOT/name/'.godot'
        if folder.exists():shutil.rmtree(folder)
        assert not folder.exists()
    for path,row in zip(generated,records):
        if not '/.godot/' in row['relative']:
            if path.exists():path.unlink()
        assert not path.exists()
    m['cleanup']={'status':'OWNED_GENERATED_CACHE_ARCHIVED_VERIFIED_REMOVED','archive':str(archive),
        'archive_sha256':candidate.freeze.sha(archive),'removed_files':records,
        'removed_file_count':len(records),'removed_bytes':sum(r['bytes'] for r in records),
        'kept':['source-snapshot','role frozen source','all original failure logs','all exported client/server packages','user paths and templates for later inspection'],
        'no_user_or_other_owner_artifacts_touched':True}
    candidate.source_check(m)
    m['status']='TWO_CURRENT_ROLE_ARTIFACTS_AVAILABLE_SIGNALING_COLD_FAILED_STOPPED'
    candidate.save(ROOT,m)
    print(json.dumps({'status':m['status'],'manifest':str(ROOT/'manifest.json'),'manifest_sha256':candidate.freeze.sha(ROOT/'manifest.json'),
        'artifacts':{k:v['absolute_path'] for k,v in m['available_artifacts'].items()},'cleanup':{k:v for k,v in m['cleanup'].items() if k!='removed_files'}},ensure_ascii=False))

if __name__=='__main__':main()
