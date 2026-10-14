"""Run only generated ordinary UDP / bare Godot ENet fixtures in fresh E: Jobs.
No game project runs, attach, recovery, saved records or application payload reads.
"""
from __future__ import annotations
import sys
sys.dont_write_bytecode = True
import argparse, hashlib, importlib.util, json, os, re, shutil, socket, time, uuid
from pathlib import Path
PROJECT = Path(__file__).resolve().parents[2]
CPP = Path(__file__).with_suffix('.cpp')
ENGINE = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
ENGINE_SHA = 'ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424'
def sha(p):
    with Path(p).open('rb') as f: return hashlib.file_digest(f, 'sha256').hexdigest()
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module
GDSCRIPT = '''extends SceneTree
func _initialize():
    call_deferred("run_case")
func run_case():
    var args = OS.get_cmdline_user_args()
    var network_begin = Time.get_ticks_usec()
    var tail_begin = -1
    var tail_pings = 0
    var server = ENetConnection.new()
    var client = ENetConnection.new()
    assert(server.create_host_bound("127.0.0.1", int(args[0]), 2, 2) == OK)
    assert(client.create_host_bound("127.0.0.1", int(args[1]), 2, 2) == OK)
    var peer = client.connect_to_host("127.0.0.1", int(args[0]), 2)
    assert(peer != null)
    var connected = [false, false]
    var disconnected = [false, false]
    var close_sent = false
    var hosts = [server, client]
    var deadline = Time.get_ticks_msec() + 8000
    while Time.get_ticks_msec() < deadline:
        for i in range(2):
            var event = hosts[i].service(0)
            if event[0] == ENetConnection.EVENT_CONNECT:
                connected[i] = true
                print("NATIVE_CONTROLLER connect role=", i)
            elif event[0] == ENetConnection.EVENT_DISCONNECT:
                disconnected[i] = true
                print("NATIVE_CONTROLLER disconnect role=", i)
        if connected[0] and connected[1]:
            if args[2] == "handshake-tail":
                if tail_begin < 0:
                    tail_begin = Time.get_ticks_usec()
                    print("HANDSHAKE_TAIL begin=1")
                if tail_pings < 3 and Time.get_ticks_usec() - tail_begin >= tail_pings * 80000:
                    peer.ping()
                    client.flush()
                    tail_pings += 1
                if Time.get_ticks_usec() - tail_begin >= 250000:
                    print("HANDSHAKE_TAIL pings=", tail_pings, " elapsed_us=", Time.get_ticks_usec()-tail_begin)
                    print("SCRIPT_CASE handshake-tail success=1")
                    server.destroy()
                    client.destroy()
                    print("FIXTURE_WINDOW network_us=", Time.get_ticks_usec()-network_begin)
                    quit(0)
                    return
                OS.delay_msec(2)
                continue
            if args[2] == "handshake":
                print("SCRIPT_CASE handshake success=1")
                server.destroy()
                client.destroy()
                print("FIXTURE_WINDOW network_us=", Time.get_ticks_usec()-network_begin)
                quit(0)
                return
            if not close_sent:
                print("SCRIPT_CLOSE peer_disconnect requested=1")
                peer.peer_disconnect()
                client.flush()
                close_sent = true
        if disconnected[0] and disconnected[1]:
            print("SCRIPT_CASE close success=1")
            server.destroy()
            client.destroy()
            print("FIXTURE_WINDOW network_us=", Time.get_ticks_usec()-network_begin)
            quit(0)
            return
        OS.delay_msec(2)
    print("SCRIPT_CASE failure connected=", connected, " disconnected=", disconnected)
    server.destroy()
    client.destroy()
    quit(1)
'''
def fields(line): return dict(re.findall(r'(\w+)=([^\s]+)', line))
def validate(text, kind):
    pending = {}; pairs = []; reads = []; wire = []; rawrows = []; tids = set(); max_pending = 0
    iats = {}; registrations = {}; identity = None
    for line in text.splitlines():
        row = fields(line)
        if line.startswith('OWNED '):
            assert identity is None and row['in_job']=='1'
            identity = row
        elif line.startswith('IAT '):
            assert row['verified']=='1'
            iats[row['api']]=row
        elif line.startswith('REGISTER '):
            assert identity is not None and all(row[k]==identity[k] for k in ('pid','creation'))
            registrations[row['socket']]=row
        if line.startswith('ENTRY '):
            assert row['seq'] not in pending
            pending[row['seq']] = row
            max_pending = max(max_pending, len(pending))
        elif line.startswith('RETURN '):
            start = pending.pop(row['seq'])
            assert all(start[k] == row[k] for k in ('pid','tid','api','socket'))
            pairs.append({**start, **row})
        elif line.startswith('READ '): reads.append(row)
        elif line.startswith('RAW '): rawrows.append(row)
        elif line.startswith('WIRE '): wire.append(row)
    assert not pending, 'unpaired API entry'
    assert set(iats)=={'sendto','recvfrom','bind','closesocket'}
    assert iats['sendto']['owner']=='ws2_32.dll' and iats['recvfrom']['owner']=='wsock32.dll'
    assert len(registrations)==2
    byseq = {p['seq']:p for p in pairs}
    for pair in pairs:
        assert identity is not None and pair['pid']==identity['pid']
    for row in reads:
        pair = byseq[row['seq']]
        assert pair['approved'] == '1'
        assert pair['socket'] in registrations and pair['local']==registrations[pair['socket']]['local']
        assert int(row['off']) + int(row['size']) <= int(row['limit'])
        if row['phase'] == 'recv_return': assert int(pair['value']) > 0
    if kind == 'raw':
        assert len(rawrows) == 12
        for worker in ('0','1'):
            rows = [r for r in rawrows if r['worker'] == worker]
            assert {(r['phase'],r['packet']) for r in rows} == {(phase,str(seq)) for phase in ('send_entry','recv_return') for seq in range(1,4)}
            assert len({byseq[r['seq']]['socket'] for r in rows}) == 1
            assert all(r['local'] == r['remote'] for r in rows)
            tids.update(byseq[r['seq']]['tid'] for r in rows)
        assert len(tids) == 2
        assert len({byseq[r['seq']]['socket'] for r in rawrows})==2
        assert max_pending==2
        assert all(r['off'] == '0' and r['size'] == '12' for r in reads)
        errors = [p for p in pairs if p['api']=='recvfrom' and p['value']=='-1']
        assert len(errors)==2 and all(p['wsa_error']=='10014' for p in errors)
        assert not any(r['seq'] in {p['seq'] for p in errors} for r in reads)
        assert 'ACTOR_RESULT failures=0' in text
    else:
        assert 'NATIVE_CONTROLLER connect role=0' in text and 'NATIVE_CONTROLLER connect role=1' in text
        assert f'SCRIPT_CASE {kind} success=1' in text
        if kind=='close':
            assert 'SCRIPT_CLOSE peer_disconnect requested=1' in text
            assert 'NATIVE_CONTROLLER disconnect role=0' in text and 'NATIVE_CONTROLLER disconnect role=1' in text
        assert any(r['command']=='2' for r in wire), 'CONNECT not observed'
        assert any(r['command']=='1' for r in wire), 'ACK not observed'
        if kind=='close': assert any(r['command']=='4' for r in wire), 'DISCONNECT not observed'
    assert 'OBSERVER_FAIL_CLOSED' not in text and 'CAPTURE exit=0' in text
    return {'pairs':len(pairs), 'header_read_regions':reads, 'raw':rawrows, 'wire':wire, 'max_simultaneous_pending':max_pending,
            'pause':next(fields(x) for x in text.splitlines() if x.startswith('CAPTURE ')), 'validated':True}
