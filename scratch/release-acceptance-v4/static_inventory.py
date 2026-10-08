"""只读发行盘点；输出仅写本脚本所在 scratch，绝不启动引擎。"""
from pathlib import Path
import hashlib, struct, json, re, os
ROOT = Path('E:/Projects/Godot/FateDominationGame-master')
DIST = Path('E:/Projects/Godot/FateDomination/test/server-dist')
OUT = Path(__file__).resolve().parent

def sha(p):
    h = hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda: f.read(1024*1024), b''): h.update(chunk)
    return h.hexdigest()

def info(p):
    return {'path':str(p), 'size':p.stat().st_size, 'mtime_ns':p.stat().st_mtime_ns, 'sha256':sha(p)}

def pck(p):
    entries=[]
    with p.open('rb') as f:
        header=f.read(112)
        magic, version, major, minor, patch, flags=struct.unpack_from('<6I',header)
        assert magic==0x43504447 and version==4 and not flags & 1, '只接受实测未加密 v4'
        base, directory=struct.unpack_from('<2Q',header,24)
        f.seek(directory)
        count=struct.unpack('<I',f.read(4))[0]
        assert count < 100000
        for _ in range(count):
            length=struct.unpack('<I',f.read(4))[0]
            assert length < 100000
            name=f.read(length).rstrip(b'\0').decode('utf-8')
            offset,size=struct.unpack('<2Q',f.read(16)); md5=f.read(16).hex(); ef=struct.unpack('<I',f.read(4))[0]
            assert offset+base+size <= p.stat().st_size
            entries.append({'name':name,'offset':offset+base,'size':size,'md5':md5,'flags':ef})
        selected={}
        for e in entries:
            if e['name'] in ['assets/config/server.cfg','project.binary','addons/fate_server_signals/fate_server_signals.gdextension']:
                f.seek(e['offset']); data=f.read(e['size']); selected[e['name']]={'sha256':hashlib.sha256(data).hexdigest(),'text':data.decode('utf-8',errors='replace') if e['name']!='project.binary' else None}
    return {'version':version,'engine':[major,minor,patch],'flags':flags,'file_base':base,'directory_offset':directory,'count':count,'entries':entries,'selected':selected}

def datacompare(dest):
    src={str(p.relative_to(ROOT/'data')).replace('\\','/'):sha(p) for p in (ROOT/'data').rglob('*') if p.is_file() and p.suffix!='.import'}
    actual={str(p.relative_to(dest)).replace('\\','/'):sha(p) for p in dest.rglob('*') if p.is_file()}
    return {'expected_count':len(src),'actual_count':len(actual),'missing':sorted(src.keys()-actual.keys()),'extra':sorted(actual.keys()-src.keys()),'changed':sorted(k for k in src.keys() & actual.keys() if src[k]!=actual[k])}

result={'scope':'STATIC_ONLY','dynamic_status':'NOT_RUN','platforms':{},'source':[],'environment':{k:v for k,v in os.environ.items() if k.startswith('FATE_')},'signaling':{}}
for platform in ['windows','linux']:
    folder=DIST/platform
    pack=pck(folder/'FateServer.pck')
    (OUT/(platform+'-pck-index.json')).write_text(json.dumps(pack,ensure_ascii=False,indent=2),encoding='utf-8')
    result['platforms'][platform]={'top_files':[info(p) for p in folder.iterdir() if p.is_file()], 'data':datacompare(folder/'data'), 'pck_count':pack['count'],'pck_data':[e['name'] for e in pack['entries'] if e['name'].startswith('data/')],'pck_signals':[e['name'] for e in pack['entries'] if 'fate_server_signals' in e['name']], 'embedded_config':pack['selected'].get('assets/config/server.cfg')}
for relative in ['export_presets.cfg','project.godot','assets/config/server.cfg','scripts/net/server_cli.gd','scripts/net/server_bootstrap.gd','scripts/net/server_policy_config.gd','scripts/net/server_room_manager.gd','scripts/net/server_room_worker.gd','scripts/net/server_console.gd','scripts/net/server_process_signals.gd','scripts/net/server_shutdown.gd','scripts/system/global/load_helper.gd','addons/fate_server_signals/fate_server_signals.gdextension']:
    p=ROOT/relative
    if p.is_file(): result['source'].append(info(p))
for p in (ROOT/'addons/fate_server_signals/bin').glob('*'):
    if p.is_file(): result['source'].append(info(p))
stage=ROOT/'scratch/authority-worker-v2/signaling-project'
result['signaling']={'exists':stage.is_dir(),'files':[info(p) for p in stage.rglob('*') if p.is_file()], 'project':(stage/'project.godot').read_text(encoding='utf-8')}
(OUT/'static-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
for k,v in result['platforms'].items():
    print(k,'pck_files=',v['pck_count'],'pack_signals=',v['pck_signals'],'data=', {x:len(y) if isinstance(y,list) else y for x,y in v['data'].items()})
    print('EMBEDDED_CONFIG',v['embedded_config'])
print('FATE_ENV',result['environment'])
print('STATIC_INVENTORY_COMPLETE dynamic=NOT_RUN')
