"""Reuse the existing bounded E-drive/OwnedJob runner, only one GUI scene."""
import sys
sys.dont_write_bytecode = True
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
base = repo / 'newtests/run_round74_scoreboard.py'
source = base.read_text(encoding='utf-8')
replacements = [
    ("('round74-scoreboard-' + args.label)", "('round75-scoreboard-' + args.label)"),
    ("'boundary': 'headless logic only; no GUI, ENet, or performance claim'", "'boundary': 'single real window scoreboard button; Viewport.push_input GUI route; controlled session not ENet/OS hardware; no performance or full-UI claim'"),
    ("'newtests/round74_scoreboard_toggle_test.tscn', 'newtests/round74_scoreboard_toggle_test.gd']", "'newtests/round74_scoreboard_toggle_test.gd', 'newtests/round75_scoreboard_click_test.tscn', 'newtests/round75_scoreboard_click_test.gd', 'newtests/run_round75_scoreboard_click.py', 'newtests/run_round74_scoreboard.py']"),
    ("scenes = ['newtests/round74_scoreboard_toggle_test.tscn']", "scenes = ['newtests/round75_scoreboard_click_test.tscn']"),
    ("command = [str(engine),'--headless','--fixed-fps','60','--path',str(target),'--scene','res://'+scene]", "command = [str(engine),'--fixed-fps','60','--path',str(target),'--scene','res://'+scene,'--','window']"),
    ("m['source_drift'] =", "m['production_scope_hashes'] = {p:h for p,h in before.items() if p.startswith(('scripts/', 'assets/scenes/'))}\n        m['gui_input'] = [json.loads(line[9:]) for line in out.splitlines() if line.startswith('GUIINPUT ')]\n        m['visual'] = [json.loads(line[7:]) for line in out.splitlines() if line.startswith('VISUAL ')]\n        m['source_drift'] ="),
]
for old, new in replacements:
    if source.count(old) != 1:
        raise RuntimeError('bounded runner reuse anchor changed: ' + old)
    source = source.replace(old, new, 1)
namespace = {'__name__': '__main__', '__file__': str(Path(__file__).resolve())}
exec(compile(source, str(Path(__file__).resolve()), 'exec'), namespace)
