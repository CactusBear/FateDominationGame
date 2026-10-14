"""Explicit Windows signaling role: external native deployment, unchanged other roles.

No editor-discovered descriptor is placed in the project or PCK. The original
DLL, four classes and methods are retained and exercised on exported EXEs.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import sys

sys.dont_write_bytecode=True
REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO))
from tools.diagnostics import round53_signaling_initialization as probe
sys.path.insert(0,str(Path(__file__).resolve().parent))
from package_audit import pck_index
import freeze_prepare

PRESET='FateServer Windows'
DECLARATION='native/fate_server_signals.gdextension'

def external_descriptor(original):
    old='"res://'+probe.DLL+'"'
    if original.count(old)!=1:raise ValueError('original Windows native mapping changed')
    return original.replace(old,'"'+Path(probe.DLL).name+'"')

def prepare(sample, source):
    rels=freeze_prepare.inventory(source,role='signaling',cold=True)
    original={r:probe.sha(source/r) for r in rels}
    transformed=freeze_prepare.transform(source,PRESET,rels,'signaling')
    if transformed['project.godot'].count('[network]')!=1:raise ValueError('explicit unique signaling network section required')
    if 'signaling_native_descriptor=' in transformed['project.godot']:raise ValueError('undeclared source-side native policy')
    transformed['project.godot']=transformed['project.godot'].replace('[network]\n','[network]\nsignaling_native_descriptor="'+DECLARATION+'"\n')
    project=sample/'project';project.mkdir()
    for rel in rels:
        if rel in (probe.EXT,probe.DLL):continue
        p=project/rel;p.parent.mkdir(parents=True,exist_ok=True)
        if rel in transformed:p.write_text(transformed[rel],encoding='utf-8',newline='\n')
        else:shutil.copyfile(source/rel,p)
    native=sample/'native';native.mkdir()
    shutil.copyfile(source/probe.DLL,native/Path(probe.DLL).name)
    (native/'fate_server_signals.gdextension').write_text(external_descriptor((source/probe.EXT).read_text()),encoding='utf-8',newline='\n')
    if any(probe.sha(source/r)!=h for r,h in original.items()):raise ValueError('source drift during preparation')
    files={p.relative_to(sample).as_posix():probe.sha(p) for p in sample.rglob('*') if p.is_file()}
    receipt={'source_files':original,'files':files,'role':'signaling','preset':PRESET,'external_descriptor':DECLARATION,'cold':not (project/'.godot').exists()}
    probe.save(sample/'input-manifest.json',receipt)
    return receipt

def audit(package, frozen):
    exe=package/'FateSignaling.exe';pck=exe.with_suffix('.pck')
    if not exe.is_file() or not pck.is_file():raise ValueError('actual EXE/PCK missing')
    index=pck_index(pck)
    forbidden=[]
    for name in index['files']:
        parts=name.lower().removeprefix('res://').split('/')
        if any(p in {'data','operations','rules','tests','test','tools','reports','docs','native'} for p in parts) or name.endswith(('.gdextension','.dll')) or name.startswith(('res://scripts/match/','res://scripts/system/','res://scripts/game_scene/','res://assets/scenes/game_scene/')):forbidden.append(name)
    if forbidden:raise ValueError('signaling PCK contains forbidden resources: '+str(forbidden))
    required=['scripts/net/server/server_bootstrap.gd','scripts/net/server/server_process_signals.gd','scripts/net/p2p/p2p_signal_server.gd','scripts/net/p2p/p2p_invite.gd','scripts/net/transport/webrtc_link.gd']
    for name in required:
        if not any(k=='res://'+name or k=='res://'+name+'.remap' for k in index['files']):raise ValueError('missing packed native wrapper or signaling script: '+name)
    dependencies={DECLARATION:probe.sha(frozen/'native/fate_server_signals.gdextension'),'native/'+Path(probe.DLL).name:probe.sha(frozen/'native'/Path(probe.DLL).name)}
    for name,digest in dependencies.items():
        if probe.sha(package/name)!=digest:raise ValueError('external native asset hash mismatch')
    return {'pck_index':index,'forbidden':forbidden,'external_native':dependencies,'package_files':{p.relative_to(package).as_posix():probe.sha(p) for p in package.rglob('*') if p.is_file()},'autoloads':False,'data_rules_archives':False,'status':'STATIC_PASS_RUNTIME_SEPARATE'}

def production_ready(text, runtime):
    prefix='SERVER_SIGNALING_NATIVE_READY '
    rows=[json.loads(l[len(prefix):]) for l in text.splitlines() if l.startswith(prefix)]
    ready=[json.loads(l.split(' ',1)[1]) for l in text.splitlines() if l.startswith('SERVER_SIGNALING_READY ')]
    stopped=[json.loads(l.split(' ',1)[1]) for l in text.splitlines() if l.startswith('SERVER_SIGNALING_STOP_REQUEST ')]
    return (len(rows)==1 and rows[0].get('status')==0 and rows[0].get('methods_verified') is True
            and len(ready)==1 and ready[0].get('ok') is True and ready[0].get('pid')==runtime['owned'][0]
            and ready[0].get('roles')==['relay'] and type(ready[0].get('port')) is int and 0<ready[0]['port']<=65535
            and set(rows[0].get('classes',[]))==set(probe.METHODS)
            and len(stopped)==1 and stopped[0].get('request')==2
            and stopped[0].get('pid')==runtime['owned'][0]
            and runtime['exit']==0 and not runtime['timeout'] and not runtime['errors']
            and runtime['module_loaded'] and runtime['details'].get('ctrl_break_sender_exit')==0)

def template_capability_control(root, frozen, candidate, templates, runner, helper, godot):
    sample=root/'template-capability-control';sample.mkdir();project=sample/'project';project.mkdir()
    inputs=json.loads((frozen/'input-manifest.json').read_text())['files']
    for rel in inputs:
        if not rel.startswith('project/'):continue
        dest=sample/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(frozen/rel,dest)
    gd=probe.CAPABILITY_GD.replace('extends SceneTree','extends Node').replace('func _initialize() -> void:\n    _run.call_deferred()',
        'func _ready() -> void:\n    var descriptor: String = OS.get_executable_path().get_base_dir().path_join("native/fate_server_signals.gdextension")\n    if GDExtensionManager.load_extension(descriptor) != GDExtensionManager.LOAD_STATUS_OK:\n        get_tree().quit(2)\n        return\n    _run.call_deferred()')
    gd=gd.replace('await process_frame','await get_tree().process_frame').replace('    quit(0 if failures.is_empty() else 1)','    get_tree().quit(0 if failures.is_empty() else 1)')
    (project/'capability_control.gd').write_text(gd,encoding='utf-8',newline='\n')
    (project/'capability_control.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://capability_control.gd" id="1"]\n[node name="Capabilities" type="Node"]\nscript = ExtResource("1")\n',encoding='utf-8',newline='\n')
    settings=project/'project.godot';settings.write_text(settings.read_text().replace('res://assets/scenes/main_menu/server_bootstrap.tscn','res://capability_control.tscn'),encoding='utf-8',newline='\n')
    probe.save(sample/'input-manifest.json',{'files':{p.relative_to(sample).as_posix():probe.sha(p) for p in project.rglob('*') if p.is_file()},'changed_role_variable':'diagnostic capability main scene','shipped_pck_modified':False})
    env=probe.child_env(sample);dest=Path(env['APPDATA'])/'Godot/export_templates/4.7.2.stable';dest.mkdir(parents=True)
    for p in templates.glob('windows_*x86_64*.exe'):shutil.copyfile(p,dest/p.name)
    cold,text=probe.run(sample,runner,godot,['--headless','--rendering-method','gl_compatibility','--editor','--path',str(project),'--import'],env,'first-cold')
    if cold['exit'] or cold['errors'] or cold['module_loaded']:raise ValueError('capability main-scene first cold failed')
    package=sample/'package';package.mkdir()
    export,text=probe.run(sample,runner,godot,['--headless','--rendering-method','gl_compatibility','--path',str(project),'--export-release',PRESET,str(package/'FateSignaling.exe')],env,'export-release')
    if export['exit'] or export['errors'] or export['module_loaded']:raise ValueError('capability control export failed')
    shutil.copytree(candidate/'native',package/'native')
    if probe.sha(package/'FateSignaling.exe')!=probe.sha(candidate/'FateSignaling.exe'):raise ValueError('capability control native host differs from candidate')
    result,text=probe.run(sample,runner,package/'FateSignaling.exe',['--headless','--',str(sample/'capabilities.json'),str(helper)],env,'actual-template-capabilities')
    checks=[line for line in text.splitlines() if line.startswith('R49_CAP ')]
    receipt=json.loads((sample/'capabilities.json').read_text())
    if result['exit'] or result['errors'] or len(checks)!=23 or any(not l.endswith('=true') for l in checks) or not receipt.get('ok'):raise ValueError('same native host four-capability control failed')
    probe.archive_generated(sample)
    return {'runtime':result,'checks':23,'ok':True,'executable_sha256':probe.sha(package/'FateSignaling.exe'),'same_executable_as_candidate':True,'dll_sha256':probe.sha(package/'native'/Path(probe.DLL).name),'separate_diagnostic_main_scene':True,'not_shipped_in_candidate_pck':True,'cold':cold,'export':export}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--source',type=Path,default=REPO);ap.add_argument('--root',type=Path,required=True);ap.add_argument('--godot',type=Path,required=True);ap.add_argument('--templates',type=Path,required=True);ap.add_argument('--prototype-manifest',type=Path,required=True);ap.add_argument('--continue-package-capability-audit',action='store_true');ap.add_argument('--continue-template-supported-control',action='store_true')
    a=ap.parse_args();continuing=a.continue_package_capability_audit or a.continue_template_supported_control
    root=probe.physical_e(a.root,fresh=not continuing);source=a.source.resolve();godot=a.godot.resolve()
    prior=json.loads(a.prototype_manifest.read_text())
    if prior.get('status')!='PROTOTYPE_TWO_FRESH_GREEN_NOT_RELEASE' or len(prior.get('samples',[]))!=2:raise ValueError('two proven prototype samples prerequisite')
    if probe.sha(godot)!=probe.ENGINE_SHA or probe.sha(source/probe.DLL)!=probe.DLL_SHA:raise ValueError('pinned host/native changed')
    if continuing:
        manifest=json.loads((root/'manifest.json').read_text())
        first=root/'fresh-1'
        rejected=first/('native-four-capabilities-no-path-result.json' if a.continue_template_supported_control else 'native-four-capabilities-result.json')
        failed=json.loads(rejected.read_text())
        raw=Path(failed['log']).read_text(encoding='utf-8')
        scope=(failed['exit']==2 and failed['errors']==['ERROR: 信令启动方式：--server-signaling --config 本机配置']) if a.continue_template_supported_control else (failed['exit']==1 and 'compiled without support for path overrides. Aborting.' in raw)
        if len(manifest.get('samples',[]))!=1 or not scope or not all(manifest['samples'][0].get(k,{}).get('exit')==c for k,c in [('cold',0),('export',0),('runtime',0),('negative',2)]):raise ValueError('continuation only allows precise diagnostic argv rejection')
        probe.save(root/('second-blocked-manifest-original.json' if a.continue_template_supported_control else 'first-blocked-manifest-original.json'),manifest)
        manifest['first_scope_rejection']={'result':str(first/'native-four-capabilities-result.json'),'sha256':probe.sha(first/'native-four-capabilities-result.json'),'changed_variable':'remove editor-only --path from capability audit','no_cold_or_product_retry':True}
        tools=root/'diagnostic-tools';runner=tools/'runner.exe';helper=tools/'capability_helper.exe';indices=(2,)
    else:
        root.mkdir();tools=root/'diagnostic-tools';tools.mkdir();runner=probe.compile_runner(tools);helper=probe.compile_capability_helper(tools);indices=(1,2)
        manifest={'role':'signaling','classification':'CANDIDATE_SOURCE_NOT_LOCKED','prototype_manifest':str(a.prototype_manifest),'prototype_sha256':probe.sha(a.prototype_manifest),'engine_sha256':probe.sha(godot),'original_dll_sha256':probe.sha(source/probe.DLL),'original_descriptor_sha256':probe.sha(source/probe.EXT),'samples':[],'status':'RUNNING','other_roles_modified':False}
    try:
        initial=None
        if continuing:
            initial=json.loads((first/'input-manifest.json').read_text())['files']
            env=os.environ.copy()
            for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR'):env[key]=str(first/'user'/key)
            package=Path(manifest['samples'][0]['package'])
            if a.continue_template_supported_control:
                manifest['template_capability_control']=template_capability_control(root,first,package,a.templates,runner,helper,godot)
                manifest['samples'][0]['capabilities']={'registered_and_methods_verified_on_actual_exe':True,'full_functions':'same EXE/DLL separate main-scene control: 23/23'}
            else:manifest['samples'][0]['capabilities']=probe.capabilities(first,runner,package/'FateSignaling.exe',env,helper,descriptor=package/DECLARATION,project_override=False,label='native-four-capabilities-no-path')
            probe.archive_generated(first)
        for n in indices:
            sample=root/('fresh-'+str(n));sample.mkdir();freeze=prepare(sample,source)
            if initial is None:initial=freeze['files']
            elif initial!=freeze['files']:raise ValueError('different fresh production input sets')
            env=probe.child_env(sample)
            template_dir=Path(env['APPDATA'])/'Godot/export_templates/4.7.2.stable';template_dir.mkdir(parents=True)
            templates={}
            for p in a.templates.glob('windows_*x86_64*.exe'):
                dest=template_dir/p.name;shutil.copyfile(p,dest);templates[p.name]=probe.sha(dest)
            if len(templates)!=4:raise ValueError('exact four official templates required')
            project=sample/'project'
            item={'root':str(sample),'input_manifest':str(sample/'input-manifest.json'),'templates':templates};manifest['samples'].append(item)
            cold,text=probe.run(sample,runner,godot,['--headless','--verbose','--rendering-method','gl_compatibility','--editor','--path',str(project),'--import'],env,'first-cold')
            item['cold']=cold
            if cold['exit'] or cold['timeout'] or cold['errors'] or cold['module_loaded']:raise ValueError('first production cold failed; no warm retry')
            extensions=project/'.godot/extension_list.cfg'
            if extensions.exists() and extensions.read_text().strip():raise ValueError('native discovered by editor')
            package=root/('artifacts/signaling' if n==1 else 'verification/signaling-second');package.mkdir(parents=True)
            export,text=probe.run(sample,runner,godot,['--headless','--rendering-method','gl_compatibility','--path',str(project),'--export-release',PRESET,str(package/'FateSignaling.exe')],env,'export-release')
            item['export']=export
            if export['exit'] or export['timeout'] or export['errors'] or export['module_loaded']:raise ValueError('export failed or loaded native too early')
            shutil.copytree(sample/'native',package/'native')
            with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
            config=package/'signaling.json';probe.save(config,{'roles':['relay'],'p2p_signaling':True,'port':port,'bind_address':'127.0.0.1'})
            item['package']=str(package);item['audit']=audit(package,sample)
            runtime,text=probe.run(sample,runner,package/'FateSignaling.exe',['--headless','--','--server-signaling','--config',str(config)],env,'actual-exported-runtime',interaction=lambda p:probe.traffic(p['port']))
            item['runtime']=runtime
            if not production_ready(text,runtime):raise ValueError('actual EXE native/READY/traffic/CTRL_BREAK failed')
            negative,text=probe.run(sample,runner,package/'FateSignaling.exe',['--headless','--','--server-signaling','--config',str(package/'missing.json')],env,'actual-exported-negative')
            item['negative']=negative
            if not probe.negative_contract(negative,text,require_script_backtrace=False):raise ValueError('actual EXE missing-config exact contract failed')
            item['capabilities']={'registered_and_methods_verified_on_actual_exe':True,'full_functions':'see separate same-EXE/DLL main-scene control'}
            current=freeze_prepare.inventory(source,role='signaling',cold=True)
            if set(current)!=set(freeze['source_files']) or any(probe.sha(source/r)!=h for r,h in freeze['source_files'].items()):raise ValueError('production source drift after runtime')
            probe.archive_generated(sample)
        if 'template_capability_control' not in manifest:
            manifest['template_capability_control']=template_capability_control(root,root/'fresh-1',Path(manifest['samples'][0]['package']),a.templates,runner,helper,godot)
        manifest['status']='TWO_FRESH_SIGNALING_CANDIDATE_GREEN'
        manifest['recommended_candidate']=manifest['samples'][0]['package']
        manifest['remaining']=['client/server new-round verification','GUI and real multi-host/cross-network acceptance']
    except Exception as exc:manifest['status']='BLOCKED';manifest['failure']=str(exc)
    if manifest['status']=='TWO_FRESH_SIGNALING_CANDIDATE_GREEN':manifest.pop('failure',None)
    if continuing:
        with (root/'manifest.json').open('w',encoding='utf-8',newline='\n') as f:json.dump(manifest,f,ensure_ascii=False,indent=2)
    else:probe.save(root/'manifest.json',manifest)
    print(json.dumps({'status':manifest['status'],'failure':manifest.get('failure'),'manifest':str(root/'manifest.json')},ensure_ascii=False))
    return 0 if manifest['status']=='TWO_FRESH_SIGNALING_CANDIDATE_GREEN' else 1

if __name__=='__main__':raise SystemExit(main())