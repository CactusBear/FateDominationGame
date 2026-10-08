"""只读审计，不运行 Godot，不调用被审计脚本的 main。"""
import importlib.util
import json
from pathlib import Path
ROOT = Path('E:/Projects/Godot/FateDominationGame-master')
RUNNER = Path('C:/Users/Administrator/AppData/Local/hermes/skills/software-development/fate-domination-engine/scripts/run_all_tests.py')
spec = importlib.util.spec_from_file_location('audited_runner', RUNNER)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
fixtures = ['RESULT checks=2 failures=1 [bad]', 'RESULT checks=2', 'RESULT checks=0 failures=[] window_only=true', 'RESULT {"checks":2,"failures":1}', 'RESULT checks=1 failures=[bad]\nRESULT checks=1 failures=[]', 'RESULT arbitrary']
rows = []
for text in fixtures:
    lines = runner.RESULT_RE.findall(text)
    result = lines[-1] if lines else None
    match = runner.FAIL_RE.search(result) if result else None
    failures = [x for x in (match.group(1).split(',') if match else []) if x.strip()] if result else None
    accepted = not (0 != 0 or runner.ERROR_RE.findall(text) or result is None or failures)
    rows.append({'synthetic_not_runtime': True, 'input': text, 'legacy_accepts': accepted})
scenes = sorted((ROOT/'tests').glob('*_test.tscn'))
output = {'scope':'STATIC_AND_SYNTHETIC_ONLY', 'runner':str(RUNNER), 'fixtures': rows, 'top_level_scene_count':len(scenes), 'nested_scenes_excluded_by_runner':[str(p.relative_to(ROOT)) for p in (ROOT/'tests').rglob('*_test.tscn') if p.parent != ROOT/'tests']}
for name, collection in [('lan_matrix.json','cases'), ('cross_network_matrix.json','tasks')]:
    data = json.loads((ROOT/'tests/real_world_acceptance_v5'/name).read_text(encoding='utf-8-sig'))
    output[name] = {'count':len(data[collection]), 'statuses':{s:sum(x['status']==s for x in data[collection]) for s in sorted({x['status'] for x in data[collection]})}}
Path(__file__).with_name('audit-output.json').write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(output,ensure_ascii=False,indent=2))
