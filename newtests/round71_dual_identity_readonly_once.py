# 旧产物非最终验收：仅读 launcher，以 E 盘外置身份目录运行一次双 headless 客户端，记录 SHA 与自有 Job 的退出回执。

import os,sys,time,json,ctypes,subprocess,hashlib
from pathlib import Path
from ctypes import wintypes as w
base=Path('E:/Caches/Hermes/cache/scratch/round71-dual-identity-once-'+str(os.getpid()))
base.mkdir(exist_ok=False)
k=ctypes.WinDLL('kernel32',use_last_error=True)
k.CreateJobObjectW.argtypes=[ctypes.c_void_p,w.LPCWSTR];k.CreateJobObjectW.restype=w.HANDLE
k.AssignProcessToJobObject.argtypes=[w.HANDLE,w.HANDLE];k.AssignProcessToJobObject.restype=w.BOOL
k.QueryInformationJobObject.argtypes=[w.HANDLE,ctypes.c_int,ctypes.c_void_p,w.DWORD,ctypes.c_void_p];k.QueryInformationJobObject.restype=w.BOOL
k.SetInformationJobObject.argtypes=[w.HANDLE,ctypes.c_int,ctypes.c_void_p,w.DWORD];k.SetInformationJobObject.restype=w.BOOL
k.TerminateJobObject.argtypes=[w.HANDLE,w.UINT];k.TerminateJobObject.restype=w.BOOL
k.CloseHandle.argtypes=[w.HANDLE];k.CloseHandle.restype=w.BOOL
class BASIC(ctypes.Structure):
 _fields_=[('a',ctypes.c_longlong),('b',ctypes.c_longlong),('flags',w.DWORD),('min',ctypes.c_size_t),('max',ctypes.c_size_t),('active',w.DWORD),('affinity',ctypes.c_size_t),('priority',w.DWORD),('scheduling',w.DWORD)]
class IO(ctypes.Structure):
 _fields_=[(n,ctypes.c_ulonglong) for n in ['read','write','other','rb','wb','ob']]
class EXT(ctypes.Structure):
 _fields_=[('basic',BASIC),('io',IO),('pm',ctypes.c_size_t),('jm',ctypes.c_size_t),('pp',ctypes.c_size_t),('pj',ctypes.c_size_t)]
class ACCT(ctypes.Structure):
 _fields_=[(n,ctypes.c_longlong) for n in ['ut','kt','pu','pk']]+[(n,w.DWORD) for n in ['fault','total','active','terminated']]
class THREAD(ctypes.Structure):
 _fields_=[('size',w.DWORD),('usage',w.DWORD),('tid',w.DWORD),('pid',w.DWORD),('base',w.LONG),('delta',w.LONG),('flags',w.DWORD)]
k.CreateToolhelp32Snapshot.argtypes=[w.DWORD,w.DWORD];k.CreateToolhelp32Snapshot.restype=w.HANDLE
k.Thread32First.argtypes=[w.HANDLE,ctypes.POINTER(THREAD)];k.Thread32Next.argtypes=k.Thread32First.argtypes
k.OpenThread.argtypes=[w.DWORD,w.BOOL,w.DWORD];k.OpenThread.restype=w.HANDLE
k.ResumeThread.argtypes=[w.HANDLE];k.ResumeThread.restype=w.DWORD
job=k.CreateJobObjectW(None,None); assert job
limits=EXT();limits.basic.flags=0x2000
assert k.SetInformationJobObject(job,9,ctypes.byref(limits),ctypes.sizeof(limits)),ctypes.get_last_error()
def acct():
 a=ACCT();assert k.QueryInformationJobObject(job,1,ctypes.byref(a),ctypes.sizeof(a),None)
 return {'total':a.total,'active':a.active,'terminated':a.terminated}
def pids():
 b=ctypes.create_string_buffer(8192)
 assert k.QueryInformationJobObject(job,3,b,len(b),None)
 count=int.from_bytes(b.raw[4:8],'little'); size=ctypes.sizeof(ctypes.c_size_t)
 return [int.from_bytes(b.raw[8+i*size:8+(i+1)*size],'little') for i in range(count)]
