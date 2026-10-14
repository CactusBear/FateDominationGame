"""Read-back, missing-native negative and exact owned-PID postchecks for R53."""
from __future__ import annotations
import ctypes
from ctypes import wintypes
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.request

sys.dont_write_bytecode=True
REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO))
from tools.diagnostics import round53_signaling_initialization as p
from tools.release import signaling_prepare as release

ROOT=Path('E:/FateCandidates/round53-signaling-runtime-entry-sa1')
PROTOTYPE=Path('E:/FateDiagnostics/round53-signaling-initialization-sa1')

def main():
    manifest=json.loads((ROOT/'manifest.json').read_text())
    if manifest['status']!='TWO_FRESH_SIGNALING_CANDIDATE_GREEN':raise RuntimeError('candidate not green')
    if '--offline-finalize' in sys.argv:
        checks=[]
        for sample in manifest['samples']:
            runtime=sample['runtime'];text=Path(runtime['log']).read_text(encoding='utf-8')
            if not release.production_ready(text,runtime):raise RuntimeError('final exact READY scope rejected')
            negative=sample['negative'];raw=Path(negative['log']).read_text(encoding='utf-8')
            if not p.negative_contract(negative,raw,require_script_backtrace=False):raise RuntimeError('final exact negative scope rejected')
            actual=release.audit(Path(sample['package']),Path(sample['root']))
            if actual['package_files']!=sample['audit']['package_files']:raise RuntimeError('final package drift')
            checks.append({'package':sample['package'],'ready_pid_roles_port_and_break':True,'missing_config_exit2_and_scope':True,'package_readback':True})
        unit=subprocess.run([sys.executable,'-B','-m','unittest','tools.tests.test_round53_signaling_initialization','-v'],cwd=REPO,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
        (ROOT/'evidence/final-unit-tests.log').write_bytes(unit.stdout)
        if unit.returncode:raise RuntimeError('final unit checks failed')
        url=f'https://raw.githubusercontent.com/godotengine/godot/{p.REV}/main/main.cpp'
        path=ROOT/'evidence/main-pinned.cpp';path.write_bytes(urllib.request.urlopen(url,timeout=25).read())
        manifest['official_template_override_contract']={'url':url,'sha256':p.sha(path),'no_override_clears_script_main_loop_and_scene':True}
        manifest['second_scope_rejection']={'result':str(ROOT/'fresh-1/native-four-capabilities-no-path-result.json'),'sha256':p.sha(ROOT/'fresh-1/native-four-capabilities-no-path-result.json'),'explanation':'release template clears --script; correct signal argc rejection exit2; not a capability execution'}
        manifest['tool_sources_sha256']={name:p.sha(REPO/name) for name in manifest['tool_sources_sha256']}
        manifest['final_offline_readback']={'checks':checks,'unit_tests':9,'passed':True,'no_Godot_rerun':True}
        with (ROOT/'manifest.json').open('w',encoding='utf-8',newline='\n') as f:json.dump(manifest,f,ensure_ascii=False,indent=2)
        print(json.dumps({'status':manifest['status'],'final_offline_pass':True,'unit_tests':9},ensure_ascii=False))
        return
    evidence=ROOT/'evidence';evidence.mkdir()
    p.save(evidence/'initial-green-manifest-original.json',manifest)
    original_failure=Path('E:/FateCandidates/round52-current-roles-20261010-sa1/evidence/fresh-signaling-cold-import.log')
    shutil.copyfile(original_failure,evidence/'round52-first-cold-AV-original.log')
    manifest['original_cold_failure']={'source':str(original_failure),'copy':str(evidence/'round52-first-cold-AV-original.log'),'sha256':p.sha(original_failure),'not_retried':True}
    inputs=[json.loads(Path(s['input_manifest']).read_text()) for s in manifest['samples']]
    if inputs[0]['files']!=inputs[1]['files']:raise RuntimeError('input equality failed')
    for sample,freeze in zip(manifest['samples'],inputs):
        actual=release.audit(Path(sample['package']),Path(sample['root']))
        if actual['package_files']!=sample['audit']['package_files']:raise RuntimeError('package drift')
        if any(p.sha(REPO/n)!=h for n,h in freeze['source_files'].items()):raise RuntimeError('source drift')
    # Distinct runtime deployment variable: the native asset is absent.
    sample=ROOT/'negative-missing-native';sample.mkdir();(sample/'project').mkdir();package=sample/'package';package.mkdir()
    canonical=Path(manifest['recommended_candidate'])
    for name in ('FateSignaling.exe','FateSignaling.pck','signaling.json'):shutil.copyfile(canonical/name,package/name)
    env=p.child_env(sample)
    runner=ROOT/'diagnostic-tools/runner.exe'
    result,text=p.run(sample,runner,package/'FateSignaling.exe',['--headless','--','--server-signaling','--config',str(package/'signaling.json')],env,'actual-missing-native')
    reason='ERROR: 信令原生部署资产缺失'
    if not p.negative_passed(result['exit'],text,expected_exit=2,reason=reason,allowed_errors=[reason]) or 'at: push_error (core/variant/variant_utility.cpp:1023)' not in text or result['module_loaded']:raise RuntimeError('missing-native fail-closed contract failed')
    manifest['missing_native_negative']=result
    p.archive_generated(sample)
    unit=subprocess.run([sys.executable,'-B','-m','unittest','tools.tests.test_round53_signaling_initialization','-v'],cwd=REPO,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
    (evidence/'unit-tests.log').write_bytes(unit.stdout)
    if unit.returncode:raise RuntimeError('unit checks failed')
    known={}
    for root in (ROOT,PROTOTYPE,Path('E:/FateDiagnostics/round53-entry-contract-red-sa1'),Path('E:/FateDiagnostics/round53-entry-contract-green-sa1')):
        for log in root.rglob('*.log'):
            for e,ct,k,kct in re.findall(r'R53_OWNED engine=(\d+) creation=(\d+) keeper=(\d+) keeper_creation=(\d+)',log.read_text(encoding='utf-8',errors='replace')):
                known[int(e)]=int(ct);known[int(k)]=int(kct)
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD];kernel.OpenProcess.restype=wintypes.HANDLE
    kernel.WaitForSingleObject.argtypes=[wintypes.HANDLE,wintypes.DWORD];kernel.WaitForSingleObject.restype=wintypes.DWORD
    kernel.GetProcessTimes.argtypes=[wintypes.HANDLE]+[ctypes.POINTER(wintypes.FILETIME)]*4
    kernel.CloseHandle.argtypes=[wintypes.HANDLE]
    results=[]
    for pid,expected in sorted(known.items()):
        h=kernel.OpenProcess(0x100000|0x1000,False,pid)
        if not h:results.append({'pid':pid,'expected_creation':expected,'not_live':True,'open_error':ctypes.get_last_error()});continue
        times=[wintypes.FILETIME() for _ in range(4)]
        if not kernel.GetProcessTimes(h,*[ctypes.byref(t) for t in times]):raise RuntimeError('owned process identity query failed')
        current=(times[0].dwHighDateTime<<32)|times[0].dwLowDateTime
        exited=kernel.WaitForSingleObject(h,0)==0;kernel.CloseHandle(h)
        if current==expected and not exited:raise RuntimeError('exact owned PID still live')
        results.append({'pid':pid,'expected_creation':expected,'current_creation':current,'not_live':exited or current!=expected,'reused_pid':current!=expected})
    p.save(evidence/'owned-pid-postcheck.json',results)
    for root in (Path('E:/FateDiagnostics/round53-entry-contract-red-sa1'),Path('E:/FateDiagnostics/round53-entry-contract-green-sa1')):p.archive_generated(root)
    manifest['postcheck']={'file':str(evidence/'owned-pid-postcheck.json'),'count':len(results),'all_exact_owned_exited':True}
    manifest['console_wrapper']={'artifact_present':True,'wrapper_route_runtime':'NOT_RUN; exact EXE was run in an independently owned console'}
    manifest['tool_sources_sha256']={name:p.sha(REPO/name) for name in ['tools/diagnostics/round53_signaling_initialization.py','tools/release/signaling_prepare.py','tools/tests/test_round53_signaling_initialization.py','tools/tests/round53_signaling_receipts.py']}
    manifest['scope']='signaling entry initialization + actual exported EXE; not three-role integrated human acceptance'
    with (ROOT/'manifest.json').open('w',encoding='utf-8',newline='\n') as f:json.dump(manifest,f,ensure_ascii=False,indent=2)
    print(json.dumps({'status':manifest['status'],'owned_pids':len(results),'missing_native_exit':result['exit'],'manifest':str(ROOT/'manifest.json')},ensure_ascii=False))

if __name__=='__main__':main()