def summarize_profile(text):
    events = [fields(x) for x in text.splitlines() if x.startswith('PROFILE_EVENT ')]
    if not events:
        raise ValueError('no measured event profile; cannot infer historical phases')
    capture = next(fields(x) for x in text.splitlines() if x.startswith('CAPTURE '))
    assert len(events) == int(capture['events'])
    assert [int(e['index']) for e in events] == list(range(len(events)))
    assert abs(sum(float(e['ms']) for e in events) - float(capture['pause_total_ms'])) < 0.01
    phases = {}
    for phase in ('startup', 'network_active'):
        rows = [e for e in events if e['phase'] == phase]
        phases[phase] = {'events': len(rows), 'pause_sum_ms': sum(float(e['ms']) for e in rows),
                         'pause_max_ms': max((float(e['ms']) for e in rows), default=0),
                         'max_event': max(rows, key=lambda e: float(e['ms']), default=None)}
    tail = [e for e in events if e.get('subwindow') == 'post_handshake']
    phases['post_handshake_subset'] = {'events':len(tail), 'pause_sum_ms':sum(float(e['ms']) for e in tail),
                                      'pause_max_ms':max((float(e['ms']) for e in tail),default=0)}
    stages = {}
    for line in text.splitlines():
        if line.startswith('PROFILE_STAGE '):
            row = fields(line)
            key = events[int(row['event'])]['phase'] + ':' + row['name']
            dest = stages.setdefault(key, {'calls': 0, 'ms': 0.0, 'bytes': 0})
            for k in dest:
                dest[k] += float(row[k]) if k == 'ms' else int(row[k])
    wall = next(fields(x) for x in text.splitlines() if x.startswith('WALL '))
    return {'phases': phases, 'stages_inclusive_not_additive': stages, 'wall': wall,
            'phase_boundary': 'first bind entry; active includes teardown until child exit',
            'pause_scope': 'handler lower bound; excludes event delivery, ContinueDebugEvent, profile bookkeeping and single-step scheduler waits'}

