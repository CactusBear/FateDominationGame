"""源码结构/语法检查；不是 Godot 类型检查或行为验收。"""
from pathlib import Path
import json
import re
import sys
from gdtoolkit.parser import parser

ROOT = Path(__file__).resolve().parents[2]
FILES = [
    "scripts/system/global/fact_delivery.gd",
    "scripts/system/global/game_log.gd",
    "scripts/system/global/event_journal.gd",
    "scripts/system/global/effect_manager.gd",
    "tests/deferred_transaction_facts_test.gd",
]
texts = {name: (ROOT / name).read_text(encoding="utf-8") for name in FILES}
checks = []

def check(name, condition):
    checks.append({"name": name, "passed": bool(condition)})

def function(source, name):
    match = re.search(r"(?:static )?func " + re.escape(name) + r"\([^)]*\).*?(?=\n(?:static )?func |\Z)", source, re.S)
    if not match:
        raise AssertionError(f"missing function {name}")
    return match.group(0)

for name, text in texts.items():
    parser.parse(text)
    check("gdtoolkit parse: " + name, True)

log = texts[FILES[1]]
journal = texts[FILES[2]]
manager = texts[FILES[3]]
delivery = texts[FILES[0]]
tests = texts[FILES[4]]
observe = function(log, "observe_facts")
check("展示订阅不把消费者直接排入延迟信号", "CONNECT_DEFERRED" not in observe and "recorded.connect(enqueue)" in observe)
record = function(journal, "record")
check("规则事实仍立即保存与发信号", record.index("entries.append(stored)") < record.index("recorded.emit") and "deferred" not in record)
check("GameLog.record 仍直接返回即时规则事实", "return _journal.record({" in function(log, "record"))
check("建立根事务推进发布边界", "GameLog.begin_fact_transaction(checkpoint.transaction_id)" in function(manager, "_begin_guard_transaction"))
for name, owner in [("_settle_idle_guard_transactions", "owner"), ("_release_guard_transactions", "checkpoint")]:
    body = function(manager, name)
    check(name + " 审计成功后才 commit 展示", body.index('.audit("commit")') < body.index("GameLog.commit_fact_transaction(" + owner + ".transaction_id)"))
skip = function(manager, "skip_runtime_guard")
check("成功恢复后立即 abort，早于完成回执", skip.index("checkpoint.restore()") < skip.index("GameLog.abort_fact_transaction") < skip.index('checkpoint.audit("rollback",'))
check("两种会话清理入口均失效旧票据", "reset_fact_delivery()" in function(log, "reset") and "GameLog.reset_fact_delivery()" in function(manager, "reset_runtime"))
check("generation 单调增加而不在 reset 复用", "_next_generation += 1" in function(delivery, "begin") and "_next_generation" not in function(delivery, "reset"))
check("订阅重连使用独立身份", "_next_subscription += 1" in function(delivery, "observe") and "ticket.listeners[listener]" in function(delivery, "_drain"))
check("排队保存根 token 引用而非状态副本", '"dependencies":_transactions.values()' in delivery)
drain = function(delivery, "_drain")
check("旧 drain 在修改 scheduled 前拒绝", drain.index("session != _session_generation") < drain.index("_scheduled = false"))
check("票据先出队后调用，重入不会重复", drain.index("_pending.pop_front()") < drain.index("listener.call("))
check("票据/消费者/重入后均检查会话", drain.count("session != _session_generation") >= 3)
check("pending 不每帧自旋", "_schedule()" not in drain and "if blocked and not aborted:" in drain)
checkpoint = (ROOT / "scripts/match/effect_checkpoint.gd").read_text(encoding="utf-8")
check("发布原语不纳入规则检查点 statics", "_fact_delivery" not in checkpoint)
for name in ["same_frame_skip", "pending_answer_skip", "resume_commit_once", "generations_and_subscription", "reentrant_reset"]:
    check("专项源码覆盖 " + name, bool(function(tests, name)))
check("专项使用真实 skip/resume 与排队时点", "EffectManager.skip_runtime_guard()" in tests and "EffectManager.resume_runtime_guard()" in tests and "_queue_time_point_batch" in tests)
scene = (ROOT / "tests/deferred_transaction_facts_test.tscn").read_text(encoding="utf-8")
check("专项场景接线到测试源码", 'path="res://tests/deferred_transaction_facts_test.gd"' in scene)
result = {
    "kind": "source_static_only",
    "godot_started": False,
    "checks": len(checks),
    "failures": [row["name"] for row in checks if not row["passed"]],
    "results": checks,
    "not_verified": ["Godot 类型检查", "运行时同帧/跨帧信号行为", "真实恢复/连锁回归", "RED/GREEN"],
}
(ROOT / "scratch/deferred-transaction-facts/static-result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, ensure_ascii=False, indent=2))
sys.exit(1 if result["failures"] else 0)
