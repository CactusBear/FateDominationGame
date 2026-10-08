"""Third-party syntax parser; not a Godot compiler/runtime check."""
from pathlib import Path
import json
from gdtoolkit.parser import parser

root = Path(__file__).resolve().parents[2]
results = []
for name in ['p2p_signal_client.gd', 'p2p_signal_server.gd', 'p2p_invite.gd']:
    path = root / 'scripts/net/p2p' / name
    parser.parse(path.read_text(encoding='utf-8'))
    results.append({'file': path.relative_to(root).as_posix(), 'parsed': True})
    print('PARSE OK', path.relative_to(root).as_posix())
Path(__file__).with_name('parser-results.json').write_text(json.dumps({'scope': 'gdtoolkit syntax only; no Godot type/API validation', 'results': results}, indent=2), encoding='utf-8')