def validate_control(text, kind):
    row = next(fields(x) for x in text.splitlines() if x.startswith('CONTROL '))
    assert row['exit']=='0' and row['in_job']=='1' and row['debugger']=='0'
    assert not any(x.startswith(('ENTRY ', 'READ ', 'WIRE ', 'PROFILE_EVENT ')) for x in text.splitlines())
    window = next(fields(x) for x in text.splitlines() if x.startswith('FIXTURE_WINDOW '))
    network_ms = float(window['network_ms']) if 'network_ms' in window else float(window['network_us'])/1000
    row['network_ms'] = network_ms
    row['startup_and_unmeasured_exit_residual_ms'] = float(row['child_ms']) - network_ms
    assert row['startup_and_unmeasured_exit_residual_ms'] >= 0
    return row

def fixture_window_ms(text):
    windows=[fields(x) for x in text.splitlines() if x.startswith('FIXTURE_WINDOW ')]
    assert len(windows)==1
    row=windows[0]
    return float(row['network_ms']) if 'network_ms' in row else float(row['network_us'])/1000

def compare_wall(case, observed_text=None):
    debug = case['profile']['wall']; control = case['control']
    network=fixture_window_ms(observed_text) if observed_text else case['fixture_network_ms']
    child_delta=float(debug['child_ms'])-float(control['child_ms'])
    network_delta=network-control['network_ms']
    return {'child_wall_delta_ms':child_delta,
            'fixture_network_wall_delta_ms':network_delta,
            'outside_network_window_delta_ms':child_delta-network_delta,
            'fixture_network_ms':network,
            'debug_bind_to_exit_ms':float(debug['active_ms']),
            'scope':'n=1 independent processes; identical fixture monotonic pre-bind-to-destroy windows; outside includes startup AND final engine exit; not a calibrated error bar'}