def resume(pid):
 snap=k.CreateToolhelp32Snapshot(4,0);t=THREAD();t.size=ctypes.sizeof(t);ok=k.Thread32First(snap,ctypes.byref(t));found=False
 while ok:
  if t.pid==pid:
   h=k.OpenThread(2,False,t.tid);assert h
   assert k.ResumeThread(h)!=0xffffffff; k.CloseHandle(h);found=True
  ok=k.Thread32Next(snap,ctypes.byref(t))
 k.CloseHandle(snap);assert found
k.OpenProcess.argtypes=[w.DWORD,w.BOOL,w.DWORD];k.OpenProcess.restype=w.HANDLE
k.GetExitCodeProcess.argtypes=[w.HANDLE,ctypes.POINTER(w.DWORD)];k.GetExitCodeProcess.restype=w.BOOL
observed={}
roles={}; processes=[]; outfile=base/'evidence.json'
r={'old_artifact':True,'nonfinal':True,'window_mode':False,'headless':True,'attempts_per_check':1,'watchdog_seconds':180,'base':str(base),'protected_pid':28100,'roles':roles,'snapshots':[]}
def snap(label):
 d={'label':label,'elapsed':round(time.monotonic()-start,3),'job':acct(),'job_pids':pids(),'roles':{}}
 assert 28100 not in d['job_pids']
 for pid in d['job_pids']:
  if pid not in observed:
   handle=k.OpenProcess(0x1000|0x100000,False,pid)
   if handle: observed[pid]=handle
 for role,v in roles.items():
  root=Path(v['APPDATA'])/'FateDomination'; ids=root/'net_identity'
  files=[]
  if ids.exists():
   for f in sorted(ids.rglob('*')):
    if f.is_file():
     with f.open('rb') as stream: sha=hashlib.file_digest(stream,'sha256').hexdigest()
     files.append({'path':str(f),'name':f.name,'sha256':sha})
  d['roles'][role]={'APPDATA':v['APPDATA'],'LOCALAPPDATA':v['LOCALAPPDATA'],'user_dir':str(root),'identity_dir':str(ids),'user_dir_exists':root.exists(),'identity_dir_exists':ids.exists(),'identity_file_count':len(files),'identity_files':files,'runtime_files':{var:[{'path':str(f),'name':f.name,'size':f.stat().st_size} for f in sorted(Path(v[var]).rglob('*')) if f.is_file()] for var in ['APPDATA','LOCALAPPDATA']}}
 r['snapshots'].append(d);outfile.write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8');return d
launcher=Path('E:/Caches/Hermes/cache/scratch/round71-human-test-candidate-validation-v3/client/START-CLIENT.cmd')
def sha_file(path):
 with Path(path).open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()
def census():
 command='Get-CimInstance Win32_Process | Where-Object { $_.Name -match "Godot|FateDomination" -or $_.ProcessId -eq 28100 } | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath | ConvertTo-Json -Depth 3'
 result=subprocess.run(['powershell.exe','-NoProfile','-Command',command],capture_output=True,text=True,timeout=15)
 return {'exit_code':result.returncode,'processes':json.loads(result.stdout) if result.stdout.strip() else [],'stderr':result.stderr}
