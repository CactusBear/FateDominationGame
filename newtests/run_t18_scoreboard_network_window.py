"""T18 only: inherit bounded E-drive freeze/OwnedJob window runner."""
import sys
sys.dont_write_bytecode = True
from pathlib import Path
repo = Path(__file__).resolve().parents[1]
source = (repo / 'newtests/run_round74_scoreboard.py').read_text(encoding='utf-8')
replacements = [
    ("e = load('r74_transform', REPO / 'tools/tests/test_round29_integrated_evidence.py')", "e = load('r74_transform', REPO / 'tools/tests/test_round29_integrated_evidence.py')\nnative = load('t18_native', REPO / 'newtests/t18_native_window_capture.py')\nr.execute = native.wrap_execute(r.execute)"),
    ("('round74-scoreboard-' + args.label)", "('t18-scoreboard-' + args.label)"),
    ("'boundary': 'headless logic only; no GUI, ENet, or performance claim'", "'boundary': 'one actual non-headless window; GUI push_input and controlled real Session receiver; NOT ENet/OS hardware/multi-machine'"),
    ("'newtests/round74_scoreboard_toggle_test.tscn', 'newtests/round74_scoreboard_toggle_test.gd']", "'newtests/round74_scoreboard_toggle_test.gd', 'newtests/round75_scoreboard_click_test.gd', 'newtests/t18_scoreboard_network_window_test.gd', 'newtests/t18_scoreboard_network_window_test.tscn', 'newtests/run_t18_scoreboard_network_window.py', 'newtests/t18_native_window_capture.py', 'newtests/run_round74_scoreboard.py']"),
    ("scenes = ['newtests/round74_scoreboard_toggle_test.tscn']", "scenes = ['newtests/t18_scoreboard_network_window_test.tscn']"),
    ("command = [str(engine),'--headless','--fixed-fps','60','--path',str(target),'--scene','res://'+scene]", "command = [str(engine),'--fixed-fps','60','--path',str(target),'--scene','res://'+scene,'--','window'] + (['empty-edge'] if args.empty_edge else [])"),
    ("m['source_hashes'] = before", "m['source_hashes'] = before\n        m['source_after_copy_drift'] = {p.as_posix():[before[p.as_posix()],sha(REPO / p)] for p in files if sha(REPO / p) != before[p.as_posix()]}\n        if m['source_after_copy_drift']: raise ValueError('source changed during copy')"),
    ("ap.add_argument('--label', required=True)", "ap.add_argument('--label', required=True)\n    ap.add_argument('--source-root', help='explicit verified prior freeze with current test overlay')\n    ap.add_argument('--empty-edge', action='store_true', help='retain legal zero-player transition diagnostic')"),
    ("args = ap.parse_args()", "args = ap.parse_args()\n    INPUT_ROOT = r.physical_e(args.source_root) if args.source_root else REPO"),
    ("r.source_files(REPO, includes)", "r.source_files(INPUT_ROOT, includes)"),
    ("m['error'] = repr(exc)", "m['error'] = repr(exc)\n        (root / 'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')"),
    ("if p.suffix in {'.gd','.tscn','.godot','.gdextension'}:", "if p.suffix in {'.gd','.tscn','.godot','.gdextension'} and (target / p).is_file():"),
    ("m['source_drift'] =", "m['gui_input'] = [json.loads(line[9:]) for line in out.splitlines() if line.startswith('GUIINPUT ')]\n        m['visual'] = [json.loads(line[7:]) for line in out.splitlines() if line.startswith('VISUAL ')]\n        m['production_scope_hashes'] = {p:h for p,h in before.items() if p.startswith(('scripts/', 'assets/scenes/'))}\n        m['source_drift'] ="),
]
for old, new in replacements:
    if source.count(old) != 1:
        raise RuntimeError('runner reuse anchor changed: ' + old)
    source = source.replace(old, new, 1)
source = source.replace('REPO / p', 'INPUT_ROOT / p')
namespace = {'__name__':'__main__', '__file__':str(Path(__file__).resolve())}
exec(compile(source, str(Path(__file__).resolve()), 'exec'), namespace)
