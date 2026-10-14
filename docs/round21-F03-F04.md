# Round21 F03/F04 公开内核审计入口

## 结果与边界

接手时当前工作树已具备三个公开薄转发及四处生产消费者迁移。本代理实际新增 `tests/kernel_audit_public_api_test.gd/.tscn`，不重复修改既有生产代码；未修改 rule_state、net_ids、GameProgress、gate 或许可。不增加通用服务、不改规则及审计顺序。保留当前 E07d、seq/observer/cutoff、finished 和 restore batch 代码。

## 定义和调用追踪

- `scripts/system/global/effect_manager.gd:192`：`mark_guard_audit_failed(effect)` 单行转发 `_guard_audit_failed`。原方法只暂停 guard、设置 `audit_write_failed`、空 guard 时绑定 effect、返回 false；不提交事务、不恢复规则、不重新激活事实。
- 同文件 `:2712`：`effect_fact_actor_id` 转发既有 `_effect_fact_actor_id`；直接对象/WeakRef 解析沿用，事件/局势返回 -1，其他来源返回 trigger player。
- 同文件 `:2727`：`effect_source_name` 转发既有 `_effect_source_name`；null、失效弱引用、无 get_shown_name 返回空串。
- `scripts/match/match_replay.gd:37`：审计失败保留原 error 设置顺序后调用公开失败入口。
- `scripts/net/authority/match_authority.gd:56`：审计失败公开入口后清理旧视图，再拒绝原中文 reason。
- 同文件 `:302/:304`：真实 guard_diagnostic 用公开 actor/source；来源卡牌/根来源优先级未改变。
- 私有方法的剩余 EffectManager 内部调用保留，不扩大公开职责。

## 真实核验

引擎：`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`。
统一参数：`--headless --fixed-fps 60 --path . --scene res://tests/<name>_test.tscn`；kernel/audit_commit 另传 `-- C:/Users/Administrator/AppData/Local/hermes/cache/scratch/round21-F03-F04`。

| 专项 | 退出码 | 真实输出 |
|---|---:|---|
| kernel_audit_public_api（最终重跑） | 0 | RESULT kernel_audit_public_api checks=37 failures=[] |
| audit_commit | 0 | RESULT audit_commit checks=239 failures=[] |
| rule_guard_continuation | 0 | RESULT checks=12 failures=[] |
| net_server_recovery_guard | 0 | RESULT checks=12 failures=[] |
| net_runtime_guard | 超时 100s | 未取得 RESULT，不能验收 |
| match_replay | 超时（100s 初跑；30s 重跑） | 未取得 RESULT，不能验收 |

新增专项实际执行公开入口、真实 authority.guard_diagnostic、真实 Journal 文件容量写失败，以及 replay.restore/close 故障短链；覆盖暂停原因、已有 guard 不覆盖、原错误、审计 revision 不推进、玩家数据/展示事实不改、直接来源及弱引用事件/局势归属。没有完整成功恢复链/窗口验收证据。

夹具修正：from setter 自身弱持有对象，所以测试必须持有 WeakRef；max_records=0 表示不限量，审计头也占一条，使用容量 2 + start/commit（重复 start 会幂等去重，不能制造写失败）。独立 Replay 哈希探针首跑不稳定，最终改为直接验证玩家数据与 GameLog 事实不变；不据此宣称全 RuleState 哈希恒等。

## Gate 与精确许可交接

命令 `python tools/check_layer_deps.py`，最终退出码 0：

```
LAYER_GATE PASS findings=80 allowlist=80 new=0 stale=0 rules={'layer': 7, 'private': 73}
```

当前 gate 已无 F03/F04 四处生产许可，因此本代理没有待删 STALE 项，也没有改许可。若主代理需要对先前快照退休，精确旧锚点为：

1. private / scripts/match/match_replay.gd / EffectManager._guard_audit_failed / `EffectManager._guard_audit_failed(EffectManager.runtime_guard_effect())` / 1 次。
2. private / scripts/net/authority/match_authority.gd / EffectManager._guard_audit_failed / 同上锚点 / 1 次。
3. private / scripts/net/authority/match_authority.gd / EffectManager._effect_fact_actor_id / `var pid:int = EffectManager._effect_fact_actor_id(effect)` / 1 次。
4. private / scripts/net/authority/match_authority.gd / EffectManager._effect_source_name / `var source_name:String = source.get_shown_name() if source != null else EffectManager._effect_source_name(effect)` / 1 次。

仍存在的 command_spell_test 双重 _effect_source_name 许可不属本次生产调用迁移，不触碰。

日志目录：`C:/Users/Administrator/AppData/Local/hermes/cache/scratch/round21-F03-F04`（scratch 会闲置清理）。`git diff --check` 指定生产文件和新测试退出码 0。并发工作树持续变化，报告只归属本代理新增测试/本文档，不把其他代理修改冒称为本轮修改。
