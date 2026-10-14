# Round50 guard 测试公开观察接线

## 交付边界

仅改三套指定测试，新增 `tests/round50_guard_observer.gd`；不改内核、EffectManager、GameProgress、RuleState、Replay、currentparent 或 gate。
本范围原 14 个精确许可剩 3 个：11 个已从实际源码消失，下面列出完整原始 exact anchors，交主代理从 ALLOWLIST 退休；同一行批次观察有两个不同 target，必须分别退休。没有字符串反射、隐藏私有读取或新增生产 getter。

## 真实闭包及身份契约

- `capture_transaction_state` 观察原根检查点身份；清空外层快照不影响真实绑定，`restore_transaction_state` 还原保持原检查点，非法批次容器拒绝且不部分清空归属。
- 手动根仍保留原两步支付停点，并额外实跑四步分支：真实扣费/移牌/生成批次。核对批次原对象、事务、来源及 event_player_id；回滚后批次归属空，公开 time_point_id 未推进，再调用公开 `run_pipeline(true)` 也不派发被撤销批次或消耗资源。
- 原 QueueOptional 独立待答链保留；另接公开 `request_choice` 真父暂停链。公开暂停快照验证父执行记录原身份及外层隔离；答复预算暂停时 guard 当前效果=原答复、root=原父效果、回调已退出后 active root=null。回滚撤销父尾部，原玩家资源、牌区引用和审计 root/parent/effect/player/card 元数据完整。
- 尾部规则动作仍是独立 RefCounted，但不可撤销计数迁入独立脚本静态 observer，动作不引用断言 Node。相等 Callable 对应独立原票据、内部票据归属于原事务；只消费两张外部票据，审计逐票次数=1、root_id=0；重复 skip 不重放。
- audit_commit 真 append/flush 故障、commit 失败未 settled 且持续持有原事务全部保留；故障后公开 resume/skip 拒绝且不清洗事务。每条 check 新增真实 CHECK 输出，和 RESULT 数量一致。
- rollback 保留原资源/牌区对象身份、随机及规则日志恢复、内尾部不执行、外尾部一次等断言；自然 end_session 后公开事务、暂停续行、尾部及批次为空。

## 验证

证据独占根：`E:/Caches/Hermes/cache/scratch/round50-guard-947793a0e00b4f28a3c5e00a321f7bf9/`。
入口脚本：`E:/Caches/Hermes/cache/scratch/round50_guard_verify.py`、`round50_guard_resume.py`、`round50_guard_mutations.py`、`round50_guard_current.py`。
真实 Godot 4.7.2 已复制到该根的 `generated/Godot.exe`。共享执行原语为现有 `tools/run_isolated_godot_test.py.execute`；每进程 180 秒、2,000,000,000 字节、剩余至少 500,000,000 字节，Windows Job 只管理自有 PID。真实主/worker user:// 物理 E 探针通过，不改全局 TEMP，不启动 GUI。

最终命令形状（精确 argv/PID 在 `report.json.process_tail`）：
```text
generated/Godot.exe --headless --fixed-fps 60 --path generated/project --scene res://tests/audit_commit_test.tscn -- <独占E输出根>
generated/Godot.exe --headless --fixed-fps 60 --path generated/project --scene res://tests/rule_guard_root_transaction_v2_test.tscn
generated/Godot.exe --headless --fixed-fps 60 --path generated/project --scene res://tests/rule_guard_rollback_test.tscn
```

| 最终日志前缀 | checks（真实 CHECK/RESULT 一致） | exit | failures |
|---|---:|---:|---|
| current-green-audit_commit | 243 | 0 | [] |
| current-green-rule_guard_root_transaction_v2 | 115 | 0 | [] |
| current-green-rule_guard_rollback | 19 | 0 | [] |

三套 stderr 空、无 ERROR/SCRIPT ERROR、唯一合法 RESULT、自然退出、Job active_owned_processes=0、句柄释放。原始 stdout/stderr 和 SHA256 在 evidence/report.json；最终刷新其他并行写入者的 3 个变化文件仅在冻结副本中进行，最终 source_drift=[]。未跑长 replay 或全 70。

冻结副本真实 RED mutation（每次 finally 恢复原字节并核验 SHA256）：

| 变异 | 实际检出 | exit |
|---|---|---:|
| 回滚前插入失败断言 | RESULT 保留失败，20 条 CHECK 一致，未被回滚吞 | 1 |
| 规则恢复后错误保留待派发批次 | 两个手动停点的批次清空/再次排空管线断言均检出，115 CHECK 一致 | 1 |
| commit 写失败错误置 settled=true | 未 settled/故障管理后仍未提交断言检出，243 CHECK 一致 | 1 |
| 内部尾部归属错误变外部 | 原事务归属、尾部次数、审计及重复 skip 检出，113 CHECK 一致 | 1 |

所有 RED 均 stderr 空、无 ERROR，失败来自真实断言，不是语法或超时。恢复后再实跑三套 GREEN；当前源码刷新后又实跑三套 GREEN。

