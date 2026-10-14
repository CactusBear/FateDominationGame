"""Independent, read-only exported-artifact validation; no source/project overrides.

G05 stable caller API (round56 client-startup owner consumes; do not copy a runner):
    receipt = run_client_startup(root, artifact_manifest, artifact_manifest_sha256,
                                 old_artifact=False)
    validated = validate_client_startup_receipt(receipt, artifact_manifest,
                         artifact_manifest_sha256, require_current=True)
Run only once in a new private E scratch child. Return is the persisted runtime.json
object, including FAIL/native-crash evidence; invalid initial paths/manifest raise.
CLI: python -B -m tools.diagnostics.round53_exported_runtime client-startup
     --root <new-E-scratch-child> --manifest <exact-manifest>
     --manifest-sha256 <sha256> [--old-artifact]
No export, editor, external script/scene, server deployment, or warm retry occurs.
Use only engine flags; default adjacent same-stem PCK loading is mandatory:
--main-pack is NOT allowed (shipped template has path overrides disabled).

Receipt schema = 'round53-client-startup-v1', stage = 'client-startup'.
Only stages['client-startup'] may be PASS/FAIL/NOTRUN. Its exit_code is the real
EXE exit; top-level exit_code is runner success (0/1). runs[0] supplies command,
pid, job_attached_before_resume, active_owned_processes (0 is actual Job query),
exit_code/exit_hex, logs and release proofs. source_bound_run binds manifest SHA,
frozen source_fingerprint, exact EXE/PCK SHA, native_files SHA map, PID and Job0.
source_observations holds pre/post current production closure SHA and exact drift.
The stage logs bind stdout/stderr/engine paths+SHA and checks re-scan full content.
isolated_environment explicitly records APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR.
old_artifact=True is evidence-only: validator(require_current=True) MUST reject it.
nonfinal=True always; even a current startup PASS never covers GUI, two clients,
authentication, save/recovery, worker capability readback, or release approval.
This is not a phase-runformal receipt. Consumer wires just its startup stage.
Consumer pins receipt file SHA before loading and preserves original failures;
validate_client_startup_receipt rechecks package/manifest/log hashes, command and
scope without spawning anything. Reuse old runtime.json; NEVER rerun that EXE.

Only this runner's E root is writable. Each root starts suspended and is assigned
before execution to a private Windows Job. A READY unsaved server is never killed
by closing its Job. Console stop/save receipts precede any resource-release claim.
"""
import argparse
import ctypes
from ctypes import wintypes as w
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import stat
import subprocess
import time
import zipfile

REPO = Path(__file__).resolve().parents[2]
MANIFEST = Path('E:/FateCandidates/round52-current-roles-20261010-sa1/manifest.json')
NATIVE = REPO / 'tools/diagnostics/round53_native_readback.gd'
AUTH = REPO / 'tools/diagnostics/round53_authenticated_client.gd'


def sha(p):
    with Path(p).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def safe(p):
    p = Path(p).absolute()
    for parent in (p, *p.parents):
        if parent.exists() or parent.is_symlink():
            s = parent.lstat()
            if stat.S_ISLNK(s.st_mode) or getattr(s, 'st_file_attributes', 0) & 0x400:
                raise ValueError('reparse/link refused: ' + str(parent))
    if p.resolve().drive.upper() != 'E:':
        raise ValueError('physical E path required: ' + str(p))
    return p


def inventory(root):
    return {p.relative_to(root).as_posix(): sha(safe(p))
            for p in sorted(root.rglob('*')) if p.is_file()}


def startup_identity(document):
    """Bind the exact paired EXE/PCK to round56's frozen source hash map."""
    from tools.release.round56_three_role_freeze import digest_map, fingerprint
    source = digest_map(document['source_files'])
    fp = fingerprint(source)
    row = document['roles']['client']
    if document.get('source_fingerprint') != fp or row.get('source_fingerprint') != fp:
        raise ValueError('CLIENT_STARTUP_SOURCE_BINDING_MISMATCH')
    declaration = row.get('declaration', {})
    exe = declaration.get('executable', '')
    if (declaration.get('role') != 'client' or declaration.get('platform') != 'windows'
            or not exe or Path(exe).name != exe or not exe.endswith('.exe')):
        raise ValueError('CLIENT_STARTUP_EXACT_WINDOWS_EXE_REQUIRED')
    files = digest_map(row['package_files'])
    pck = Path(exe).with_suffix('.pck').name
    if exe not in files or pck not in files:
        raise ValueError('CLIENT_STARTUP_EXACT_EXE_PCK_REQUIRED')
    return {'source_fingerprint': fp, 'executable': exe, 'pck': pck,
            'exe_sha256': files[exe], 'pck_sha256': files[pck]}


def startup_checks(record, logs):
    """Fail closed: exit0/banner alone cannot attest main resource loading."""
    text = '\n'.join(logs.values())
    errors = re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*(?:ERROR|FATAL):|'
                       r'(?:GDExtension|dynamic library|DLL)[^\n]*(?:not found|failed|cannot|could not)',
                       text, re.IGNORECASE | re.MULTILINE)
    normal = (record.get('exit_code') == 0 and record.get('exited') is True
              and record.get('active_owned_processes') == 0
              and not any(record.get(k) for k in ('forced_termination', 'bounded_timeout',
                          'preserved_unsaved_or_unknown_process', 'external_terminal_timeout')))
    releases = record.get('log_resource_release', {})
    return {'normal_exit': normal,
            'private_job_exited': record.get('job_attached_before_resume') is True
                                  and record.get('active_owned_processes') == 0,
            'logs_released': bool(releases) and all(v.get('exclusive_read') is True for v in releases.values()),
            'engine_log_present': bool(logs.get('engine')),
            'engine_banner': 'Godot Engine v' in text,
            'official_main_load_observed': bool(re.search(
                r'Loading resource: res://assets/scenes/main_menu/opening_background\.(?:tscn|scn)|'
                r"^Completed load for: 'res://assets/scenes/main_menu/opening_background\.(?:tscn|scn)'"
                r"(?: remapped 'res://[^'\r\n]+')? at thread -?\d+[ \t]*\r?$",
                text, re.MULTILINE)),
            'no_loader_or_script_errors': errors is None and not record.get('errors')}