def validate_small(text, kind):
    entries=[fields(x) for x in text.splitlines() if x.startswith('ENTRY ')]
    returns=[fields(x) for x in text.splitlines() if x.startswith('RETURN ')]
    if kind=='unload':
        assert 'ACTOR_UNLOAD requested=1' in text and 'CACHE_INVALIDATE ' in text
        assert 'OBSERVER_FAIL_CLOSED watched_module_unload' in text
        assert 'ACTOR_UNLOAD returned=1' not in text and 'CAPTURE exit=0' not in text
        return {'validated':True,'expected_fail_closed':True,'scope':'real self-owned DLL FreeLibrary, armed exported marker; cache invalidates before refusal'}
    pending={};maxdepth=0
    for line in text.splitlines():
        row=fields(line)
        if line.startswith('ENTRY '):
            stack=pending.setdefault(row['tid'],[]);stack.append(row);maxdepth=max(maxdepth,len(stack))
        elif line.startswith('RETURN '):
            start=pending[row['tid']].pop()
            assert row['seq']==start['seq'] and row['return_pc']==start['return_pc']
    assert not any(pending.values()) and len(entries)==len(returns)
    assert 'OBSERVER_FAIL_CLOSED' not in text and 'CAPTURE exit=0' in text
    assert not any(x.startswith('READ ') for x in text.splitlines())
    if kind=='send-error':
        errors=[r for r in returns if r['api']=='sendto']
        assert len(errors)==1 and errors[0]['value']=='-1' and errors[0]['wsa_error']=='10038'
        assert 'ACTOR_SEND_ERROR result=-1 error=10038' in text
        assert next(r for r in entries if r['api']=='sendto')['approved']=='0'
    else:
        assert len(entries)==4 and len({r['tid'] for r in entries})==1 and maxdepth==4
        assert len({r['return_pc'] for r in entries})==2
        assert all(r['api']=='control_recursive' for r in entries)
        assert 'ACTOR_RECURSION result=3 scope=call_stack_control_not_system_API' in text
    return {'validated':True,'entries':len(entries),'maxdepth':maxdepth,'payload_bytes_read':0,
            'scope':'real WinSock error' if kind=='send-error' else 'self-owned recursive call-stack control, NOT recursive system API'}

def protected_files():
    # Owned diagnostic writes are excluded; production, tests, native artifacts and other helpers are readonly.
    files={ENGINE, PROJECT/'project.godot', PROJECT/'docs/round68-owned-winsock-observer.md'}
    allowed={CPP,Path(__file__).resolve(),PROJECT/'tools/tests/test_round69_winsock_overhead.py'}
    for directory in ('scripts','tests','test','addons','tools'):
        for p in (PROJECT/directory).rglob('*'):
            if p.is_file() and p.suffix.lower() in ('.gd','.tscn','.cpp','.h','.hpp','.dll','.py') and p.resolve() not in allowed:
                files.add(p)
    old=Path('E:/scratch/isolated-ade1b96e02db40efac298cbb4c3c8489')
    files.update((old/'generated/observer.cpp',old/'generated/observer.exe',old/'evidence/report.json',old/'evidence/verification.json'))
    return files

def approved_port_pair(values):
    if type(values) is not list or len(values)!=2 or any(type(p) is not int or not 30000<=p<=65000 for p in values) or values[0]==values[1]:
        raise ValueError('exact distinct approved integer ports required before bind; no 28100')
    return values

def archive_path(path, owner):
    path=Path(path).absolute()
    for p in [path,*path.parents]:
        if p.is_symlink() or p.is_junction():raise ValueError('artifact reparse refused')
    path=path.resolve()
    if not path.is_relative_to(owner) or path==owner:
        raise ValueError('artifact outside owned archive')
    return path

def baseline_readback(owner):
    owner=Path(owner).resolve()
    if owner.parent!=Path('E:/scratch').resolve() or not re.fullmatch(r'isolated-[a-f0-9]{32}',owner.name):
        raise ValueError('baseline requires exact own E UUID root')
    for p in [owner,*owner.parents]:
        if p.is_symlink() or p.is_junction():raise ValueError('baseline reparse rejected')
    report=json.loads((owner/'evidence/report.json').read_text(encoding='utf-8'))
    approved_port_pair(report['ports'])
    assert report['passed'] and report['job0'] and all(x['exited'] and x['active_owned_processes']==0 for x in report['processes'])
    assert sha(owner/'generated/observer.cpp')==report['hashes'][str(CPP)]
    assert sha(owner/'generated/observer.exe')==report['hashes'][str(owner/'generated/observer.exe')]
    summaries={k:summarize_profile((owner/'evidence'/f'{k}.stdout.log').read_text(encoding='utf-8')) for k in ('raw','handshake','close')}
    return {'owner':str(owner),'report_sha256':sha(owner/'evidence/report.json'),'ports':report['ports'],'profiles':summaries}

