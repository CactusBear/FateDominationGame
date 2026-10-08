"""Source-contract checks only; never execute Godot or model game rules."""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
MANAGER = ROOT / 'scripts/net/server/server_room_manager.gd'
HOST = ROOT / 'scripts/net/session/authority_host_client.gd'
OUT = Path(__file__).parent


def body(source, name):
    match = re.search(r'^func ' + re.escape(name) + r'\([^\n]*\)[^\n]*:\n(.*?)(?=^(?:static )?func |\Z)', source, re.M | re.S)
    assert match, name
    return match.group(1)


def checks(manager, host):
    results = {}
    capability = body(manager, 'process_ownership_available')
    lines = [line.strip() for line in capability.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    results['no_native_backend_no_bool_callback_bypass'] = lines == ['return false']
    verify = body(manager, 'process_identity_verified')
    results['ownership_gate_before_verifier'] = verify.index('if not process_ownership_available():') < verify.index('process_identity_verifier.call') and 'return false' in verify.split('process_identity_verifier.call')[0]
    results['verifier_strict_bool'] = 'return verified is bool and verified' in verify
    results['no_pid_or_ready_as_os_proof'] = 'OS.is_process_running' not in verify and 'ready' not in verify
    for name, effect in [('create_room', 'RecoveryPaths.checked'), ('recover_room', 'rooms.has')]:
        text = body(manager, name)
        prefix = text.split(effect)[0]
        results[name + '_reject_before_side_effects'] = 'if not process_ownership_available():' in prefix and 'error = PROCESS_OWNERSHIP_UNAVAILABLE' in prefix and 'return ' in prefix
    poll = body(manager, 'poll')
    prefix = poll.split('Time.get_ticks_msec()')[0]
    results['poll_reject_before_heartbeat_ready_or_kill'] = 'if not process_ownership_available():' in prefix and 'room.ready = false' in prefix and 'room.error = PROCESS_OWNERSHIP_UNAVAILABLE' in prefix and '\t\treturn' in prefix
    stop = body(manager, 'stop_room').split('OS.is_process_running')[0]
    results['stop_no_unverified_pid_kill'] = 'if pid > 0 and not process_ownership_available():' in stop and 'return false' in stop.split('if pid > 0 and not process_ownership_available():')[1]
    notify = body(manager, '_notification')
    results['destructor_no_unverified_pid_kill'] = 'if not process_ownership_available(): return' in notify.split('rooms.values()')[0]
    start = body(host, 'start')
    results['lan_p2p_reject_before_listener_and_peer_takeover'] = 'if not gateway.manager.process_ownership_available():' in start.split('_name = name')[0] and 'return ERR_UNAVAILABLE' in start.split('_name = name')[0]
    results['error_is_explicit'] = 'const PROCESS_OWNERSHIP_UNAVAILABLE:String' in manager and '原生工作进程所有权验证不可用' in manager
    return results


def main():
    manager = MANAGER.read_text(encoding='utf-8')
    host = HOST.read_text(encoding='utf-8')
    result = checks(manager, host)
    mutations = {
        'fake_true_callback_or_capability': (manager.replace('func process_ownership_available() -> bool:\n\treturn false', 'func process_ownership_available() -> bool:\n\treturn true'), host),
        'pid_liveness_as_proof': (manager.replace('return verified is bool and verified', 'return OS.is_process_running(binding.pid)'), host),
        'ready_self_report_as_proof': (manager.replace('return verified is bool and verified', 'return binding.get("ready", false)'), host),
        'non_bool_verifier_success': (manager.replace('return verified is bool and verified', 'return bool(verified)'), host),
        'create_without_capability_gate': (manager.replace('func create_room(name: String, settings: Dictionary, data_root: String) -> String:\n\terror = ""\n\tif not process_ownership_available():\n\t\terror = PROCESS_OWNERSHIP_UNAVAILABLE\n\t\treturn ""', 'func create_room(name: String, settings: Dictionary, data_root: String) -> String:\n\terror = ""'), host),
        'recover_without_capability_gate': (manager.replace('func recover_room(id:String, expected_pid:int = -2, expected_instance_id:String = "") -> bool:\n\terror = ""\n\tif not process_ownership_available():\n\t\terror = PROCESS_OWNERSHIP_UNAVAILABLE\n\t\treturn false', 'func recover_room(id:String, expected_pid:int = -2, expected_instance_id:String = "") -> bool:\n\terror = ""'), host),
        'poll_fake_green': (manager.replace('room.ready = false\n\t\t\troom.error = PROCESS_OWNERSHIP_UNAVAILABLE', 'room.ready = true\n\t\t\troom.error = PROCESS_OWNERSHIP_UNAVAILABLE'), host),
        'destructor_pid_kill': (manager.replace('\t\tif not process_ownership_available(): return\n', ''), host),
        'host_infinite_wait': (manager, host.replace('\tif not gateway.manager.process_ownership_available():\n\t\terror = gateway.manager.PROCESS_OWNERSHIP_UNAVAILABLE\n\t\treturn ERR_UNAVAILABLE\n', '')),
    }
    rejected = {}
    for name, (mut_manager, mut_host) in mutations.items():
        assert (mut_manager, mut_host) != (manager, host), 'mutation did not apply: ' + name
        try:
            findings = checks(mut_manager, mut_host)
            rejected[name] = [key for key, ok in findings.items() if not ok]
        except (AssertionError, ValueError) as exc:
            rejected[name] = [str(exc)]
        assert rejected[name], 'mutation escaped: ' + name
    evidence = {'scope': 'Static source contracts and in-memory mutations; no Godot/native runtime execution', 'checks': result, 'checks_passed': sum(result.values()), 'checks_total': len(result), 'mutations_rejected': rejected, 'mutation_count': len(rejected)}
    (OUT / 'static_evidence.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(evidence, ensure_ascii=False, indent=2))
    assert all(result.values())
    try:
        from gdtoolkit.parser import parser
    except ImportError:
        print('gdtoolkit unavailable in this interpreter', file=sys.stderr)
        return 2
    for path in (MANAGER, HOST):
        parser.parse(path.read_text(encoding='utf-8'))
        print('GDScript static parse PASS: ' + str(path.relative_to(ROOT)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