class Job:
    def __init__(self):
        self.k = ctypes.WinDLL('kernel32', use_last_error=True)
        for name, args, result in [
            ('CreateJobObjectW',[w.LPVOID,w.LPCWSTR],w.HANDLE),
            ('AssignProcessToJobObject',[w.HANDLE,w.HANDLE],w.BOOL),
            ('SetInformationJobObject',[w.HANDLE,ctypes.c_int,w.LPVOID,w.DWORD],w.BOOL),
            ('QueryInformationJobObject',[w.HANDLE,ctypes.c_int,w.LPVOID,w.DWORD,w.LPVOID],w.BOOL),
            ('TerminateJobObject',[w.HANDLE,w.UINT],w.BOOL),
            ('CloseHandle',[w.HANDLE],w.BOOL),
            ('CreateFileW',[w.LPCWSTR,w.DWORD,w.DWORD,w.LPVOID,w.DWORD,w.DWORD,w.HANDLE],w.HANDLE),
        ]:
            fn = getattr(self.k,name); fn.argtypes = args; fn.restype = result
        self.handle = self.k.CreateJobObjectW(None,None)
        if not self.handle: raise ctypes.WinError(ctypes.get_last_error())
        # No KILL_ON_JOB_CLOSE: an unsaved READY process must survive runner failure.

    def attach(self,p):
        if not self.k.AssignProcessToJobObject(self.handle,int(p._handle)):
            raise ctypes.WinError(ctypes.get_last_error())
        resume = ctypes.WinDLL('ntdll').NtResumeProcess
        resume.argtypes = [w.HANDLE]; resume.restype = ctypes.c_long
        if resume(int(p._handle)) != 0: raise RuntimeError('owned root resume failed')

    def active(self):
        class Accounting(ctypes.Structure):
            _fields_ = [('times',ctypes.c_int64 * 4),('faults',w.DWORD),
                        ('total',w.DWORD),('active',w.DWORD),('terminated',w.DWORD)]
        a = Accounting()
        if not self.k.QueryInformationJobObject(self.handle,1,ctypes.byref(a),ctypes.sizeof(a),None):
            raise ctypes.WinError(ctypes.get_last_error())
        return a.active

    def file_release(self,path):
        h = self.k.CreateFileW(str(path),0x80000000,0,None,3,0x80,None)
        if h == ctypes.c_void_p(-1).value:
            return {'exclusive_read':False,'error':ctypes.get_last_error()}
        self.k.CloseHandle(h)
        return {'exclusive_read':True}

    def close(self):
        self.k.CloseHandle(self.handle)


