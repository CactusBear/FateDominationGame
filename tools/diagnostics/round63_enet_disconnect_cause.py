"""Read-only ENet cause preflight. Never starts/attaches/debugs a game process.

Preserves source/trace hashes; no packet payload, keys, tickets, setters or RVA guesses.
Exit 2 means native-cause capture is blocked, never a product/source PASS.
"""
from __future__ import annotations
import sys
sys.dont_write_bytecode = True
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import urllib.request

PROJECT = Path(__file__).resolve().parents[2]
ENGINE_SHA = 'ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424'
SOURCES = [
    'modules/enet/enet_packet_peer.cpp', 'modules/enet/enet_packet_peer.h',
    'modules/enet/enet_connection.cpp', 'modules/enet/enet_multiplayer_peer.cpp',
    'modules/enet/doc_classes/ENetPacketPeer.xml',
    'thirdparty/enet/protocol.c', 'thirdparty/enet/peer.c',
    'thirdparty/enet/enet/enet.h', 'thirdparty/enet/enet/protocol.h',
]
READONLY = [
    'scripts/net/transport/enet_transport.gd',
    'scripts/net/transport/recovery_net_probe.gd',
    'scripts/net/server/server_gateway.gd',
    'scripts/net/server/server_room_worker.gd',
    'scripts/net/session/lobby_session.gd',
    'scripts/net/validation/room_data_validation_worker.gd',
    'scripts/system/global/load_game.gd',
    'tests/net_process_full_game_test.gd',
    'tools/diagnostics/native_cold_import_debug.py',
]

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def checked(path, root):
    path, root = Path(path).resolve(), Path(root).resolve()
    if not path.is_relative_to(root):
        raise ValueError('path escaped approved root')
    for part in [path, *path.parents]:
        if part.is_symlink() or part.is_junction():
            raise ValueError('link/junction refused')
        if part == root:
            break
    return path

