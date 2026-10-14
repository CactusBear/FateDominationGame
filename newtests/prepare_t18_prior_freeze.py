"""Rehydrate a previously three-way verified freeze; never mix changed production bytes."""
import argparse, hashlib, json, shutil
from pathlib import Path
repo = Path(__file__).resolve().parents[1]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
ap = argparse.ArgumentParser()
ap.add_argument('--manifest', required=True)
ap.add_argument('--output', required=True)
a = ap.parse_args()
mp = Path(a.manifest)
m = json.loads(mp.read_text(encoding='utf-8'))
if m.get('source_after_copy_drift') != {}:
    raise ValueError('baseline did not pass source before/after copy verification')
archive = mp.parent / 'evidence/frozen-inputs'
out = Path(a.output)
if out.drive.upper() != 'E:' or out.exists(): raise ValueError('new E output required')
out.mkdir(parents=True)
records, missing = [], []
for name, expected in m['source_hashes'].items():
    if name in ['newtests/run_t18_scoreboard_network_window.py', 'newtests/t18_scoreboard_network_window_test.gd', 'newtests/t18_scoreboard_network_window_test.tscn']:
        continue
    p = Path(name)
    src = archive / p if (archive / p).is_file() else repo / p
    dst = out / p
    if not src.is_file():
        missing.append({'path':name,'reason':'missing'})
        continue
    b = src.read_bytes()
    if name == 'project.godot' and (repo / p).is_file() and sha(repo / p) == expected:
        b = (repo / p).read_bytes()
    elif name == 'project.godot':
        text = b.decode('utf-8-sig')
        for op in reversed(m['editor_transform']['operations']):
            if op['action'] == 'replace': text = text.replace(op['transformed'], op['original'], 1)
            else: text = text.replace('version_control/autoload_on_startup=true', op['original']+'\nversion_control/autoload_on_startup=true', 1)
        candidates = [text.encode('utf-8'), b'\xef\xbb\xbf'+text.encode('utf-8')]
        b = next((x for x in candidates if hashlib.sha256(x).hexdigest() == expected), b)
    h = hashlib.sha256(b).hexdigest()
    if h != expected:
        missing.append({'path':name,'reason':'hash mismatch','expected':expected,'actual':h})
        continue
    dst.parent.mkdir(parents=True,exist_ok=True)
    dst.write_bytes(b)
    if sha(dst) != expected: raise ValueError('destination hash mismatch')
    records.append({'path':name,'sha256':expected,'origin':str(src)})
receipt = {'baseline_manifest':str(mp),'baseline_manifest_sha256':sha(mp),'matched_files':len(records),'missing_or_changed':missing,'files':records,'test_overlay':[]}
if not missing:
    for name in ['newtests/t18_scoreboard_network_window_test.gd','newtests/t18_scoreboard_network_window_test.tscn','newtests/run_t18_scoreboard_network_window.py','newtests/prepare_t18_prior_freeze.py','newtests/t18_native_window_capture.py']:
        dst = out / name; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(repo / name,dst)
        receipt['test_overlay'].append({'path':name,'sha256':sha(dst)})
(out.parent / (out.name+'-receipt.json')).write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in receipt.items() if k != 'files'},ensure_ascii=False))
raise SystemExit(1 if missing else 0)
