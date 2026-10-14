"""Read only completed Job0 evidence; emit exact-schema views, never raw payloads.
Does not rerun the worker or alter the original manifest/logs. argv: owned evidence root.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('isolation',REPO/'tools/run_isolated_godot_test.py')
isolation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(isolation)
owner = isolation.physical_e(sys.argv[1])
manifest = json.loads((owner/'manifest.json').read_text(encoding='utf-8'))
if owner.name != 'isolated-'+manifest['run_id'] or manifest['owner'] != str(owner):
    raise ValueError('ownership mismatch')
if not manifest['processes'] or any(not p.get('exited') or p.get('active_owned_processes') != 0 or not p.get('log_handles_released') for p in manifest['processes']):
    raise ValueError('Job0/log release not proven')
evidence = owner/'evidence'
stdout = (evidence/'test.stdout.log').read_text(encoding='utf-8')
stderr = (evidence/'test.stderr.log').read_text(encoding='utf-8')
worker = (evidence/'worker-engine.log').read_text(encoding='utf-8')
result = isolation.analyze(stdout,stderr,manifest['results']['test']['exit'])
# Exact-schema allowlist projection is a new view, not a replacement for the raw log.
views = {}
for label,prefix,text in [('boundary','TEST_CHAIN_STAGE',stdout),('startup','SERVER_ROOM_STARTUP',worker)]:
    selected = [line for line in text.splitlines() if line.startswith(prefix+' ')]
    regex = re.compile(r'^'+prefix+r' stage=([a-z_]+) result=(-1|0|1)$')
    if not selected or any(not regex.fullmatch(line) for line in selected):
        raise ValueError('unsafe/missing stage schema')
    path = evidence/(label+'-stages.log')
    payload = ('\n'.join(selected)+'\n').encode('utf-8')
    if path.exists() and path.read_bytes()!=payload:
        raise ValueError('refusing to overwrite a divergent projection')
    if not path.exists():
        path.write_bytes(payload)
    views[label] = {'path':str(path),'lines':len(selected),'sha256':hashlib.sha256(payload).hexdigest()}
source_drift = [rel for rel,digest in manifest['source_sha256'].items() if hashlib.sha256((REPO/rel).read_bytes()).hexdigest()!=digest]
frozen_mismatches = [rel for rel,digest in manifest['source_sha256'].items() if rel!='project.godot' and hashlib.sha256((Path(manifest['project'])/rel).read_bytes()).hexdigest()!=digest]
checks = [line for line in stdout.splitlines() if line.startswith('CHECK ')]
summary = {'views':views,'actual_CHECK_count':len(checks),'CHECK_true':sum(line.startswith('CHECK true ') for line in checks),
           'CHECK_false':sum(line.startswith('CHECK false ') for line in checks),'exit':manifest['results']['test']['exit'],
           'analysis':result,'ERROR_count':sum(bool(re.search(r'SCRIPT ERROR|SHADER ERROR|^\s*ERROR:',line)) for line in (stdout+'\n'+stderr+'\n'+worker).splitlines()),
           'Job0':True,'source_drift':source_drift,'frozen_input_mismatches':frozen_mismatches,'save_restore_passed':False}
print(json.dumps(summary,ensure_ascii=False,indent=2))
sys.exit(0 if not frozen_mismatches and len(checks)==result['result']['checks'] else 1)