def pe_metadata(path):
    b = path.read_bytes()
    if b[:2] != b'MZ':
        raise ValueError('not PE')
    pe = struct.unpack_from('<I', b, 60)[0]
    if b[pe:pe+4] != b'PE\0\0':
        raise ValueError('invalid PE')
    machine, count, timestamp, symbols, nsyms, optsize, flags = struct.unpack_from('<HHIIIHH', b, pe+4)
    optional = pe+24
    if struct.unpack_from('<H', b, optional)[0] != 0x20b:
        raise ValueError('requires PE32+')
    sections = []
    for i in range(count):
        pos = optional+optsize+i*40
        name = b[pos:pos+8].rstrip(b'\0').decode('ascii', 'replace')
        vsize, va, rawsize, raw = struct.unpack_from('<IIII', b, pos+8)
        sections.append((name, va, vsize, raw, rawsize))
    def offset(rva):
        for _, va, vsize, raw, rawsize in sections:
            if va <= rva < va+max(vsize, rawsize):
                return raw+rva-va
        raise ValueError('unmapped PE directory')
    export_rva, export_size = struct.unpack_from('<II', b, optional+112)
    debug_rva, debug_size = struct.unpack_from('<II', b, optional+112+6*8)
    names = []
    if export_rva:
        pos = offset(export_rva)
        n = struct.unpack_from('<I', b, pos+24)[0]
        table = offset(struct.unpack_from('<I', b, pos+32)[0])
        for i in range(n):
            start = offset(struct.unpack_from('<I', b, table+i*4)[0])
            names.append(b[start:b.index(b'\0',start)].decode('ascii','replace'))
    debug_entries = []
    if debug_rva:
        pos = offset(debug_rva)
        for i in range(debug_size//28):
            row = struct.unpack_from('<IIHHIIII', b, pos+28*i)
            debug_entries.append({'type':row[4], 'bytes':row[5]})
    return {'machine':hex(machine),'timestamp':timestamp,'coff_symbol_count':nsyms,
            'debug_directory_rva':debug_rva,'debug_directory_bytes':debug_size,
            'debug_entries':debug_entries,'sections':[x[0] for x in sections],
            'export_count':len(names),'enet_exports':[n for n in names if 'enet' in n.lower()],
            'export_directory_bytes':export_size,
            'incidental_RSDS_string_is_not_codeview_record':not bool(debug_rva)}

def fetch(url, destination):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent':'Fate-readonly-diagnostic'}), timeout=20) as response:
            body = response.read()
            status = response.status
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(body)
        return {'url':url,'status':status,'bytes':len(body),'sha256':sha(destination),
                'path':destination.as_posix()}
    except Exception as exc:
        return {'url':url,'error':str(exc)}

def archived_events(path):
    rows = []
    for line_no, line in enumerate(path.read_text(encoding='utf-8').splitlines(),1):
        # Do not decode archived business-message payloads.
        if re.search(r'"signal"\s*:\s*"message_received"', line):
            continue
        value = json.loads(line)
        raw = value.get('raw_nonsecret',{})
        if not raw.get('stack') and value.get('event_seq') not in [108,109,114,115]:
            continue
        row = {k:value[k] for k in ['event_seq','stage','signal','client','ticks_usec','ticks_msec','pid'] if k in value}
        row['archive_line'] = line_no
        row['stack'] = [{k:f[k] for k in ['function','line','source'] if k in f} for f in raw.get('stack',[])]
        row['identity'] = {k:value.get('causal',{})[k] for k in ['external_peer','internal_peer','member','native_instance','generation','room','request'] if k in value.get('causal',{})}
        binding = raw.get('binding',{})
        row['binding'] = {k:binding[k] for k in ['external_peer','internal_peer','room','worker_pid','instance_id'] if k in binding}
        rows.append(row)
    return rows

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--engine', type=Path, required=True)
    args = parser.parse_args(argv)
    root = checked(args.root, Path('E:/scratch'))
    if root.exists():
        raise ValueError('requires fresh E:/scratch owned evidence root')
    archive = checked(args.archive, Path('E:/scratch'))
    engine = args.engine.resolve()
    if sha(engine) != ENGINE_SHA:
        raise ValueError('exact engine identity required')
    manifest_path = archive/'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    if manifest['engine_sha256'] != ENGINE_SHA:
        raise ValueError('archive engine differs')
    artifact_checks = [sha(checked(archive/'evidence'/row['path'],archive)) == row['sha256'] for row in manifest['artifact_index']]
    if not all(artifact_checks):
        raise ValueError('original artifact hash mismatch')
    if not all(p.get('exited') is True and p.get('active_owned_processes') == 0 and p.get('log_handles_released') is True for p in manifest['processes']):
        raise ValueError('original Job0 not proven')
    before = {name:sha(PROJECT/name) for name in READONLY}
    def observe_tree():
        return {name:sha(PROJECT/name) if (PROJECT/name).is_file() else None
                for name in manifest['source_end_hashes']}
    tree_before = observe_tree()
    root.mkdir()
    (root/'executor.py').write_bytes(Path(__file__).read_bytes())
    version = subprocess.run([str(engine),'--version'],capture_output=True,timeout=20)
    (root/'engine-version.stdout.log').write_bytes(version.stdout)
    (root/'engine-version.stderr.log').write_bytes(version.stderr)
    text = version.stdout.decode('utf-8','replace').strip()
    match = re.fullmatch(r'4\.7\.2\.stable\.official\.([0-9a-f]{9})', text)
    if version.returncode or not match:
        raise ValueError('unrecognized actual engine version')
    commit = match[1]
    tag_command = ['git','ls-remote','https://github.com/godotengine/godot.git','refs/tags/4.7.2-stable']
    tag = subprocess.run(tag_command,capture_output=True,timeout=30)
    (root/'official-tag.stdout.log').write_bytes(tag.stdout)
    (root/'official-tag.stderr.log').write_bytes(tag.stderr)
    full = re.fullmatch(rb'([0-9a-f]{40})\s+refs/tags/4\.7\.2-stable\s*',tag.stdout)
    if tag.returncode == 0 and full and full[1].decode().startswith(commit):
        commit = full[1].decode()
    else:
        raise ValueError('official tag failed to bind engine version hash')
    requests = [(f'https://raw.githubusercontent.com/godotengine/godot/{commit}/{name}',root/'source'/name) for name in SOURCES]
    requests += [('https://github.com/godotengine/godot-builds/releases/expanded_assets/4.7.2-stable',root/'official-release-assets.html')]
    with ThreadPoolExecutor(max_workers=4) as pool:
        downloads = list(pool.map(lambda pair:fetch(*pair),requests))
    listing = root/'official-release-assets.html'
    assets = re.findall(r'href="([^"]+/releases/download/[^"]+)"',listing.read_text(encoding='utf-8')) if listing.exists() else []
    peer_source = root/'source/modules/enet/enet_packet_peer.cpp'
    source_text = peer_source.read_text(encoding='utf-8') if peer_source.exists() else ''
    methods = re.findall(r'ClassDB::bind_method\(D_METHOD\("([^"]+)"',source_text)
    stats = re.findall(r'BIND_ENUM_CONSTANT\((PEER_[A-Z_]+)\)',source_text)
    metadata = pe_metadata(engine)
    local_symbols = [p.name for p in engine.parent.iterdir() if p.suffix.lower() in ['.pdb','.debug','.sym','.map']]
    report = {'status':'TOOLBLOCK_MISSING_NATIVE_FIELD_AND_VERIFIED_ENET_ADDRESS_MAP',
        'sourcePASS':False,'releasePASS':False,'new_save_recover_runs':0,
        'new_owned_game_processes':0,'debug_attach_calls':0,'packet_capture':False,
        'engine':{'path':engine.as_posix(),'sha256':sha(engine),'version':text,'version_exit':version.returncode,'PE':metadata,'local_symbols':local_symbols},
        'source_commit_selector':commit,'source_selector_is_not_native_address_mapping':True,
        'official_tag_command':tag_command,'official_tag_exit':tag.returncode,
        'analysis_inputs':'original immutable evidence/frozen-inputs and exact official source; current repository is drift observation only, never executed as a game',
        'executor_sha256':sha(root/'executor.py'),
        'source_tree_observation_before':tree_before,
        'source_tree_observation_after':observe_tree(),
        'outside_readonly_original_drift':[{'path':n,'original':manifest['source_end_hashes'][n],'observed':h} for n,h in tree_before.items() if n not in READONLY and h != manifest['source_end_hashes'][n]],
        'downloads':downloads,'release_assets':assets,
        'official_windows_symbol_assets':[a for a in assets if ('symbol' in a.lower() or '.pdb' in a.lower()) and ('win' in a.lower())],
        'api_readonly_methods':[m for m in methods if m.startswith('get_') or m.startswith('is_')],
        'api_statistics':stats,
        'missing_native_fields':['disconnect_origin_same_thread_stack','ENetHost_identity_and_serviceTime','ENetPeer_identity_and_address','timeoutLimit','timeoutMinimum','timeoutMaximum','lastReceiveTime','lastSendTime','earliestTimeout','nextTimeout','sentReliableCommands_ack_state','actual_disconnect_command_type'],
        'original':{'archive':archive.as_posix(),'manifest_sha256':sha(manifest_path),'artifact_count':len(artifact_checks),'all_artifact_hashes_match':all(artifact_checks),'generated_exists':(archive/'generated').exists(),'cleanup':manifest.get('cleanup'),
            'jobs':[{k:p.get(k) for k in ['pid','exit_code','exited','active_owned_processes','log_handles_released']} for p in manifest['processes']]},
        'archived_script_stacks_not_native_breakpoints':archived_events(archive/'evidence/net_server_gateway_restart_test/agent-events.jsonl'),
        'readonly_source_hashes_before':before,
        'current_vs_original_freeze':{n:{'current':before[n],'original':manifest['source_end_hashes'].get(n),'matches':before[n]==manifest['source_end_hashes'].get(n)} for n in READONLY if n in manifest['source_end_hashes']},
        'readonly_source_hashes_after':{n:sha(PROJECT/n) for n in READONLY},
        'limits':['No ENet native address is guessed or installed as breakpoint.','No memory dump or business message decoding.','No production change, target/seed/budget change, or scene rerun.','Existing debugger DEBUG_ONLY_THIS_PROCESS does not trace worker descendants; historical teardown RVAs are unrelated.']}
    report['readonly_unchanged'] = report['readonly_source_hashes_before'] == report['readonly_source_hashes_after']
    report['source_tree_drift_during_observation'] = [{'path':n,'before':h,'after':report['source_tree_observation_after'][n]} for n,h in tree_before.items() if h != report['source_tree_observation_after'][n]]
    report['original_manifest_unchanged'] = sha(manifest_path) == report['original']['manifest_sha256']
    report['original_artifacts_readback_after'] = all(sha(checked(archive/'evidence'/row['path'],archive)) == row['sha256'] for row in manifest['artifact_index'])
    out = root/'report.json'
    out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    if json.loads(out.read_text(encoding='utf-8')) != report:
        raise ValueError('report readback failed')
    print(json.dumps({'report':out.as_posix(),'sha256':sha(out),'status':report['status'],
        'downloads_ok':sum('sha256' in d for d in downloads),'downloads_total':len(downloads),
        'artifact_count':len(artifact_checks),'readonly_unchanged':report['readonly_unchanged'],
        'new_save_recover_runs':0,'sourcePASS':False},ensure_ascii=False))
    return 2

if __name__ == '__main__':
    sys.exit(main())
