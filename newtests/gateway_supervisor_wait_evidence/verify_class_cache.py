import os, json, re, hashlib, importlib.util, shutil
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('triage',HERE/'run_supervisor_triage.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
def check(project):
    archive=project/'newtests/join_shape_session_wiring_evidence'
    assert not archive.exists(), 'unexpected archive in bounded freeze'
    cache=project/'.godot/global_script_class_cache.cfg'
    text=cache.read_text(encoding='utf-8')
    blocks=[b for b in re.findall(r'\{[^{}]*\}',text,re.S) if re.search(r'"class":\s*&?"MatchLobbySession"',b)]
    assert len(blocks)==1 and '"path": "res://scripts/net/session/lobby_session.gd"' in blocks[0]
    return {'project':str(project),'archive_exists':False,'cleanup':'no archive to delete/ignore; bounded dependency freeze excludes it','cache_sha256':hashlib.sha256(cache.read_bytes()).hexdigest(),'MatchLobbySession_entries':blocks}
def main():
    roots=[m.SOURCE]+[m.ROOT/x/'project' for x in ['diagnostic','fixed','paced-fixed','paced-fixed-v2','clean']]
    result={'prior_projects':[check(p) for p in roots]}
    scope,project,evidence,fixture=m.prepare('cache-verified',False)
    env=os.environ.copy()
    for k in ['APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR']:
        p=scope/'runtime'/k.lower(); p.mkdir(parents=True,exist_ok=True); env[k]=str(p)
    records=[]
    cmd=[str(m.ENGINE),'--headless','--fixed-fps','60','--path',str(project),'--import']
    out,err,code=m.runner.execute(cmd,env,scope,evidence,'import',{'seconds':1200,'bytes':8*1024**3,'min_free':0},records)
    result['import']={'command':cmd,'exit':code,'engine_errors':sum(bool(re.match(r'^\s*(?:SCRIPT\s+)?ERROR:',x)) for x in (out+'\n'+err).splitlines()),'job_records':records}
    result['after_import']=check(project)
    (evidence/'class-cache-verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    assert code==0 and result['import']['engine_errors']==0
    result['scene']=m.execute(scope,project,evidence,fixture,'scene')
    result['after_scene']=check(project)
    (evidence/'class-cache-verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    for name in ['import.stdout.log','import.stderr.log','scene.stdout.log','scene.stderr.log','scene.receipt.json','class-cache-verification.json']:
        target=HERE/('cache-verified.'+name)
        assert not target.exists(); shutil.copy2(evidence/name,target)
    print(json.dumps(result,ensure_ascii=False),flush=True)
if __name__=='__main__': main()
