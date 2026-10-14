"""One real-window acceptance run; reuse audited E-drive OwnedJob runner."""
import sys
sys.dont_write_bytecode = True
from pathlib import Path
repo = Path(__file__).resolve().parents[1]
source = (repo / 'newtests/run_round74_scoreboard.py').read_text(encoding='utf-8')
changes = [
    ("('round74-scoreboard-' + args.label)", "('round75-order-resources-' + args.label)"),
    ("'seconds': 180", "'seconds': 600"),
    ("'boundary': 'headless logic only; no GUI, ENet, or performance claim'", "'boundary': 'single Viewport.push_input real window; formal LobbySession snapshot receive and normal process refresh; no ENet/hardware/full-suite/performance claim'"),
    ("'newtests/round74_scoreboard_toggle_test.tscn', 'newtests/round74_scoreboard_toggle_test.gd']", "'newtests/round75_order_resources_window_test.tscn', 'newtests/round75_order_resources_window_test.gd', 'newtests/run_round75_order_resources_window.py']"),
    ("scenes = ['newtests/round74_scoreboard_toggle_test.tscn']", "scenes = ['newtests/round75_order_resources_window_test.tscn']"),
    ("command = [str(engine),'--headless','--fixed-fps','60','--path',str(target),'--scene','res://'+scene]", "command = [str(engine),'--fixed-fps','60','--path',str(target),'--scene','res://'+scene,'--','window']"),
    ("m['source_drift'] =", "m['gui_input'] = [json.loads(line[9:]) for line in out.splitlines() if line.startswith('GUIINPUT ')]\n        m['visual'] = [json.loads(line[7:]) for line in out.splitlines() if line.startswith('VISUAL ')]\n        m['source_drift'] ="),
]
# Complete the repository -> generated transfer before verifying or archiving.
# The old per-file drift exception could stop midway, then finally masked it
# by archiving an uncopied dependency. Keep the original failure explicit.
changes.extend([
    ("if sha(dest) != before[p.as_posix()]: raise ValueError('freeze drift: ' + str(p))", "# Verify only after every explicit dependency has been copied."),
    ("m['source_hashes'] = before", "m['source_hashes'] = before\n        missing = [p.as_posix() for p in files if not (target / p).is_file()]\n        if missing: raise FileNotFoundError('generated dependencies missing: ' + json.dumps(missing))\n        m['freeze_copy_complete'] = True\n        drift = [p.as_posix() for p in files if sha(target / p) != before[p.as_posix()]]\n        if drift: raise ValueError('repository changed during freeze copy: ' + json.dumps(drift))"),
    ("m['error'] = repr(exc)", "m['error'] = repr(exc)\n        print('ORIGINAL_RUNNER_ERROR ' + repr(exc), flush=True)"),
    ("for p in files:\n            if p.suffix", "if not m.get('freeze_copy_complete', False):\n            m['archive_blocked_incomplete_freeze'] = [p.as_posix() for p in files if not (target / p).is_file()]\n        for p in (files if m.get('freeze_copy_complete', False) else []):\n            if p.suffix"),
])
for old,new in changes:
    if source.count(old) != 1: raise RuntimeError('runner anchor changed: '+old)
    source = source.replace(old,new,1)
exec(compile(source,str(Path(__file__).resolve()),'exec'), {'__name__':'__main__','__file__':str(Path(__file__).resolve())})