首次冻结导入因漏 native DLL/shader include 及冷导入 cursor 尚未导入出现错误；未把该阶段算通过。补真实依赖后 `import-complete` exit0、无 ERROR。中间新增暂停观察也曾真实失败：独立排队答复无父续行；新增真 request_choice 链解决，不放宽原链断言。新选择在 register_effect 之前显式声明 player_id，避免其注册时 child 审计仍为 -1。历史完整探针/导入错误日志保留，不用于最终 PASS。

## 交主代理退休：完整 exact anchors

### 1. tests/audit_commit_test.gd — EffectManager._guard_transactions

旧证据行 `107`；rule=`private`，次数=1。
```gdscript
var checkpoint = EffectManager._guard_transactions.get(root)
```

### 2. tests/audit_commit_test.gd — EffectManager._guard_transactions

旧证据行 `111`；rule=`private`，次数=1。
```gdscript
check(EffectManager._guard_transactions.has(root), "失败保留事务归属")
```

### 3. tests/rule_guard_rollback_test.gd — EffectManager._guard_transactions

旧证据行 `51`；rule=`private`，次数=1。
```gdscript
print("CHECKPOINT_ERROR ", EffectManager._guard_transactions.get(effect).error)
```

### 4. tests/rule_guard_rollback_test.gd — EffectManager._guard_transactions

旧证据行 `66`；rule=`private`，次数=1。
```gdscript
check(EffectManager._guard_transactions.is_empty(), "退出清除事务检查点")
```

### 5. tests/rule_guard_root_transaction_v2_test.gd — EffectManager._guard_transactions

旧证据行 `90`；rule=`private`，次数=1。
```gdscript
check(EffectManager._guard_transactions.has(effect), "检查点在选择及支付之前存在")
```

### 6. tests/rule_guard_root_transaction_v2_test.gd — EffectManager._guard_transactions

旧证据行 `95`；rule=`private`，次数=1。
```gdscript
var checkpoint = EffectManager._guard_transactions.get(effect)
```

### 7. tests/rule_guard_root_transaction_v2_test.gd — EffectManager._batch_transactions

旧证据行 `105`；rule=`private`，次数=1。
```gdscript
check(EffectManager._queued_time_point_batches.is_empty() and EffectManager._batch_transactions.is_empty(), "事务排队时点和归属清空")
```

### 8. tests/rule_guard_root_transaction_v2_test.gd — EffectManager._queued_time_point_batches

旧证据行 `105`；rule=`private`，次数=1。
```gdscript
check(EffectManager._queued_time_point_batches.is_empty() and EffectManager._batch_transactions.is_empty(), "事务排队时点和归属清空")
```

### 9. tests/rule_guard_root_transaction_v2_test.gd — EffectManager._guard_transactions

旧证据行 `128`；rule=`private`，次数=1。
```gdscript
var root = EffectManager._guard_transactions.get(answer)
```

### 10. tests/rule_guard_root_transaction_v2_test.gd — EffectManager._paused_runs

旧证据行 `135`；rule=`private`，次数=1。
```gdscript
check(EffectManager._paused_runs.is_empty() and not EffectManager.effect_pool.has(answer), "新建答复及父续行引用撤销")
```

### 11. tests/rule_guard_root_transaction_v2_test.gd — EffectManager._guard_continuations

旧证据行 `150`；rule=`private`，次数=1。
```gdscript
check(EffectManager._guard_continuations.size() == 2, "相等内部 Callable 两次独立登记")
```

## 明确保留的 3 个 fault-injection 许可

- `tests/audit_commit_test.gd` / `EffectManager._begin_guard_transaction`，旧证据行 `106`：
```gdscript
check(EffectManager._begin_guard_transaction(root), "真实根事务 start")
```
- `tests/audit_commit_test.gd` / `EffectManager._release_guard_transactions`，旧证据行 `109`：
```gdscript
EffectManager._release_guard_transactions()
```
- `tests/rule_guard_root_transaction_v2_test.gd` / `EffectManager._queue_time_point_batch`，旧证据行 `21`：
```gdscript
if queue_batch: EffectManager._queue_time_point_batch(EffectManager.activating_eff, player_id)
```

`_begin_guard_transaction` / `_release_guard_transactions` 保留：本夹具必须在根 start 成功后、commit 之前通过真实 writer 容量触发 commit append 写失败，单次公开 activate/pipeline 会把这两个阶段连在一起自动提交；不为测试新增生产入口，也不把故障降成普通前置拒绝。事务观察部分已全部用公开 capture/root API 替换。

`_queue_time_point_batch` 保留：精确入队暂停中的待派发批次属合法注入职责，暂无等价的公开精确入队接口；原位置及 code anchor 保持不变。观察部分已用公开批次令牌和真实管线行为替换，并实跑非空批次及故障变异。

当前全树 gate 只读实跑有 0 NEW，本范围 11 个 STALE；还存在另一写入者的 layer STALE（room_validation_task 的场景路径），不纳入本范围退休，也不宣称当前主工程 gate PASS。主代理退休以上 11 项后应重新跑全树 gate 与其单测；本代理无 gate 写权。
