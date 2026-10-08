"""Build a rule-free signaling project snapshot; never starts Godot."""
from pathlib import Path
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / 'signaling-project'
FILES = [
    'scripts/net/server_bootstrap.gd',
    'scripts/net/server_process_signals.gd',
    'scripts/net/p2p_signal_server.gd',
    'scripts/net/p2p_invite.gd',
    'scripts/net/webrtc_link.gd',
    'assets/scenes/main_menu/server_bootstrap.tscn',
    'addons/fate_server_signals/fate_server_signals.gdextension',
    'addons/fate_server_signals/bin/libfate_server_signals.windows.x86_64.dll',
    'addons/fate_server_signals/bin/libfate_server_signals.linux.x86_64.so',
]
# The snapshot has no gameplay autoload and only the explicit signaling load closure.
for name in FILES:
    source = ROOT / name
    if not source.is_file():
        raise FileNotFoundError(source)
    if source.suffix == '.gd':
        text = source.read_text(encoding='utf-8')
        for path in re.findall(r'(?:preload|load)\("res://([^\"]+)"\)', text):
            if path not in FILES:
                raise AssertionError(f'Unlisted dependency {name}: {path}')
config = (Path(__file__).resolve().parent / 'project.signaling.godot').read_text(encoding='utf-8')
assert '\n[autoload]\n' not in config
for name in FILES:
    target = OUT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / name, target)
(OUT / 'project.godot').write_text(config, encoding='utf-8')
(OUT / 'relay.json').write_text(json.dumps({'roles':['relay'],'port':53000,'bind_address':'127.0.0.1','max_clients':96,'max_rooms':16,'relay':{}}, indent=2), encoding='utf-8')
manifest = {name: hashlib.sha256((OUT / name).read_bytes()).hexdigest() for name in FILES}
(OUT / 'staging-manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print(f'SIGNALING_PROJECT_STAGED files={len(FILES)} gameplay_autoload=0 rules_authority_scripts=0 output={OUT}')
