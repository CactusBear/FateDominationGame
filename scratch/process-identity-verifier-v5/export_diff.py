"""Export only this agent's owned hunks, excluding sibling changes."""
from pathlib import Path
import difflib

ROOT = Path(__file__).resolve().parents[2]
manager_path = 'scripts/net/server/server_room_manager.gd'
host_path = 'scripts/net/session/authority_host_client.gd'
changes = {
    manager_path: [
        ('var process_identity_verifier:Callable\nconst PROCESS_OWNERSHIP_UNAVAILABLE:String = "原生工作进程所有权验证不可用；禁止启动、恢复或操作未验证的进程，原目录保留"\n\n## 当前扩展仅支持信号保护，未提供原子 spawn + 私有 OS 句柄生命周期。\n## 这是显式部署阻断，不可通过设置 Callable、ready 字符串或 PID 存活绕过。\n## 只有原生所有者接管 spawn/verify/exit/terminate/release 后才可开放此接口。\nfunc process_ownership_available() -> bool:\n\treturn false\n', 'var process_identity_verifier:Callable\n'),
        ('func process_identity_verified(binding:Dictionary) -> bool:\n\tif not process_ownership_available():\n\t\terror = PROCESS_OWNERSHIP_UNAVAILABLE\n\t\treturn false\n', 'func process_identity_verified(binding:Dictionary) -> bool:\n'),
        ('func create_room(name: String, settings: Dictionary, data_root: String) -> String:\n\terror = ""\n\tif not process_ownership_available():\n\t\terror = PROCESS_OWNERSHIP_UNAVAILABLE\n\t\treturn ""\n', 'func create_room(name: String, settings: Dictionary, data_root: String) -> String:\n\terror = ""\n'),
        ('func poll() -> void:\n\tif not process_ownership_available():\n\t\terror = PROCESS_OWNERSHIP_UNAVAILABLE\n\t\tfor room in rooms.values():\n\t\t\troom.ready = false\n\t\t\troom.error = PROCESS_OWNERSHIP_UNAVAILABLE\n\t\treturn\n', 'func poll() -> void:\n'),
        ('func recover_room(id:String, expected_pid:int = -2, expected_instance_id:String = "") -> bool:\n\terror = ""\n\tif not process_ownership_available():\n\t\terror = PROCESS_OWNERSHIP_UNAVAILABLE\n\t\treturn false\n', 'func recover_room(id:String, expected_pid:int = -2, expected_instance_id:String = "") -> bool:\n\terror = ""\n'),
        ('\tvar pid: int = rooms[id].pid\n\tif pid > 0 and not process_ownership_available():\n\t\terror = PROCESS_OWNERSHIP_UNAVAILABLE\n\t\treturn false\n', '\tvar pid: int = rooms[id].pid\n'),
        ('\tif what == NOTIFICATION_PREDELETE:\n\t\tif not process_ownership_available(): return\n', '\tif what == NOTIFICATION_PREDELETE:\n'),
    ],
    host_path: [
        ('\t# 不开启注定无法完成 OS 所有权验证的监听，也不接管外部 P2P peer。\n\tif not gateway.manager.process_ownership_available():\n\t\terror = gateway.manager.PROCESS_OWNERSHIP_UNAVAILABLE\n\t\treturn ERR_UNAVAILABLE\n', ''),
    ],
}
patch = []
for relative, pairs in changes.items():
    current = (ROOT / relative).read_text(encoding='utf-8')
    before = current
    for added, old in pairs:
        assert before.count(added) == 1, relative
        before = before.replace(added, old, 1)
    patch.extend(difflib.unified_diff(before.splitlines(keepends=True), current.splitlines(keepends=True), fromfile='a/' + relative, tofile='b/' + relative))
output = Path(__file__).parent / 'production.diff'
output.write_text(''.join(patch), encoding='utf-8', newline='\n')
print(str(output))