class Runner:
    def __init__(self,root):
        self.root = safe(root)
        approved = safe('E:/Caches/Hermes/cache/scratch')
        if self.root == approved or not self.root.is_relative_to(approved):
            raise ValueError('explicit private child of approved E scratch required')
        self.root.mkdir(parents=True,exist_ok=True)
        self.mpath = self.root / 'runtime.json'
        self.parent = json.loads(MANIFEST.read_text(encoding='utf-8'))
        self.state = json.loads(self.mpath.read_text()) if self.mpath.exists() else {
            'owner':'round53-independent-exported-runtime','root':self.root.as_posix(),
            'parent_manifest':MANIFEST.as_posix(),'parent_manifest_sha256':sha(MANIFEST),
            'runs':[],'verdict':'NOT_COMPLETE','remaining':['signaling artifact unavailable',
                'new WindowsJobLease/TemporaryCleanupLease not shipped','GUI not this owner',
                'full match save/restore and cross-machine not covered'],
        }
        if self.state.get('owner') != 'round53-independent-exported-runtime' or self.state.get('root') != self.root.as_posix():
            raise ValueError('existing runtime ownership mismatch')
        if self.state['parent_manifest_sha256'] != sha(MANIFEST):
            raise RuntimeError('parent manifest changed')
        self.live = []

    def save(self):
        temporary = self.mpath.with_suffix('.tmp')
        temporary.write_text(json.dumps(self.state,ensure_ascii=False,indent=2),encoding='utf-8')
        temporary.replace(self.mpath)

    def verify(self,label):
        result = {}
        for role in ('client','server'):
            entry = self.parent['roles'][role]
            current = inventory(safe(entry['package']))
            expected = entry['package_files']
            differences = {'added':sorted(set(current)-set(expected)),
                           'removed':sorted(set(expected)-set(current)),
                           'changed':[k for k in expected if k in current and expected[k] != current[k]]}
            result[role] = {'count':len(current),'differences':differences,'files':current}
            if any(differences.values()):
                self.state.setdefault('package_verifications',{})[label] = result; self.save()
                raise RuntimeError('package changed: ' + role)
        self.state.setdefault('package_verifications',{})[label] = result
        self.save()

    def environment(self,label):
        root = self.root / 'users' / label
        env = os.environ.copy()
        for key,sub in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),
                        ('TEMP','tmp'),('TMP','tmp'),('TMPDIR','tmp')]:
            directory = safe(root/sub); directory.mkdir(parents=True,exist_ok=True)
            env[key] = directory.as_posix()
        env['HERMES_VALIDATION_USER_PROBE'] = '1'
        return env

    def command(self,role,args):
        entry = self.parent['roles'][role]
        exe = Path(entry['package']) / entry['declaration']['executable']
        return [str(exe),'--headless','--audio-driver','Dummy',
                '--rendering-method','gl_compatibility',*args]

    def start(self,label,role,args,user_label=None,stdin=None):
        self.verify(label+'-before')
        if any(r['label'] == label for r in self.state['runs']):
            raise RuntimeError('no retry of existing run label: ' + label)
        logs = self.root / 'logs'; logs.mkdir(exist_ok=True)
        out = logs/(label+'.stdout.log'); err = logs/(label+'.stderr.log')
        env = self.environment(user_label or label)
        command = self.command(role,[*args,'--log-file',str(logs/(label+'.engine.log'))])
        # Engine args must precede the single --; preserve the production user argv.
        if '--' in args:
            i = args.index('--')
            command = self.command(role,[*args[:i],'--log-file',str(logs/(label+'.engine.log')),*args[i:]])
        job = Job()
        fout = out.open('wb'); ferr = err.open('wb')
        p = subprocess.Popen(command,cwd=self.root,env=env,stdout=fout,stderr=ferr,
                             stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                             creationflags=0x4)
        record = {'label':label,'role':role,'command':command,'pid':p.pid,
                  'manifest_sha256':self.state['parent_manifest_sha256'],
                  'stdout':str(out),'stderr':str(err),'env_root':env['APPDATA'],
                  'exited':False,'timeout_seconds':180,'job_attached_before_resume':False}
        self.state['runs'].append(record); self.save()
        try:
            job.attach(p)
        except Exception:
            p.kill(); p.wait(timeout=15); job.close(); fout.close(); ferr.close()
            raise
        record['job_attached_before_resume'] = True
        if stdin is not None:
            p.stdin.write(stdin.encode('utf-8')); p.stdin.close()
        item = (p,job,fout,ferr,record,time.monotonic())
        self.live.append(item); self.save()
        return item

    def finish(self,item,allow_terminate=False):
        p,job,fout,ferr,r,start = item
        while p.poll() is None or job.active():
            if time.monotonic()-start > 180:
                r['bounded_timeout'] = True
                ready_text = Path(r['stdout']).read_text(encoding='utf-8',errors='replace')
                server_scope = any(flag in r['command'] for flag in ('--server-gateway','--server-room-worker'))
                if allow_terminate and not server_scope and 'SERVER_GATEWAY_READY' not in ready_text and 'SERVER_ROOM_READY' not in ready_text:
                    job.k.TerminateJobObject(job.handle,125); p.wait(timeout=15)
                    r['forced_termination'] = True
                else:
                    r['preserved_unsaved_or_unknown_process'] = True
                    self.save()
                    raise RuntimeError('180s bound; do not kill READY unsaved/unknown: '+r['label'])
                break
            time.sleep(.03)
        code = p.wait(timeout=15)
        active = job.active()
        fout.close(); ferr.close()
        r.update(exit_code=code,exit_hex=f'0x{code & 0xffffffff:08X}',
                 seconds=round(time.monotonic()-start,6),active_owned_processes=active,
                 exited=active==0,stdout_sha256=sha(r['stdout']),stderr_sha256=sha(r['stderr']))
        r['log_resource_release'] = {str(path):job.file_release(path) for path in (Path(r['stdout']),Path(r['stderr']))}
        text = Path(r['stdout']).read_text(encoding='utf-8',errors='replace')+'\n'+Path(r['stderr']).read_text(encoding='utf-8',errors='replace')
        r['errors'] = [line for line in text.splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',line)]
        job.close(); self.live.remove(item); self.save(); self.verify(r['label']+'-after')
        if code & 0xffffffff == 0xc0000005:
            self.state['verdict'] = 'FIRST_NATIVE_AV_STOP'; self.save()
            raise RuntimeError('first native AV; no continuation')
        return r,text

    def run(self,label,role,args,user_label=None,stdin=None):
        return self.finish(self.start(label,role,args,user_label,stdin),allow_terminate=True)

    def probe(self,role):
        label = role+'-native'
        r,text = self.run(label,role,['--quit-after','2','--script',NATIVE.as_posix(),'--',self.state['parent_manifest_sha256']])
        receipts = [json.loads(line.split(' ',1)[1]) for line in text.splitlines() if line.startswith('ROUND53_NATIVE ')]
        if r['exit_code'] != 0 or r['errors']:
            raise RuntimeError('native ClassDB probe engine failure: '+label)
        if len(receipts)!=1:
            self.state.setdefault('native_readbacks',{})[role] = {'ok':False,'status':'EXTERNAL_SCRIPT_NOT_EXECUTED','reason':'release ignores requested script/main-loop override; exit0 from official scene is not ClassDB proof','run':label}
            self.save()
            return
        if not receipts[0]['ok']:
            raise RuntimeError('native ClassDB registration failure: '+label)
        receipt = receipts[0]
        safe(receipt['user_root'])
        if not Path(receipt['user_root']).is_relative_to(self.root/'users'/label):
            raise RuntimeError('actual user root outside private E root')
        readback = Path(receipt['user_root'])/'round53-native-readback.json'
        if json.loads(readback.read_text()) != receipt: raise RuntimeError('native persisted readback mismatch')
        if receipt['cfg'].get('sha256') != self.parent['formal_configuration']['server_cfg_sha256'] or receipt['cfg'].get('enabled') is not True or receipt['cfg'].get('budget_sec') != 15 or receipt['pool'] != 20:
            raise RuntimeError('formal packaged cfg/pool mismatch')
        self.state.setdefault('native_readbacks',{})[role] = receipt
        self.save()

    def client(self):
        # The first client-native run timed out with no receipt. Never repeat it.
        if not any(r['label']=='client-native' for r in self.state['runs']):
            self.probe('client')
        else:
            self.state.setdefault('native_readbacks',{})['client'] = {'ok':False,'status':'FIRST_PROBE_NO_RECEIPT_NOT_RETRIED'}
        r,text = self.run('client-official-main','client',['--verbose','--fixed-fps','60','--quit-after','180'])
        produced = inventory(self.root/'users'/'client-official-main')
        r['actual_user_files'] = produced
        r['startup_ok'] = r['exit_code']==0 and not r['errors']
        self.state['client_official_main'] = {'ok':r['startup_ok'],'user_files':produced,
            'scene_chain_boundary':'official main entered; no synthetic scene or replacement --script; GUI interaction not covered'}
        self.save()
        if not r['startup_ok']: raise RuntimeError('official client startup failed')

    def ports(self):
        sockets = []
        result = []
        for _ in range(2):
            s = socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
            s.bind(('127.0.0.1',0)); result.append(s.getsockname()[1]); sockets.append(s)
        for s in sockets:s.close()
        # Release -> production bind is a non-atomic handoff, never retried on error.
        return result

    def config(self,label,extension):
        base = self.root/'deployments'/label
        if base.exists():raise RuntimeError('deployment directory already owned by prior attempt; no overwrite/retry')
        base.mkdir(parents=True,exist_ok=False)
        ports = self.ports()
        cfg = {'roles':['game'],'port':ports[0],'bind_address':'127.0.0.1',
            'data_root':safe(self.parent['roles']['server']['package']+'/data').as_posix(),
            'storage_root':(base/'rooms').as_posix(),'identity_registry':'user://round53_players.json',
            'console_dir':(base/'console').as_posix(),'status_file':(base/'status.json').as_posix(),
            'internal_port_base':ports[1],'internal_port_count':1,
            'startup_seconds':30.0,'shutdown_seconds':30.0,'max_rooms':1,'max_clients':4,
            'p2p_signaling':False,'record_matches':True,'authority_host_mode':'dedicated',
            'transaction_log':True,'recovery_key_mismatch':'reject','recovery_inheritance':'host_select',
            'data':{'random_sim_enabled':True,'random_sim_budget_sec':15.0},'room_runtime':{},
            'broadcast_confirmation_capable':False,'temporary_cleanup':{'enabled':False},
            'heartbeat_publication':{}}
        path = base/('deployment.'+extension)
        if extension=='json':
            path.write_text(json.dumps(cfg,ensure_ascii=False),encoding='utf-8')
        else:
            lines = ['[server]']
            for key,value in cfg.items():
                if key=='data':continue
                lines.append(key+' = '+json.dumps(value,ensure_ascii=False))
            lines += ['','[data]','random_sim_enabled = true','random_sim_budget_sec = 15.0']
            path.write_text('\n'.join(lines)+'\n',encoding='utf-8')
        self.state.setdefault('deployments',{})[label] = {'config':str(path),'config_sha256':sha(path),'configuration':cfg,
            'system_udp_selection_non_atomic_handoff':ports}
        self.save()
        return cfg,path

    def console(self,label,cfg,command):
        r,text = self.run(label,'server',['--','--server-console',cfg['console_dir']],user_label='server-'+label.split('-')[0],stdin=command+'\nexit\n')
        responses = [json.loads(line.split(' ',1)[1]) for line in text.splitlines() if line.startswith('CONSOLE_RESULT ')]
        self.state.setdefault('console_receipts',{})[label] = {'command':command,'responses':responses}
        self.save()
        if r['exit_code']!=0 or r['errors'] or len(responses)!=1:raise RuntimeError('console failed: '+label)
        return responses[0]

    def wait_ready(self,item,cfg):
        p,job,_,_,r,start = item
        while time.monotonic()-start<30:
            status=Path(cfg['status_file'])
            if status.exists():
                report=json.loads(status.read_text())
                if report.get('ok') is not True or report.get('pid')!=p.pid:raise RuntimeError('READY status pid mismatch')
                r['ready_readback']=report; self.save();return
            if p.poll() is not None:
                result,text=self.finish(item)
                raise RuntimeError('server before READY: '+str(result['errors'] or result['exit_hex']))
            time.sleep(.03)
        raise RuntimeError('server no READY within unchanged 30s; no retry')

    def server(self):
        # Actual release --help has no script/scene/main-loop override capability.
        # Do not repeat an ignored fixture or substitute console-created room for RSA.
        self.state.setdefault('native_readbacks',{})['server'] = {'ok':False,'status':'BLOCKED_RELEASE_TEMPLATE_NO_SCRIPT_OVERRIDE','methods_readback':None}
        self.state['authenticated_room'] = {'ok':False,'status':'BLOCKED_RELEASE_TEMPLATE_NO_SCRIPT_OVERRIDE','reason':'cannot execute package-external RSA fixture in official release; no source/engine substitution'}
        self.save()
        for format_name in ('cfg','json'):
            cfg,path=self.config(format_name,format_name)
            item=self.start('server-'+format_name+'-deployment','server',['--verbose','--','--server-gateway','--config',path.as_posix()],user_label='server-'+format_name)
            self.wait_ready(item,cfg)
            status=self.console(format_name+'-status',cfg,'status')
            rooms=self.console(format_name+'-rooms',cfg,'rooms')
            if not status.get('ok') or not rooms.get('ok') or rooms.get('result') != []:
                raise RuntimeError('unexpected room/CLI state; preserve unsaved process')
            response=self.console(format_name+'-stop',cfg,'stop')
            if not response.get('ok'):raise RuntimeError('formal stop rejected')
            r,text=self.finish(item)
            if r['exit_code']!=0 or r['errors'] or r['active_owned_processes']!=0:
                raise RuntimeError('deployed server formal stop failed')
            deployment=self.state['deployments'][format_name]
            deployment['actual_ready']=r['ready_readback']
            deployment['stop_readback']={'exit_code':r['exit_code'],'errors':r['errors'],'active_owned_processes':r['active_owned_processes'],'log_resource_release':r['log_resource_release']}
            deployment['room_settings_lobby_save']='NOT_RUN_BLOCKED_EXTERNAL_SCRIPT'
            deployment['actual_user_files']=inventory(self.root/'users'/('server-'+format_name))
            self.save()
        self.state['verdict']='PARTIAL_CLIENT_OFFICIAL_SERVER_JSON_CFG_READY_STOP_NATIVE_RSA_BLOCKED'
        self.save()

    def userroles(self):
        # Existing package-internal production worker opt-in prints actual user root.
        # Invalid manifest is deliberate, bounded, and cannot initialize game rules.
        base=self.root/'user-receipts';base.mkdir(exist_ok=True)
        manifest=base/'not-an-array.json';manifest.write_text('{}',encoding='utf-8')
        for role in ('client','server'):
            report=base/(role+'-validation-rejection.json')
            data=Path(self.parent['roles'][role]['package'])/'data'
            r,text=self.run(role+'-official-user-worker',role,['--','--room-data-validation-worker',data.as_posix(),manifest.as_posix(),report.as_posix()])
            entries=[json.loads(line.split(' ',1)[1]) for line in text.splitlines() if line.startswith('ROOM_VALIDATION_USER_PROBE ')]
            if r['exit_code']!=1 or r['errors'] or len(entries)!=1:
                raise RuntimeError('production user-root role failed: '+role)
            receipt=entries[0];actual=safe(receipt['path'])
            expected=self.root/'users'/(role+'-official-user-worker')
            if not actual.is_relative_to(expected) or receipt['pid']!=r['pid'] or receipt['worker_pool_max_threads']!=20:
                raise RuntimeError('production user-root/pool readback mismatch')
            persisted=actual/('validation-probe-'+str(r['pid'])+'.json')
            if json.loads(persisted.read_text())!=receipt:
                raise RuntimeError('production persisted user readback mismatch')
            rejected=json.loads(report.read_text())
            if rejected.get('errors')!=['批准清单不是数组'] or rejected.get('ok') is not False:
                raise RuntimeError('unexpected validation negative cause')
            self.state.setdefault('production_user_readbacks',{})[role]={'receipt':receipt,'persisted_path':str(persisted),'sha256':sha(persisted),'negative_report':rejected,'boundary':'official built-in validation role only, not native ClassDB, gateway PID, or scene replacement'}
            self.save()

    def inspect(self):
        r,text = self.run('client-release-help','client',['--help'])
        self.state['release_cli_help'] = {'exit_code':r['exit_code'],'text':text,'script_override_status':'observed no auxiliary script execution; compile/config cause not yet asserted'}
        self.save()

    def negative(self):
        base=self.root/'negatives';base.mkdir(exist_ok=True)
        missing=base/'missing.json'
        r,text=self.run('server-missing-json','server',['--','--server-gateway','--config',missing.as_posix()])
        expected_json = ['ERROR: Parse JSON failed. Error at line 0: Unknown error getting token','ERROR: 服务端配置无效，CFG 只接受 server、data 与 relay 段']
        self.state['missing_json_contract']={'exit_code':r['exit_code'],'errors':r['errors'],
            'contract_matched':r['exit_code']==1 and r['errors']==expected_json and 'SERVER_GATEWAY_READY' not in text,
            'note':'exact unreadable JSON rejection: exit1 plus both known diagnostics, no READY'}
        cfg,path=self.config('missing-root','json')
        cfg.pop('data_root');path.write_text(json.dumps(cfg),encoding='utf-8')
        r,text=self.run('server-missing-approved-root','server',['--','--server-gateway','--config',path.as_posix()])
        self.state['missing_root_contract']={'exit_code':r['exit_code'],'errors':r['errors'],
            'contract_matched':r['exit_code']==1 and r['errors']==['ERROR: 必须显式声明 port；游戏服务还需 data_root、storage_root'] and 'SERVER_GATEWAY_READY' not in text,
            'note':'actual declared CLI requires explicit data_root/storage_root, exact exit1 and single reason'}
        self.state['deployments']['missing-root']['configuration']=cfg
        self.state['deployments']['missing-root']['config_sha256']=sha(path)
        self.save()
        if not self.state['missing_root_contract']['contract_matched'] or not self.state['missing_json_contract']['contract_matched']:
            raise RuntimeError('negative rejection does not match declared cause/exit')

    def audit(self):
        self.verify('audit-final')
        checks=[]
        for r in self.state['runs']:
            if r.get('external_terminal_timeout'):
                checks.append({'label':r['label'],'status':'EXTERNAL_TIMEOUT_NO_NORMAL_EXIT_PROOF'})
                continue
            for stream in ('stdout','stderr'):
                if sha(r[stream])!=r[stream+'_sha256']:raise RuntimeError('changed runtime log')
            if r.get('active_owned_processes')!=0 or not r.get('exited'):
                raise RuntimeError('runtime root/Job not exited')
            checks.append({'label':r['label'],'exit':r['exit_code'],'job_active':0})
        cases=[('missing_json_contract','server-missing-json',['ERROR: Parse JSON failed. Error at line 0: Unknown error getting token','ERROR: 服务端配置无效，CFG 只接受 server、data 与 relay 段']),('missing_root_contract','server-missing-approved-root',['ERROR: 必须显式声明 port；游戏服务还需 data_root、storage_root'])]
        for key,label,expected in cases:
            r=next(r for r in self.state['runs'] if r['label']==label)
            raw=Path(r['stdout']).read_text(encoding='utf-8',errors='replace')+'\n'+Path(r['stderr']).read_text(encoding='utf-8',errors='replace')
            ok=r['exit_code']==1 and r['errors']==expected and 'SERVER_GATEWAY_READY' not in raw
            self.state[key]['contract_matched']=ok
            if not ok:raise RuntimeError('exact negative contract mismatch')
        native=self.state['runs'][0]
        native['stdout_sha256']=sha(native['stdout']);native['stderr_sha256']=sha(native['stderr'])
        self.state['tool_hashes']={p.name:sha(p) for p in (Path(__file__),NATIVE,AUTH)}
        self.state['audit']={'actual_runs':len(checks),'runs':checks,'complete_runtime_green':False,'first_probe_normal_exit_not_proven':True,'no_retry_of_first_probe':True}
        self.save()

    def archive(self):
        if self.live:raise RuntimeError('cannot archive/reclaim while owned processes unresolved')
        self.verify('final')
        members=[p for p in self.root.rglob('*') if p.is_file() and p.name not in ('runtime.json','runtime.tmp','runtime-evidence.zip')]
        target=self.root/'runtime-evidence.zip'
        expected={p.relative_to(self.root).as_posix():sha(p) for p in members}
        with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as z:
            for p in members:z.write(p,p.relative_to(self.root).as_posix())
        with zipfile.ZipFile(target) as z:
            if z.testzip() is not None:raise RuntimeError('archive CRC failed')
            actual={name:hashlib.sha256(z.read(name)).hexdigest() for name in z.namelist()}
        if expected!=actual:raise RuntimeError('archive per-file sha mismatch')
        self.state['archive']={'path':str(target),'sha256':sha(target),'files':expected,'verified':True,
            'cleanup':'no candidate copy created; identity/save/user roots retained; no user junction or path edits'}
        self.save()


class ClientStartupRunner(Runner):
    """G05 path adapter only; Runner owns process launch, Job and 180s budget."""
    def __init__(self, root, manifest, manifest_sha256, old_artifact=False):
        self.root = safe(root)
        approved = safe('E:/Caches/Hermes/cache/scratch')
        if self.root == approved or not self.root.is_relative_to(approved):
            raise ValueError('explicit private child of approved E scratch required')
        self.manifest = safe(manifest)
        if not re.fullmatch('[0-9a-f]{64}', manifest_sha256 or '') or sha(self.manifest) != manifest_sha256:
            raise ValueError('CLIENT_STARTUP_MANIFEST_HASH_MISMATCH')
        self.parent = json.loads(self.manifest.read_text(encoding='utf-8'))
        self.identity = startup_identity(self.parent)
        self.source = safe(self.parent['source'])
        self.package = safe(self.parent['roles']['client']['package'])
        if self.root.is_relative_to(self.source) or self.root.is_relative_to(self.package):
            raise ValueError('CLIENT_STARTUP_READONLY_SOURCE_PACKAGE_REQUIRED')
        # Fresh owned directory is the no-retry boundary, including native crashes.
        self.root.mkdir(parents=True, exist_ok=False)
        self.mpath = self.root / 'runtime.json'
        self.live = []
        self.state = {'owner': 'round53-client-startup', 'schema': 'round53-client-startup-v1',
            'root': self.root.as_posix(), 'stage': 'client-startup',
            'artifact_manifest': self.manifest.as_posix(),
            'artifact_manifest_sha256': manifest_sha256, 'parent_manifest_sha256': manifest_sha256,
            'identity': self.identity, 'old_artifact': bool(old_artifact), 'nonfinal': True,
            'classification': 'STARTUP_ONLY_NOT_FINAL', 'runs': [],
            'tool_sha256': sha(__file__),
            'stages': {'client-startup': {'status': 'NOTRUN'}},
            'not_covered': ['GUI', 'two-client-network', 'save', 'recovery', 'cross-machine',
                            'native-ClassDB-method-readback'], 'source_observations': {}}
        self.save()

    def verify(self, label):
        from tools.release.round56_three_role_freeze import validate_artifact, current_inventory
        if sha(self.manifest) != self.state['artifact_manifest_sha256']:
            raise ValueError('CLIENT_STARTUP_MANIFEST_DRIFT')
        validate_artifact('client', self.parent['roles']['client'])
        self.state.setdefault('package_verifications', {})[label] = {
            'manifest_sha256': self.state['artifact_manifest_sha256'],
            'exact_client_package_verified': True, **self.identity}
        current = current_inventory(self.source)
        actual = current['source_files']; frozen = self.parent['source_files']
        differences = {'added': sorted(set(actual) - set(frozen)),
                       'removed': sorted(set(frozen) - set(actual)),
                       'changed': {k: {'frozen': frozen[k], 'current': actual[k]}
                                   for k in frozen if k in actual and frozen[k] != actual[k]}}
        self.state['source_observations'][label] = {
            'current_source_fingerprint': current['source_fingerprint'],
            'frozen_source_fingerprint': self.identity['source_fingerprint'],
            'matches_artifact': actual == frozen, 'differences': differences}
        self.save()
        if actual != frozen and not self.state['old_artifact']:
            raise ValueError('CLIENT_STARTUP_CURRENT_SOURCE_MISMATCH_USE_EXPLICIT_OLD_ARTIFACT')

    def environment(self, label):
        env = Runner.environment(self, label)
        self.state['isolated_environment'] = {key: env[key] for key in
            ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'TMPDIR')}
        self.save()
        return env

    def command(self, role, args):
        if role != 'client' or any(flag in args for flag in
                ('--', '--script', '--path', '--scene', '--main-pack', '--editor',
                 '--server-gateway', '--server-room-worker')):
            raise ValueError('CLIENT_STARTUP_ONLY_OFFICIAL_HEADLESS_MAIN')
        # Official template loads its manifest-verified adjacent same-stem PCK.
        # --main-pack is a forbidden path override in shipped release templates.
        return Runner.command(self, role, args)

    def client_startup(self):
        if self.state['runs'] or self.state.get('startup_attempted'):
            raise RuntimeError('CLIENT_STARTUP_NO_RETRY')
        self.state['startup_attempted'] = True; self.save()
        failure = None
        item = None
        try:
            item = self.start('client-startup', 'client',
                              ['--verbose', '--fixed-fps', '60', '--quit-after', '180'])
            # Unknown descendants/unsaved workers are preserved on timeout, never killed.
            self.finish(item, allow_terminate=False)
        except Exception as error:
            failure = str(error)
        logs = {}; evidence = {}
        record = self.state['runs'][0] if self.state['runs'] else {}
        for stream in ('stdout', 'stderr', 'engine'):
            path = self.root / 'logs' / ('client-startup.' + stream + '.log')
            if path.is_file():
                logs[stream] = path.read_text(encoding='utf-8', errors='replace')
                evidence[stream] = {'path': path.as_posix(), 'sha256': sha(path)}
                if item is not None and record.get('exited'):
                    record.setdefault('log_resource_release', {})[str(path)] = item[1].file_release(path)
        checks = startup_checks(record, logs)
        checks['package_verified_before_and_after'] = all(
            self.state.get('package_verifications', {}).get('client-startup-' + suffix,
                {}).get('exact_client_package_verified') is True for suffix in ('before', 'after'))
        checks['source_identity_recorded_before_and_after'] = all(
            'client-startup-' + suffix in self.state['source_observations'] for suffix in ('before', 'after'))
        checks['runner_completed_without_exception'] = failure is None
        ok = all(checks.values())
        self.state['stages']['client-startup'] = {'status': 'PASS' if ok else 'FAIL',
            'exit_code': record.get('exit_code'), 'checks': checks, 'logs': evidence,
            'first_cause': failure, 'scope': 'official exported client headless startup/normal quit only'}
        self.state['exit_code'] = 0 if ok else 1
        self.state['source_bound_run'] = {
            'artifact_manifest_sha256': self.state['artifact_manifest_sha256'], **self.identity,
            'native_files': self.parent['roles']['client'].get('native_files', {}),
            'pid': record.get('pid'), 'active_owned_processes': record.get('active_owned_processes')}
        if record.get('exit_code', 0) & 0xffffffff >= 0x80000000:
            self.state['classification'] = 'FIRST_NATIVE_CRASH_STOP_NONFINAL'
        self.save()
        if not ok:
            raise RuntimeError(failure or 'CLIENT_STARTUP_CHECKS_FAILED')
        return self.state


