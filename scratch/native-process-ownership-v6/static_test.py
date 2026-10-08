from pathlib import Path
import hashlib
import json
import re
from gdtoolkit.parser import parser

out = Path(__file__).resolve().parent
root = out.parents[1]
manifest = json.loads((out / 'manifest.json').read_text(encoding='utf-8'))
for relative, record in manifest.items():
    assert hashlib.sha256((out / 'overlay' / relative).read_bytes()).hexdigest() == record['overlay_sha256']
    if relative.endswith('.gd'):
        parser.parse((out / 'overlay' / relative).read_text(encoding='utf-8'))
    if record['baseline_sha256']:
        assert hashlib.sha256((root / relative).read_bytes()).hexdigest() == record['baseline_sha256'], relative
manager = (out / 'overlay/scripts/net/server/server_room_manager.gd').read_text(encoding='utf-8')
parser.parse(manager)
for forbidden in ['OS.create_process', 'OS.kill', 'OS.is_process_running', 'process_identity_verifier']:
    assert forbidden not in manager, forbidden
assert manager.count('_process_owner.call("spawn"') == 2
assert 'room.process_token = spawned.token' in manager
assert '"process_token":spawned.token' in manager
assert 'if previous_state != 0:' in manager
assert 'if room.error.is_empty() and _process_state(room) == 1: _write_supervisor(room)' in manager
assert 'not _terminate_process(rooms[id]) or not _release_process(rooms[id])' in manager
core = (out / 'overlay/addons/fate_server_signals/src/process_owner_core.cpp').read_text(encoding='utf-8')
assert not re.search(r'\b(kill|waitpid|OpenProcess)\s*\(', re.sub(r'//[^\n]*', '', core))
assert 'options.flags = CLONE_PIDFD' in core
assert 'send(gate[1], &permission, 1, MSG_NOSIGNAL)' in core
assert 'send_pidfd(fd, SIGKILL)' in core
assert 'CreateProcessW(' in core and 'TerminateProcess(handle, 1)' in core
assert 'entry->second.pid != pid' in core
assert 'inspect(entry->second) != EXITED' in core
signals = (out / 'overlay/addons/fate_server_signals/src/server_signals.cpp').read_text(encoding='utf-8')
assert 'register_fate_process_owner();' in signals
print(f'PASS static: GDScript syntax, {len(manifest)}-file manifest, unchanged production baselines, no PID-only lifecycle, atomic clone3 identity, ownership bindings')