tracked=[launcher,launcher.parent/'FateDomination.exe',Path('E:/FateCandidates/round71-build-only-4f7fb4194e19acdf-91306a82/artifacts/client/FateDomination.exe')]
r['artifact_hashes_before']={str(path):sha_file(path) for path in tracked}
r['launcher_lines']=[{'line':i+1,'text':line} for i,line in enumerate(launcher.read_text(encoding='utf-8').splitlines())]
r['process_census_before']=census()
r['scratch_physical']=str(base.resolve())
assert base.resolve().drive.upper()=='E:'
start=time.monotonic()
print('EVIDENCE_BASE='+str(base),flush=True)
try:
 for role in ['host','guest']:
  env=os.environ.copy()
  for var,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('TEMP','temp'),('TMP','temp'),('TMPDIR','temp')]:
   directory=base/'test-users'/role/sub;directory.mkdir(parents=True,exist_ok=True);env[var]=str(directory)
  env['GODOT_DISABLE_CRASH_HANDLER']='1'
  log=base/(role+'.engine.log'); out=base/(role+'.stdout.log')
  cmd='"'+str(launcher)+'" --headless --audio-driver Dummy --rendering-method gl_compatibility --max-fps 10 --quit-after 180 --log-file "'+str(log)+'"'
  v={'APPDATA':env['APPDATA'],'LOCALAPPDATA':env['LOCALAPPDATA'],'TEMP':env['TEMP'],'TMP':env['TMP'],'TMPDIR':env['TMPDIR'],'cmd':cmd,'engine_log':str(log),'stdout_log':str(out)};roles[role]=v
  snap(role+'_before_launch')
  stream=out.open('wb');nativecmd='"'+os.environ.get('COMSPEC','C:/Windows/System32/cmd.exe')+'" /d /s /c "'+cmd+'"';v['native_command']=nativecmd;p=subprocess.Popen(nativecmd,cwd=str(base),env=env,stdout=stream,stderr=subprocess.STDOUT,creationflags=0x4|0x08000000)
  processes.append((role,p,stream));v['launcher_pid']=p.pid
  assert p.pid!=28100
  assert k.AssignProcessToJobObject(job,w.HANDLE(int(p._handle))),ctypes.get_last_error()
  resume(p.pid);print('LAUNCHED',role,'pid',p.pid,'CMD',cmd,flush=True)
  time.sleep(1);print('SNAPSHOT',json.dumps(snap(role+'_started'),ensure_ascii=False),flush=True)
  if role=='guest': r['process_census_coexisting']=census()
 while any(p.poll() is None for _,p,_ in processes) or acct()['active']:
  if time.monotonic()-start>180:
   r['watchdog_fired']=True;assert 28100 not in pids();k.TerminateJobObject(job,124);break
  time.sleep(.5);snap('coexist_or_exit')
 for role,p,stream in processes:
  roles[role]['launcher_exit_code']=p.wait(timeout=10);stream.close()
 time.sleep(.5)
 r['final']=snap('after_normal_exit');r['Job0']=acct()['active']==0;r['watchdog_fired']=r.get('watchdog_fired',False)
 for role,v in roles.items():
  lines=[]
  for path in [Path(v['engine_log']),Path(v['stdout_log'])]:
   if path.exists():
    text=path.read_text(encoding='utf-8',errors='replace').splitlines()
    lines.extend([{'file':str(path),'line':i+1,'text':s} for i,s in enumerate(text) if 'SCRIPT ERROR' in s or 'Parse Error' in s or s.startswith('ERROR:') or 'Godot Engine' in s])
  v['log_key_lines']=lines
  v['script_error_count']=sum('SCRIPT ERROR' in item['text'] for item in lines)
  v['parse_error_count']=sum('Parse Error' in item['text'] for item in lines)
  v['engine_error_count']=sum(item['text'].startswith('ERROR:') for item in lines)
 r['process_census_after']=census()
 r['artifact_hashes_after']={str(path):sha_file(path) for path in tracked}
 r['artifact_hashes_unchanged']=r['artifact_hashes_before']==r['artifact_hashes_after']
 r['job_accounting_final']=acct();r['observed_process_exit_codes']=[]
 for pid,handle in observed.items():
  code=w.DWORD();ok=k.GetExitCodeProcess(handle,ctypes.byref(code));r['observed_process_exit_codes'].append({'pid':pid,'exit_code':code.value if ok else None});k.CloseHandle(handle)
 outfile.write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8');print('FINAL',json.dumps({key:r[key] for key in ['old_artifact','nonfinal','Job0','watchdog_fired','job_accounting_final','observed_process_exit_codes','roles','final']},ensure_ascii=False),flush=True)
finally:
 if acct()['active']:
  assert 28100 not in pids();k.TerminateJobObject(job,125)
 k.CloseHandle(job)