def validate_client_startup_receipt(receipt, artifact_manifest, artifact_manifest_sha256,
                                    require_current=False):
    """Read-only PASS consumption; no launch. Old proof cannot enter current gate."""
    from tools.release.round56_three_role_freeze import validate_artifact
    manifest = safe(artifact_manifest)
    if (not re.fullmatch('[0-9a-f]{64}', artifact_manifest_sha256 or '')
            or sha(manifest) != artifact_manifest_sha256):
        raise ValueError('CLIENT_STARTUP_MANIFEST_HASH_MISMATCH')
    document = json.loads(manifest.read_text(encoding='utf-8'))
    identity = startup_identity(document)
    if (receipt.get('schema') != 'round53-client-startup-v1'
            or receipt.get('stage') != 'client-startup'
            or receipt.get('nonfinal') is not True
            or type(receipt.get('old_artifact')) is not bool
            or receipt.get('classification') != 'STARTUP_ONLY_NOT_FINAL'
            or set(receipt.get('stages', {})) != {'client-startup'}):
        raise ValueError('CLIENT_STARTUP_RECEIPT_SCOPE_MISMATCH')
    if (safe(receipt['artifact_manifest']) != manifest
            or receipt.get('artifact_manifest_sha256') != artifact_manifest_sha256
            or receipt.get('identity') != identity):
        raise ValueError('CLIENT_STARTUP_RECEIPT_IDENTITY_MISMATCH')
    root = safe(receipt['root'])
    approved = safe('E:/Caches/Hermes/cache/scratch')
    if root == approved or not root.is_relative_to(approved):
        raise ValueError('CLIENT_STARTUP_RECEIPT_ROOT_MISMATCH')
    stage = receipt['stages']['client-startup']
    runs = receipt.get('runs', [])
    if (stage.get('status') != 'PASS' or stage.get('exit_code') != 0
            or receipt.get('exit_code') != 0 or len(runs) != 1):
        raise ValueError('CLIENT_STARTUP_PASS_PROOF_REQUIRED')
    record = runs[0]
    if (record.get('label') != 'client-startup' or record.get('role') != 'client'
            or not isinstance(record.get('pid'), int) or record['pid'] <= 0
            or record.get('timeout_seconds') != 180):
        raise ValueError('CLIENT_STARTUP_EXACT_RUN_REQUIRED')
    adapter = ClientStartupRunner.__new__(ClientStartupRunner)
    adapter.parent = document; adapter.identity = identity
    adapter.package = safe(document['roles']['client']['package'])
    expected_command = adapter.command('client', ['--verbose', '--fixed-fps', '60',
        '--quit-after', '180', '--log-file', str(root / 'logs/client-startup.engine.log')])
    if (record.get('command') != expected_command
            or safe(record['env_root']) != root / 'users/client-startup/appdata'):
        raise ValueError('CLIENT_STARTUP_COMMAND_OR_USER_ROOT_MISMATCH')
    bound = {'artifact_manifest_sha256': artifact_manifest_sha256, **identity,
             'native_files': document['roles']['client'].get('native_files', {}),
             'pid': record['pid'], 'active_owned_processes': 0}
    if receipt.get('source_bound_run') != bound:
        raise ValueError('CLIENT_STARTUP_SOURCE_BOUND_RUN_MISMATCH')
    expected_env = {key: (root / 'users/client-startup' / sub).as_posix() for key, sub in
        [('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata'),
         ('TEMP', 'tmp'), ('TMP', 'tmp'), ('TMPDIR', 'tmp')]}
    if receipt.get('isolated_environment') != expected_env:
        raise ValueError('CLIENT_STARTUP_ISOLATED_ENVIRONMENT_MISMATCH')
    logs = {}
    if set(stage.get('logs', {})) != {'stdout', 'stderr', 'engine'}:
        raise ValueError('CLIENT_STARTUP_THREE_LOGS_REQUIRED')
    for stream, entry in stage['logs'].items():
        path = safe(entry['path'])
        if path != root / 'logs' / ('client-startup.' + stream + '.log') or sha(path) != entry['sha256']:
            raise ValueError('CLIENT_STARTUP_LOG_HASH_MISMATCH')
        logs[stream] = path.read_text(encoding='utf-8', errors='replace')
    checks = startup_checks(record, logs)
    matches_current = True
    for suffix in ('before', 'after'):
        label = 'client-startup-' + suffix
        package = receipt.get('package_verifications', {}).get(label, {})
        source = receipt.get('source_observations', {}).get(label, {})
        if (package.get('exact_client_package_verified') is not True
                or package.get('manifest_sha256') != artifact_manifest_sha256
                or any(package.get(k) != v for k, v in identity.items())
                or source.get('frozen_source_fingerprint') != identity['source_fingerprint']
                or not re.fullmatch('[0-9a-f]{64}', source.get('current_source_fingerprint', ''))):
            raise ValueError('CLIENT_STARTUP_PRE_POST_IDENTITY_REQUIRED')
        matches_current &= (source.get('matches_artifact') is True
            and source['current_source_fingerprint'] == identity['source_fingerprint']
            and source.get('differences') == {'added': [], 'removed': [], 'changed': {}})
    checks.update(package_verified_before_and_after=True,
                  source_identity_recorded_before_and_after=True,
                  runner_completed_without_exception=stage.get('first_cause') is None)
    if stage.get('checks') != checks or not all(checks.values()):
        raise ValueError('CLIENT_STARTUP_CHECK_READBACK_MISMATCH')
    validate_artifact('client', document['roles']['client'])
    eligible = not receipt['old_artifact'] and matches_current
    if require_current and not eligible:
        raise ValueError('CLIENT_STARTUP_OLD_OR_SOURCE_DRIFT_NONFINAL')
    return {'stage': 'client-startup', 'status': 'PASS', 'nonfinal': True,
            'old_artifact': receipt['old_artifact'], 'eligible_for_current_candidate': eligible,
            'source_fingerprint': identity['source_fingerprint'], 'job_active': 0,
            'artifact_manifest_sha256': artifact_manifest_sha256}


