"""静态源码契约，不执行或替代 Godot 规则；变异仅在内存。"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
PATHS = {
    "guard": "scripts/net/recovery_path_safety.gd",
    "manager": "scripts/net/server_room_manager.gd",
    "worker": "scripts/net/server_room_worker.gd",
    "suite": "tests/recovery_path_safety_test.gd",
}
source = {key: (ROOT / path).read_text(encoding="utf-8") for key, path in PATHS.items()}


def contracts(s):
    guard, manager, worker = s["guard"], s["manager"], s["worker"]
    recovery = manager.split("func recover_room(", 1)[1].split("func _write_supervisor", 1)[0]
    ready = worker.split("func _ready()", 1)[1].split("func _process", 1)[0]
    checks = {
        "拒绝点段": 'part in [".", ".."]' in guard,
        "设备名和ADS": '"CONIN$"' in guard and '"123456789¹²³"' in guard and 'character in "/\\\\:<>' in guard,
        "完整目录段比较": 'b.begins_with(a.trim_suffix("/") + "/")' in guard,
        "检查所有祖先链接": 'directory.is_link(current.get_file())' in guard,
        "包括隐藏目录": "dir.include_hidden = true" in guard,
        "不使用simplify洗白": "simplify_path" not in guard,
        "恢复写配置前授权": recovery.index("_safe_recovery_config") < recovery.index("write_configuration"),
        "批准根不来自配置": 'RecoveryPaths.checked(arguments[1], config.data_root)' in ready,
        "配置读取前边界": ready.index("RecoveryPaths.checked(arguments[2], arguments[0])") < ready.index("JSON.parse_string"),
        "固定副本树检查": 'RecoveryPaths.tree(_directory, isolated, [20000])' in ready,
        "store之前pin": "cache.pin(" in ready and ready.index("cache.pin(") < ready.index("cache.store("),
        "加载发布后释放": ready.index("_release_startup_pins()") > ready.index("session.publish_blob("),
        "失败退出释放": "push_error(reason)\n\t_release_startup_pins()" in worker and "func _exit_tree() -> void:\n\t_release_startup_pins()" in worker,
        "恢复根限房间": 'RecoveryPaths.same(session.archive_root, _directory.path_join("matches"))' in worker,
        "恢复副本而非原档": "await session.restore_local_match(snapshot)" in worker and "await session.restore_local_match(source)" not in worker,
        "复制预算": "recovery_copy_max_bytes - budget[1]" in worker and "depth > 128" in worker,
    }
    return [name for name, good in checks.items() if not good], len(checks)


failures, count = contracts(source)
mutations = {
    "删除数据根检查": ("worker", "RecoveryPaths.checked(arguments[1], config.data_root)", "true"),
    "删除祖先链接检查": ("guard", "directory.is_link(current.get_file())", "false"),
    "删除pin": ("worker", "cache.pin(", "cache.fetch("),
    "使用原档恢复": ("worker", "await session.restore_local_match(snapshot)", "await session.restore_local_match(source)"),
}
results = {}
for name, (key, old, new) in mutations.items():
    changed = dict(source)
    assert old in changed[key], name
    changed[key] = changed[key].replace(old, new, 1)
    bad, _ = contracts(changed)
    results[name] = bool(bad)
assert not failures, failures
assert all(results.values()), results
print(json.dumps({"static_contract_checks": count, "failures": failures, "in_memory_mutants_rejected": results, "Godot_executed": False}, ensure_ascii=False, indent=2))