def run(only_raw=False, native_only=False, compare_root=None):
    isolation = load('round68_isolation', PROJECT/'tools/run_isolated_godot_test.py')
    owner = isolation.physical_e('E:/scratch') / ('isolated-'+uuid.uuid4().hex)
    owner.mkdir(); generated=owner/'generated'; generated.mkdir(); evidence=owner/'evidence'; evidence.mkdir()
    env=os.environ.copy(); env['_NO_DEBUG_HEAP']='1'; env['VSLANG']='1033'
    for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR'):
        p=generated/key.lower(); p.mkdir(); env[key]=str(p)
    report={'owner':str(owner),'processes':[],'cases':{},'small_cases':{},'passed':False,'recovery_runs':0,'attach_calls':0,'payload_bytes_read':0,'mode':'round69_cached','file_attempt_limit':3,'production_authorized':False,'warm_scope':'observer own static files only'}
    before={str(p):sha(p) for p in protected_files()}
    report['protected_before']=before
    if compare_root:report['baseline']=baseline_readback(compare_root)
    budget={'seconds':90,'bytes':1024**3,'min_free':1024**3}
    def save():
        p=evidence/'report.json'; p.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        assert json.loads(p.read_text(encoding='utf-8')) == report
    def execute(command,name):
        out,err,code=isolation.execute(command,env,generated,evidence,name,budget,report['processes'])
        report.setdefault('commands',[]).append({'name':name,'command':command,'exit':code})
        save(); return out,err,code
    print('ROUND68_OWNER '+str(owner),flush=True)
    try:
        assert sha(ENGINE)==ENGINE_SHA
        source=generated/'observer.cpp'; shutil.copyfile(CPP,source)
        shutil.copyfile(Path(__file__),generated/'observer_launcher.py')
        assert sha(source)==sha(CPP)
        report['source_artifacts']={str(source):sha(source),str(generated/'observer_launcher.py'):sha(generated/'observer_launcher.py')}
        binary=generated/'observer.exe'; build=generated/'build.cmd'
        build.write_text('@call "D:/VS2022/Common7/Tools/VsDevCmd.bat" -arch=x64 -host_arch=x64\n'+f'@cl /nologo /EHsc /std:c++17 /utf-8 /W3 /WX "{source}" /Fe:"{binary}" /Fo:"{generated / "observer.obj"}" /link wsock32.lib bcrypt.lib\n@if errorlevel 1 exit /b 1\n'+f'@cl /nologo /EHsc /std:c++17 /utf-8 /W3 /WX /LD /DROUND69_UNLOAD_DLL "{source}" /Fe:"{generated / "owned-unload.dll"}" /Fo:"{generated / "owned-unload.obj"}"\n',encoding='utf-8')
        compiler=load('round68_owned_compiler',PROJECT/'tools/diagnostics/assembly_publish_failure_capture.py')
        out,err,code=compiler.compile_owned(isolation,['cmd.exe','/d','/c',str(build)],env,generated,evidence,report['processes'])
        save()
        assert code==0, 'build failed: '+out+err
        out,err,code=execute([str(binary),'--cache-unit'],'cache-unit')
        assert code==0 and 'CACHE_UNIT cases=5 real_self_image=1' in out, out+err
        report['cache_unit']=out
        out,err,code=execute([str(binary),'--unit'],'unit')
        assert code==0 and 'UNIT cases=63 payload_bytes_read=0' in out, out+err
        report['unit']=out
        # Only reserve fresh loopback ports; never inspect or bind the user's 28100.
        reservations=[]
        for port in report.get('baseline',{}).get('ports',[0,0]):
            sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);sock.bind(('127.0.0.1',port));reservations.append(sock)
        ports=[s.getsockname()[1] for s in reservations]
        assert all(30000<=p<=65000 for p in ports) and len(set(ports))==2
        for sock in reservations:sock.close()
        report['ports']=ports
        a,b=map(str,ports)
        for kind,flag in (('send-error','--actor-send-error'),('recursive','--actor-recursive'),('unload','--actor-unload')):
            out,err,code=execute([str(binary),'raw',a,b,str(binary),flag,a,b],kind)
            assert code==(2 if kind=='unload' else 0), out+err
            report['small_cases'][kind]=validate_small(out,kind);save()
        if native_only:
            report['readonly_unchanged']=all(sha(p)==h for p,h in before.items())
            report['job0']=all(p.get('exited') is True and p.get('active_owned_processes')==0 for p in report['processes'])
            report['passed']=report['readonly_unchanged'] and report['job0']
            report['hashes']={str(p):sha(p) for p in (CPP,Path(__file__),binary,generated/'owned-unload.dll')}
            report['log_artifacts']={str(p):sha(p) for p in evidence.glob('*.log')}
            report['protected_after']={str(p):sha(p) for p in before}
            assert report['protected_after']==before
            save();return 0 if report['passed'] else 1
        out,err,code=execute([str(binary),'raw',a,b,str(binary),'--actor',a,b],'raw')
        assert code==0, out+err
        report['cases']['raw']=validate(out,'raw');report['cases']['raw']['profile']=summarize_profile(out);save()
        co,ce,cc=execute([str(binary),'control-raw',a,b,str(binary),'--actor',a,b],'raw-control')
        assert cc==0 and 'ACTOR_RESULT failures=0' in co and 'CONTROL exit=0' in co, co+ce
        report['cases']['raw']['control']=validate_control(co,'raw');report['cases']['raw']['wall_comparison']=compare_wall(report['cases']['raw'],out);save()
        print('RAW_GREEN '+str(owner),flush=True)
        if not only_raw:
            project=generated/'project';project.mkdir()
            (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Round68BareENet"\n[threading]\nworker_pool/max_threads=2\n',encoding='utf-8')
            (project/'fixture.gd').write_text(GDSCRIPT,encoding='utf-8',newline='\n')
            for case in ('handshake','close','handshake-tail'):
                out,err,code=execute([str(binary),'enet',a,b,str(ENGINE),'--headless','--path',str(project),'--script','res://fixture.gd','--',a,b,case],case)
                assert code==0 and 'SCRIPT ERROR' not in out+err, out+err
                # Generated script/controller stdout is separate from native API header evidence.
                report['cases'][case]=validate(out,case);report['cases'][case]['profile']=summarize_profile(out);save()
                co,ce,cc=execute([str(binary),'control-enet',a,b,str(ENGINE),'--headless','--path',str(project),'--script','res://fixture.gd','--',a,b,case],case+'-control')
                assert cc==0 and f'SCRIPT_CASE {case} success=1' in co and 'CONTROL exit=0' in co, co+ce
                report['cases'][case]['control']=validate_control(co,case);report['cases'][case]['wall_comparison']=compare_wall(report['cases'][case],out);save()
        report['readonly_unchanged']=all(sha(p)==h for p,h in before.items())
        report['job0']=all(p.get('exited') is True and p.get('active_owned_processes')==0 for p in report['processes'])
        report['passed']=report['readonly_unchanged'] and report['job0'] and all(x['validated'] for x in report['cases'].values())
        report['hashes']={str(p):sha(p) for p in (CPP,Path(__file__),binary,generated/'owned-unload.dll')}
        if not only_raw:
            report['source_artifacts'].update({str(project/'fixture.gd'):sha(project/'fixture.gd'),str(project/'project.godot'):sha(project/'project.godot')})
        report['log_artifacts']={str(p):sha(p) for p in evidence.glob('*.log')}
        report['protected_after']={str(p):sha(p) for p in before}
        assert report['protected_after']==before
        for p,h in report['source_artifacts'].items():assert sha(p)==h
    except Exception as exc:
        report['passed']=False
        report['error']=repr(exc)
    finally:
        report['job0']=all(p.get('exited') is True and p.get('active_owned_processes')==0 for p in report['processes'])
        save(); print(json.dumps({'owner':str(owner),'passed':report['passed'],'job0':report['job0'],'error':report.get('error')},ensure_ascii=False),flush=True)
    return 0 if report['passed'] else 1
def verify(owner):
    owner=Path(owner).resolve()
    if owner.parent!=Path('E:/scratch').resolve() or not re.fullmatch(r'isolated-[a-f0-9]{32}',owner.name):
        raise ValueError('requires exact owned E UUID root')
    for p in [owner,*owner.parents]:
        if p.is_symlink() or p.is_junction(): raise ValueError('reparse root refused')
    evidence=owner/'evidence'; original=evidence/'report.json'
    report=json.loads(original.read_text(encoding='utf-8'))
    assert report['owner']==str(owner) and report['job0']
    assert all(c['validated'] for c in report['cases'].values())
    changed={p:{'before':h,'after':report.get('protected_after',{}).get(p)} for p,h in report.get('protected_before',{}).items() if report.get('protected_after',{}).get(p)!=h}
    if not report['passed']:
        assert changed and report.get('error')=='AssertionError()', 'not a readonly-manifest-only incomplete run'
    assert all(p['exited'] is True and p['active_owned_processes']==0 for p in report['processes'])
    assert report['hashes'][str(CPP)]==sha(owner/'generated/observer.cpp')
    for p,h in report.get('source_artifacts',{}).items():assert sha(archive_path(p,owner))==h
    for p,h in report.get('log_artifacts',{}).items():assert sha(archive_path(p,owner))==h
    assert bool(changed)==(report.get('readonly_unchanged') is False)
    assert report['hashes'][str(owner/'generated/observer.exe')]==sha(owner/'generated/observer.exe')
    dll=owner/'generated/owned-unload.dll'
    if str(dll) in report['hashes']:assert report['hashes'][str(dll)]==sha(dll)
    result={'original_report_sha256':sha(original),'verifier_sha256':sha(__file__),'job0':True,'no_processes_started':True,'cases':{},'overall_passed':report['passed'],'protected_changed':changed,'same_global_freeze':not changed}
    for kind in report['cases']:
        log=evidence/(kind+'.stdout.log'); result['cases'][kind]=validate(log.read_text(encoding='utf-8'),kind)
        result['cases'][kind]['log_sha256']=sha(log)
        if report['cases'][kind].get('profile'):
            result['cases'][kind]['profile']=summarize_profile(log.read_text(encoding='utf-8'))
            assert result['cases'][kind]['profile']==report['cases'][kind]['profile']
            control=(evidence/(kind+'-control.stdout.log')).read_text(encoding='utf-8')
            result['cases'][kind]['control']=validate_control(control,kind)
            assert result['cases'][kind]['control']==report['cases'][kind]['control']
            result['cases'][kind]['aligned_wall_comparison']=compare_wall(report['cases'][kind],log.read_text(encoding='utf-8'))
    result['small_cases']={kind:validate_small((evidence/(kind+'.stdout.log')).read_text(encoding='utf-8'),kind) for kind in report.get('small_cases',{})}
    assert result['small_cases']==report.get('small_cases',{})
    result['official_checksum_default']={'url':'https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf001b61586d9930840f2f1394092c079/thirdparty/enet/host.c','sha256':sha(Path('E:/scratch/isolated-ade1b96e02db40efac298cbb4c3c8489/evidence/official-host.c')),'line':89,'checksum':'NULL','scope':'generated bare ENetConnection, no compress or checksum setter; never infer production configuration'}
    result['measured_pause_scope']='debug event handler elapsed, excludes event delivery latency and suspended single-step scheduler latency; lower bound, perturbation present'
    output=evidence/'verification.json'
    if output.exists(): raise ValueError('verification already exists; do not overwrite')
    output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    assert json.loads(output.read_text(encoding='utf-8'))==result
    print(json.dumps({'verification':str(output),'sha256':sha(output),'job0':True,'cases':list(result['cases']),'evidence_readback_verified':True,'overall_passed':report['passed'],'protected_changed':list(changed)},ensure_ascii=False))
    return 0
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--execute',action='store_true');p.add_argument('--raw-only',action='store_true');p.add_argument('--native-only',action='store_true');p.add_argument('--compare-root',type=Path);p.add_argument('--verify',type=Path);a=p.parse_args()
    if a.verify:
        if a.execute or a.raw_only or a.native_only or a.compare_root:p.error('verify is offline only')
        raise SystemExit(verify(a.verify))
    if not a.execute:p.error('requires --execute (new owned fixtures only)')
    raise SystemExit(run(a.raw_only,a.native_only,a.compare_root))