def run_client_startup(root, artifact_manifest, artifact_manifest_sha256, old_artifact=False):
    """Single real EXE attempt. Return persisted PASS/FAIL; never retry after failure."""
    runner = ClientStartupRunner(root, artifact_manifest, artifact_manifest_sha256, old_artifact)
    try:
        runner.client_startup()
    except Exception as error:
        runner.state.setdefault('failures', []).append({'phase': 'client-startup', 'first_cause': str(error)})
        runner.state['exit_code'] = 1
        runner.save()
    return runner.state


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('phase',choices=['client','server','negative','archive','inspect','userroles','audit','client-startup'])
    parser.add_argument('--root',required=True)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--manifest-sha256')
    parser.add_argument('--old-artifact', action='store_true')
    args=parser.parse_args()
    if args.phase == 'client-startup':
        if args.manifest is None or args.manifest_sha256 is None:
            parser.error('client-startup requires --manifest and --manifest-sha256')
        try:
            receipt = run_client_startup(args.root, args.manifest, args.manifest_sha256, args.old_artifact)
        except Exception as error:
            print(json.dumps({'ok': False, 'error': str(error), 'phase': args.phase}, ensure_ascii=False))
            return 1
        print(json.dumps({'ok': receipt['exit_code'] == 0, 'phase': args.phase,
            'manifest': str(Path(args.root) / 'runtime.json'), 'old_artifact': receipt['old_artifact'],
            'nonfinal': True, 'status': receipt['stages']['client-startup']['status']}, ensure_ascii=False))
        return receipt['exit_code']
    if args.manifest is not None or args.manifest_sha256 is not None or args.old_artifact:
        parser.error('explicit manifest/old-artifact options are only for client-startup')
    runner=Runner(args.root)
    try:
        getattr(runner,args.phase)()
    except Exception as e:
        runner.state.setdefault('failures',[]).append({'phase':args.phase,'first_cause':str(e)})
        runner.save()
        print(json.dumps({'ok':False,'error':str(e),'manifest':str(runner.mpath)},ensure_ascii=False))
        return 1
    print(json.dumps({'ok':True,'phase':args.phase,'manifest':str(runner.mpath)},ensure_ascii=False))
    return 0


if __name__=='__main__':
    raise SystemExit(main())
