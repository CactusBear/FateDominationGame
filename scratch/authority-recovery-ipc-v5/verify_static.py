"""源码契约反例检查；不模拟规则，不启动 Godot，不读取凭证。"""
from pathlib import Path
import json
from gdtoolkit.parser import parser

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
PATHS = {
    'client': 'scripts/net/session/authority_host_client.gd',
    'worker': 'scripts/net/server/server_room_worker.gd',
    'ui': 'scripts/net/ui/lobby_screen.gd',
    'control': 'scripts/net/server/server_room_control.gd',
}
sources = {key: (ROOT / path).read_text(encoding='utf-8') for key, path in PATHS.items()}

def body(source, name):
    start = source.index('func ' + name + '(')
    end = source.find('\nfunc ', start + 1)
    return source[start:end if end >= 0 else None]

def client_blocked(text):
    code = body(text, 'restore_local_match')
    return 'return false' in code and 'return true' not in code and all(
        forbidden not in code for forbidden in ['write_json(', 'FileAccess.', '.restore_archive(', 'transport.close(', 'session.room.', 'await ']
    )

def startup_blocked(text):
    code = body(text, '_ready')
    guard = 'if has_recovery_state and _authority_host_mode in ["lan", "p2p"]:'
    return guard in code and '\n\t\treturn\n' in code[code.index(guard):code.index('_room_id = config.id')] and code.index(guard) < code.index('session.host(') < code.index('session.load_recovery_state(')

def automatic_blocked(text):
    code = body(text, '_try_restore_match')
    guard = 'if _authority_host_mode in ["lan", "p2p"]:'
    return guard in code and '\n\t\treturn\n' in code[code.index(guard):code.index('for player_id')] and code.index(guard) < code.index('_copy_recovery_tree(') < code.index('session.restore_local_match(')

def ui_blocked(text):
    code = body(text, '_restore_archive')
    guard = 'if session.authority_host != null:'
    return guard in code and '\n\t\treturn\n' in code[code.index(guard):code.index('if not await session.restore_local_match(')] and 'session.authority_host.restore_local_match(source)' in code

checks = {
    'client_restore_always_refuses_without_io_or_room_mutation': client_blocked(sources['client']),
    'worker_blocks_existing_lan_p2p_recovery_before_host_publish': startup_blocked(sources['worker']),
    'worker_blocks_auto_restore_before_scan_copy_and_replay': automatic_blocked(sources['worker']),
    'ui_routes_to_refusal_and_returns_before_shared_restore': ui_blocked(sources['ui']),
    'diagnostics_do_not_advertise_restore': '"archive_restore_available":false' in sources['client'],
    'management_whitelist_unchanged_no_restore_action': 'request.get("action") in ["save","seed","close","pause","resume"]' in sources['control'],
    'ordinary_network_disallows_arbitrary_server_management': 'begins_with("server_")' in sources['client'] and '直连房间不提供服务端管理入口' in sources['client'],
}
mutations = {
    'client_forged_success': not client_blocked(sources['client'].replace('return false\n\nfunc diagnostics', 'return true\n\nfunc diagnostics')),
    'worker_startup_bypass': not startup_blocked(sources['worker'].replace('if has_recovery_state and _authority_host_mode in ["lan", "p2p"]:', 'if false:')),
    'worker_auto_restore_bypass': not automatic_blocked(sources['worker'].replace('if _authority_host_mode in ["lan", "p2p"]:', 'if false:')),
    'ui_shared_restore_fallthrough': not ui_blocked(sources['ui'].replace('session.authority_host.restore_local_match(source)\n\t\tstatus.text = session.error\n\t\treturn', 'session.authority_host.restore_local_match(source)\n\t\tstatus.text = session.error')),
}
parses = {}
for key, text in sources.items():
    try:
        parser.parse(text)
        parses[PATHS[key]] = {'ok': True}
    except Exception as exc:
        parses[PATHS[key]] = {'ok': False, 'error': str(exc)}
result = {
    'scope': 'LAN/P2P安全阻断；非恢复IPC实现；非Godot运行验收',
    'checks': checks, 'negative_mutations_detected': mutations,
    'gdtoolkit_parse': parses,
    'check_count': len(checks), 'negative_count': len(mutations),
    'all_passed': all(checks.values()) and all(mutations.values()) and all(p['ok'] for p in parses.values()),
    'not_executed': ['Godot', 'runtime IPC', 'engine failure injection', 'credentials', 'git commit'],
}
(OUT / 'static-results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False, indent=2))
raise SystemExit(0 if result['all_passed'] else 1)
