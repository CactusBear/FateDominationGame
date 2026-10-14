"""统一 headless 测试入口：串行跑任意 tests/ newtests/ 场景，复用 analyze_logs 判定。

不强杀：每个场景带 --quit-after 帧上限；超出墙钟预算只记录 RETAINED_TIMEOUT 并停止后续启动。
用法:
  python tools/run_scenes.py <label> res://tests/a.tscn res://newtests/b.tscn ...
  python tools/run_scenes.py <label> --list scenes.txt      # 每行一个 res:// 路径
  python tools/run_scenes.py <label> --compare <old_label>  # 只打印相对旧结果的新增失败
环境变量: FATE_PROJECT（项目根，默认本仓库）、WALL（单场景墙钟秒，默认 420）、
          RUN_OUT（输出根，默认 <项目>/runtime_reports/runs）。
"""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
from run_refactor_headless_baseline import GODOT, analyze_logs  # noqa: E402

PROJECT = Path(os.environ.get('FATE_PROJECT', TOOLS.parent))
OUT = Path(os.environ.get('RUN_OUT', PROJECT / 'runtime_reports' / 'runs'))
WALL = int(os.environ.get('WALL', '420'))


def run(label, scenes, window=False):
    out = OUT / label
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for scene in scenes:
        name = scene.rsplit('/', 1)[-1].removesuffix('.tscn')
        cmd = [str(GODOT), '--fixed-fps', '60', '--quit-after', '36000', '--path', str(PROJECT), '--scene', scene]
        if not window:
            cmd.insert(1, '--headless')
        so, se = out / (name + '.out.log'), out / (name + '.err.log')
        start = time.monotonic()
        with so.open('wb') as a, se.open('wb') as b:
            p = subprocess.Popen(cmd, cwd=PROJECT, stdout=a, stderr=b)
            try:
                code = p.wait(timeout=WALL)
            except subprocess.TimeoutExpired:
                rows.append({'scene': name, 'status': 'RETAINED_TIMEOUT', 'pid': p.pid})
                print(json.dumps(rows[-1], ensure_ascii=False), flush=True)
                break
        ev = analyze_logs(so.read_bytes().decode('utf-8', 'replace'), se.read_bytes().decode('utf-8', 'replace'),
                          exit_code=code, timed_out=False)
        rows.append({'scene': name, 'status': ev['status'], 'exit': code, 'secs': round(time.monotonic() - start, 1),
                     'checks': ev['checks'], 'failures': [f for r in ev['parsed_results'] for f in r['failures']],
                     'reasons': ev['failure_reasons'], 'errors': ev['errors'][:6]})
        print(json.dumps(rows[-1], ensure_ascii=False), flush=True)
        (out / 'summary.json').write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding='utf-8')
    (out / 'summary.json').write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding='utf-8')
    print('PASS %d / %d' % (sum(r.get('status') == 'PASS' for r in rows), len(rows)))
    return rows


def compare(label, old_label):
    old = {r['scene']: r for r in json.loads((OUT / old_label / 'summary.json').read_text(encoding='utf-8'))}
    new = json.loads((OUT / label / 'summary.json').read_text(encoding='utf-8'))
    regressions = 0
    for r in new:
        o = old.get(r['scene'])
        if o is None:
            continue
        # 失败标签里可能带运行期实例 ID，比较前把长数字归一，避免同一失败被误报为新增。
        norm = lambda fs: {re.sub(r'-?\d{6,}', '#', f) for f in fs}
        added = sorted(norm(r.get('failures', [])) - norm(o.get('failures', [])))
        if (o['status'] == 'PASS' and r['status'] != 'PASS') or added:
            regressions += 1
            print('REGRESSION', r['scene'], o['status'], '->', r['status'], added[:5], r.get('errors', [])[:1])
    print('REGRESSIONS', regressions)
    return regressions


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    label, rest = argv[0], argv[1:]
    if rest[0] == '--compare':
        return 1 if compare(label, rest[1]) else 0
    window = '--window' in rest
    rest = [a for a in rest if a != '--window']
    if rest[0] == '--list':
        rest = [l.strip() for l in Path(rest[1]).read_text(encoding='utf-8').splitlines() if l.strip()]
    rows = run(label, rest, window)
    return 0 if rows and all(r.get('status') == 'PASS' for r in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
