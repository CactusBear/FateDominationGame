"""Owned E-only short headless observations; existing runner owns every Job PID."""
import argparse
import ast
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import socket
import threading
import time
import uuid
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tests"))
from runtime_observation_source_proof import reconstruct_original_channel
from round64_native_contract_source_test import audit, EXPECTED

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('owned_runner', ROOT / 'tools/run_isolated_godot_test.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

def ipc_observation(godot,target,generated,evidence,env,budgets,processes,budget):
    name = 'production-ipc-' + str(budget)
    runtime = generated / name
    runtime.mkdir()
    storage = runtime / 'rooms'
    storage.mkdir()
    control = runtime / 'console'
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as probe:
        probe.bind(('127.0.0.1',0))
        port = probe.getsockname()[1]
    configuration = {'port':port,'bind_address':'127.0.0.1','roles':['game'],'data_root':(ROOT/'data').as_posix(),'storage_root':storage.as_posix(),'console_dir':control.as_posix(),'data':{'random_sim_enabled':True,'random_sim_budget_sec':budget},'server_name':'round54-observer','motd':'read-only','record_matches':True,'transaction_log':True,'authority_host_mode':'dedicated','recovery_key_mismatch':'reject','recovery_inheritance':'host_select','shutdown_seconds':5}
    config = runtime / 'server.json'
    config.write_text(json.dumps(configuration),encoding='utf-8')
    command = [str(godot),'--headless','--fixed-fps','60','--path',str(target),'--scene','res://assets/scenes/main_menu/server_cli.tscn','--','--server-gateway','--config',str(config)]
    outcome = {}
    def launch():
        try: outcome['execution'] = runner.execute(command,env,generated,evidence,name,budgets,processes)
        except Exception as exc: outcome['error'] = str(exc)
    task = threading.Thread(target=launch)
    task.start()
    end = time.monotonic() + 45
    try:
        while not (control/'control.json').exists():
            if not task.is_alive() or time.monotonic() > end: raise RuntimeError('production console not ready '+name)
            time.sleep(.05)
        instance = json.loads((control/'control.json').read_text())['instance']
        def request(command,instance_override=None):
            token = uuid.uuid4().hex
            path = control/(token+'.request.json')
            temporary = path.with_suffix('.tmp')
            temporary.write_text(json.dumps({'instance':instance if instance_override is None else instance_override,'command':command}),encoding='utf-8')
            temporary.replace(path)
            response = control/(token+'.response.json')
            deadline = time.monotonic()+15
            while not response.exists():
                if time.monotonic()>deadline or not task.is_alive(): raise RuntimeError('missing IPC response '+command)
                time.sleep(.05)
            return json.loads(response.read_text(encoding='utf-8'))
        response = request('status')
        stale = request('status','stale-instance')
        (evidence/(name+'.status.json')).write_text(json.dumps(response,indent=2),encoding='utf-8')
        result = response['result']
        legacy = {k:v for k,v in result.items() if k not in ['native_capabilities','validation_policy','worker_pool']}
        expected = {'game_port':port,'rooms':0,'attached_clients':0,'pending_clients':0,'relay_port':0,'server_name':'round54-observer','motd':'read-only'}
        caps = result['native_capabilities']
        passed = response['ok'] is True and legacy == expected and result['validation_policy'] == {'enabled':True,'budget':budget} and result['worker_pool'] == {'max_threads':20} and len(result)==10 and len(caps)==4 and all(c['exists'] is True and c['can_instantiate'] is True and all(v is True for v in c['methods'].values()) for c in caps.values()) and sum(len(c['methods']) for c in caps.values())==13 and stale['ok'] is False
        stop = request('stop')
        outcome.update({'passed':passed,'legacy_equivalent':legacy==expected,'stop':stop,'stale_rejected':stale['ok'] is False,'response_sha256':hashlib.sha256((evidence/(name+'.status.json')).read_bytes()).hexdigest()})
    except Exception as exc:
        outcome['error'] = str(exc)
        if 'request' in locals() and task.is_alive():
            try: outcome['stop_after_error'] = request('stop')
            except Exception: pass
    task.join(190)
    if 'execution' in outcome:
        out,err,code = outcome.pop('execution')
        outcome['exit_code'] = code
        outcome['passed'] = outcome.get('passed',False) and code==0 and not re.search(r'SCRIPT ERROR|ERROR:',out+err) and 'SERVER_GATEWAY_READY ' in out
    else: outcome['passed'] = False
    return outcome

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--phase', required=True)
    parser.add_argument('--ipc', action='store_true')
    parser.add_argument('--baseline-channel-sha')
    args = parser.parse_args()
    baseline_hashes = json.loads((ROOT/'newtests/round64_baseline/source-sha.json').read_text())
    approved = runner.physical_e(Path('E:/scratch'))
    token = uuid.uuid4().hex
    owner = approved / ('isolated-' + token)
    owner.mkdir()
    generated = owner / 'generated'
    evidence = owner / 'evidence'
    generated.mkdir()
    evidence.mkdir()
    target = generated / 'project'
    target.mkdir()
    manifest = {'run_id':token,'generated':str(generated),'phase':args.phase, 'processes':[], 'source_files':[], 'passed':False}
    budgets = {'seconds':180, 'bytes':1500000000, 'min_free':2000000000}
    env = os.environ.copy()
    env['APPDATA'] = str(generated / 'appdata')
    env['LOCALAPPDATA'] = str(generated / 'localappdata')
    Path(env['APPDATA']).mkdir()
    Path(env['LOCALAPPDATA']).mkdir()
    fixture_root = generated / 'observation-fixtures'
    fixture_root.mkdir()
    env['HERMES_OBSERVATION_FIXTURE'] = fixture_root.as_posix()
    godot = runner.physical_e(Path('E:/scratch/round51-engine/Godot_v4.7.2-stable_win64.exe'))
    selected = set()
    queue = ['newtests/round64_native_contract_test.gd','newtests/round64_native_contract_test.tscn','newtests/round64_native_rejection_test.gd','newtests/round64_native_rejection_test.tscn','tests/server_deployment_default_budget_test.gd','tests/server_deployment_default_budget_test.tscn','assets/config/server.cfg','project.godot','tests/runtime_observation_contract_test.gd','tests/runtime_observation_contract_test.tscn','tests/net_server_console_channel_test.gd','tests/net_server_console_channel_test.tscn','scripts/net/server/server_cli.gd','assets/scenes/main_menu/server_cli.tscn']
    # Global classes must be indexed, but only their explicit resource dependencies are copied.
    queue += [p.relative_to(ROOT).as_posix() for p in (ROOT / 'scripts').rglob('*.gd')]
    while queue:
        name = queue.pop()
        if name in selected: continue
        source = ROOT / name
        if not source.is_file(): continue
        runner.contained(source, ROOT)
        selected.add(name)
        if source.suffix in {'.gd','.tscn','.tres','.godot'}:
            text = source.read_text(encoding='utf-8-sig')
            if source.suffix == '.gd':
                queue.extend(re.findall(r'preload\("res://([^"\n]+)"\)',text))
                queue.extend(re.findall(r'extends "res://([^"\n]+)"',text))
            elif source.suffix in {'.tscn','.tres'}:
                queue.extend(re.findall(r'path="res://([^"\n]+)"',text))
    selected.discard('addons/godot_ai/runtime/game_helper.gd')
    selected.update(p.relative_to(ROOT).as_posix() for p in (ROOT/'data').rglob('*') if p.is_file())
    selected.add('addons/fate_server_signals/fate_server_signals.gdextension')
    selected.update(p.relative_to(ROOT).as_posix() for p in (ROOT / 'addons/fate_server_signals/bin').glob('*.dll') if not p.name.startswith('~'))
    selected.add('addons/webrtc_native/webrtc_native.gdextension')
    selected.update(p.relative_to(ROOT).as_posix() for p in (ROOT / 'addons/webrtc_native/lib').glob('libwebrtc_native.windows.template_*.x86_64.dll'))
    for name in sorted(selected):
        source = ROOT / name
        destination = target / name
        destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(source,destination)
        digest = hashlib.sha256(destination.read_bytes()).hexdigest()
        if digest != hashlib.sha256(source.read_bytes()).hexdigest(): raise RuntimeError('source drift '+name)
        manifest['source_files'].append({'path':name,'sha256':digest})
    if args.baseline_channel_sha:
        path = target / 'scripts/net/server/server_console_channel.gd'
        baseline = reconstruct_original_channel(path.read_text(encoding='utf-8'))
        data = baseline.encode('utf-8')
        if hashlib.sha256(data).hexdigest()!=args.baseline_channel_sha:
            data = baseline.replace('\n','\r\n').encode('utf-8')
        if hashlib.sha256(data).hexdigest()!=args.baseline_channel_sha: raise RuntimeError('baseline channel hash mismatch')
        path.write_bytes(data)
        manifest['isolated_baseline_channel_sha256'] = args.baseline_channel_sha
    config = (target / 'project.godot').read_text(encoding='utf-8-sig')
    config = re.sub(r'^_mcp_game_helper=.*\n','',config,flags=re.M)
    config = config.replace('version_control/autoload_on_startup=true','version_control/autoload_on_startup=false')
    config = re.sub(r'enabled=PackedStringArray\("res://addons/godot_ai/plugin.cfg"\)','enabled=PackedStringArray()',config)
    config = config.replace('renderer/rendering_method="mobile"','renderer/rendering_method="gl_compatibility"')
    config = re.sub(r'^run/main_scene(?:\.fate_server)?=.*\n','',config,flags=re.M)
    (target / 'project.godot').write_text(config,encoding='utf-8')
    manifest['isolated_project_sha256'] = hashlib.sha256(config.encode()).hexdigest()
    source_errors = audit(target)
    manifest['contract_source_gate'] = source_errors
    if source_errors: raise RuntimeError('source contract gate rejected '+str(source_errors))
    # Legacy channel fixture has a historical absolute root; change only its output root.
    fixture = target/'tests/net_server_console_channel_test.gd'
    old = '"E:/Projects/Godot/FateDomination/test/console-channel-%d" % Time.get_ticks_usec()'
    text = fixture.read_text(encoding='utf-8')
    if old not in text: raise RuntimeError('legacy fixture root anchor changed')
    text = text.replace(old,'OS.get_environment("HERMES_OBSERVATION_FIXTURE").path_join("console-channel-%d" % Time.get_ticks_usec())')
    fixture.write_text(text,encoding='utf-8')
    manifest['fixture_output_conversion'] = {'path':str(fixture.relative_to(target)),'sha256':hashlib.sha256(fixture.read_bytes()).hexdigest()}
    try:
        # First import resources without cold autoload preloads. Restore exact transformed config before tests.
        import_config = re.sub(r'\[autoload\].*?(?=\n\[|\Z)','',config,flags=re.S)
        (target / 'project.godot').write_text(import_config,encoding='utf-8')
        out,err,code = runner.execute([str(godot),'--headless','--editor','--import','--path',str(target)],env,generated,evidence,'import',budgets,manifest['processes'])
        (target / 'project.godot').write_text(config,encoding='utf-8')
        manifest['import_exit'] = code
        if code != 0 or re.search(r'SCRIPT ERROR|ERROR:',out+err): raise RuntimeError('import rejected')
        for suite in ['runtime_observation_contract_test','net_server_console_channel_test','server_deployment_default_budget_test','round64_native_contract_test']:
            command = [str(godot),'--headless','--fixed-fps','60','--path',str(target),'--scene',('res://newtests/' if suite.startswith('round64_') else 'res://tests/')+suite+'.tscn','--','--server-gateway']
            out,err,code = runner.execute(command,env,generated,evidence,suite,budgets,manifest['processes'])
            manifest[suite] = runner.analyze(out,err,code)
        manifest['passed'] = all(manifest[s]['passed'] for s in ['runtime_observation_contract_test','net_server_console_channel_test','server_deployment_default_budget_test','round64_native_contract_test'])
        minimal = generated/'bootstrap-project'
        minimal.mkdir()
        for name in ['scripts/net/server/server_bootstrap.gd','scripts/io/native_method_contract.gd','newtests/round64_native_rejection_test.gd','newtests/round64_native_rejection_test.tscn']:
            destination = minimal/name
            destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(target/name,destination)
        minimal_config = '[application]\nconfig/name="Round64NativeBoundary"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir="'+(generated/'bootstrap-user').as_posix()+'"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        (minimal/'project.godot').write_text(minimal_config,encoding='utf-8')
        descriptor_source = target/'addons/fate_server_signals/fate_server_signals.gdextension'
        external_descriptor = generated/'external-native.gdextension'
        external_text = descriptor_source.read_text(encoding='utf-8').replace('res://addons/fate_server_signals/bin/',(target/'addons/fate_server_signals/bin').as_posix()+'/')
        external_descriptor.write_text(external_text,encoding='utf-8')
        manifest['external_descriptor_conversion'] = {'sha256':hashlib.sha256(external_descriptor.read_bytes()).hexdigest(),'only_library_path_conversion':True,'automatic_discovery':False}
        env['HERMES_ROUND64_NATIVE_DESCRIPTOR'] = external_descriptor.as_posix()
        native_command = [str(godot),'--headless','--fixed-fps','60','--path',str(minimal),'--scene','res://newtests/round64_native_rejection_test.tscn']
        out,err,code = runner.execute(native_command,env,generated,evidence,'bootstrap-positive',budgets,manifest['processes'])
        manifest['bootstrap_positive'] = runner.analyze(out,err,code)
        manifest['passed'] = manifest['passed'] and manifest['bootstrap_positive']['passed']
        channel_path = target/'scripts/net/server/server_console_channel.gd'
        channel_bytes = channel_path.read_bytes()
        shared_path = minimal/'scripts/io/native_method_contract.gd'
        shared_bytes = shared_path.read_bytes()
        bootstrap_path = minimal/'scripts/net/server/server_bootstrap.gd'
        bootstrap_bytes = bootstrap_path.read_bytes()
        try:
            # A real one-sided drift reproducer: no missing dependency or ClassDB substitution.
            drift_contract = dict(EXPECTED)
            drift_contract['FateProcessOwner'] = EXPECTED['FateProcessOwner'][1:]
            literal = json.dumps(drift_contract,ensure_ascii=False)
            drift_text = channel_bytes.decode().replace('const NATIVE_METHOD_CONTRACT:Dictionary = NativeMethodContract.REQUIRED_METHODS','const NATIVE_METHOD_CONTRACT:Dictionary = '+literal)
            channel_path.write_text(drift_text,encoding='utf-8')
            out,err,code = runner.execute([str(godot),'--headless','--fixed-fps','60','--path',str(target),'--scene','res://newtests/round64_native_contract_test.tscn','--','--server-gateway'],env,generated,evidence,'drift-red',budgets,manifest['processes'])
            red = runner.analyze(out,err,code)
            expected_failures = ['bootstrap and status contracts cannot drift','consumers match actual source declaration','ClassDB observation shares bootstrap contract']
            manifest['drift_red'] = {'analysis':red,'exit_code':code,'expected_failures':expected_failures,'valid':code==1 and 'SCRIPT ERROR' not in out+err and 'ERROR:' not in out+err and all(label in out for label in expected_failures) and out.count('CHECK false ')==3}
            channel_path.write_bytes(channel_bytes)
            out,err,code = runner.execute([str(godot),'--headless','--fixed-fps','60','--path',str(target),'--scene','res://newtests/round64_native_contract_test.tscn','--','--server-gateway'],env,generated,evidence,'drift-green-restored',budgets,manifest['processes'])
            manifest['drift_green'] = runner.analyze(out,err,code)
            manifest['passed'] = manifest['passed'] and manifest['drift_green']['passed']
            negatives = [('missing_method','信令原生方法缺失：FateServerSignals.round64_missing_method'),('unregistered_class','信令原生能力未注册：Round64UnregisteredClass')]
            for mode,reason in negatives:
                for version in ['before','shared']:
                    original = (ROOT/'newtests/round64_baseline/server_bootstrap.gd').read_bytes()
                    if hashlib.sha256(original).hexdigest()!=baseline_hashes['scripts/net/server/server_bootstrap.gd']: raise RuntimeError('baseline hash mismatch')
                    if version == 'before':
                        bootstrap_path.write_bytes(original)
                        destination = bootstrap_path
                        text = original.decode('utf-8')
                    else:
                        bootstrap_path.write_bytes(bootstrap_bytes)
                        destination = shared_path
                        text = shared_bytes.decode('utf-8')
                    if mode == 'missing_method':
                        text = text.replace('"FateServerSignals":["enable"','"FateServerSignals":["round64_missing_method","enable"')
                    else:
                        anchor = 'var required:Dictionary = {' if version=='before' else 'const REQUIRED_METHODS:Dictionary = {'
                        text = text.replace(anchor,anchor+'\n\t"Round64UnregisteredClass":["spawn"],')
                    destination.write_text(text,encoding='utf-8')
                    out,err,code = runner.execute(native_command,env,generated,evidence,mode+'-'+version,budgets,manifest['processes'])
                    expected_marker = 'ROUND64_BOOTSTRAP_REJECTION '+json.dumps({'reason':reason},ensure_ascii=False,separators=(',',':'))
                    valid = code==2 and expected_marker in out and 'SCRIPT ERROR' not in out+err and (out+err).count('ERROR: ')==1 and ('ERROR: '+reason) in out+err and 'SERVER_SIGNALING_NATIVE_READY ' not in out
                    manifest[mode+'_'+version] = {'exit_code':code,'reason':reason,'valid':valid}
                    bootstrap_path.write_bytes(bootstrap_bytes)
                    shared_path.write_bytes(shared_bytes)
            manifest['passed'] = manifest['passed'] and manifest['drift_red']['valid'] and all(manifest[m+'_'+v]['valid'] for m,_ in negatives for v in ['before','shared'])
        finally:
            channel_path.write_bytes(channel_bytes)
            bootstrap_path.write_bytes(bootstrap_bytes)
            shared_path.write_bytes(shared_bytes)
        if args.ipc:
            for budget in [15,61.25]:
                manifest['ipc_'+str(budget)] = ipc_observation(godot,target,generated,evidence,env,budgets,manifest['processes'],budget)
                manifest['passed'] = manifest['passed'] and manifest['ipc_'+str(budget)]['passed']
    except Exception as exc:
        manifest['error'] = str(exc)
    finally:
        manifest['current_source_drift'] = [item['path'] for item in manifest['source_files'] if hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest()!=item['sha256']]
        manifest['readonly_baseline_drift'] = [name for name,digest in baseline_hashes.items() if name not in ['scripts/net/server/server_bootstrap.gd','scripts/net/server/server_console_channel.gd'] and hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest]
        manifest['passed'] = manifest['passed'] and not manifest['current_source_drift'] and not manifest['readonly_baseline_drift']
        manifest['logs'] = [{'path':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in evidence.glob('*.log')]
        (owner / 'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
        if all(p.get('exited') for p in manifest['processes']):
            runner.delete_owned(generated,owner)
            manifest['cleanup'] = 'generated_removed'
        else: manifest['cleanup'] = 'retained_exit_unproven'
        (owner / 'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'manifest':str(owner/'manifest.json'),'passed':manifest['passed'],'error':manifest.get('error'),'cleanup':manifest['cleanup']}))
    return 0 if manifest['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())