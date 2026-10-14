# Round47：三个旧编辑器 fixture 合同修复

## 修改与边界

只修改 `tests/acceptance_root_transaction_test.gd`、`tests/net_server_linux_paused_recovery_test.gd`、`tests/ui_refresh_cost_board.gd`；新增 `tests/round47_editor_fixture_parse_test.gd/.tscn` 与本说明。生产脚本、父 fixture、gate 和 baseline 不改；未操作主编辑器窗口、未清 MCP 历史错误。

- acceptance：父 `rule_guard_chain_rollback_test.gd` 已把规则回调迁至 `rule_guard_continuation_fixture.gd` 的 RefCounted Actor，旧 `super.change_parent/change_child` 及裸 `choices/outside/ask_other` 不存在。继续使用父 reset 登记的同一 Actor/child，用独立 `AcceptanceActions` 组合真实 `change_parent/change_child` 和牌区、RNG、GameLog 副作用。不能 reset 后替换 Actor：原 child 已登记在 `GameData.effects`，会留下指向旧 Actor 的失效 Callable。原 17 个 CHECK 全保留，另加观察器不可回滚断言，共 18；检查计数和失败列表始终留在测试 Node，不被规则 Callable 引回检查点。
- acceptance 私有观察改用现有 `runtime_guard_effect/runtime_guard_root_effect`、`paused_runs_snapshot`、`capture_transaction_state().continuation_queue`。没有新增生产访问口。
- Linux 恢复：实际父合同是 `_recover_match(Variant, Variant) -> bool`。恢复覆盖保留未限定的两个参数并返回 bool；pause 拒绝、父恢复失败、恢复后未保持暂停、暂停期间局面变化、resume 拒绝均失败短路，不把失败当成功继续续局。
- UI：实际父合同 `_held_card_playable(card, _actions = null, group = null) -> bool`；计数夹具逐一原样透传三个参数，仍执行父合法性判定。确认计数仍调用父安全判定。新专项覆盖显式合法组合、未知候选、空朝向、已选整组合法/非法、一参数默认拒绝、调用计数及源码参数透传。

## RED → GREEN 真实执行

独占证据根：

`E:/HermesScratch/round47-editor-fixtures-7dbe3aae52f84364ba403d56470ff312/`

主要证据：`manifest.json`、`current3-negative-results.json`、`evidence/*.stdout.log/*.stderr.log`。`red-parse` 用真实 Godot 复现原三个 parse 根因，exit 1、RESULT checks=3，三个 compile 检查均 false。后续失败诊断与并行依赖缺失日志保留，没有覆写或清空旧错误求 green。

同一 current3 冻结版本的最终专项如下，全部 exit 0、唯一合法 RESULT、空 failures，无 SCRIPT ERROR/ERROR：

| 日志前缀 | 实际场景 | RESULT checks |
|---|---|---:|
| current3-parse | round47_editor_fixture_parse_test | 14 |
| current3-acceptance | acceptance_root_transaction_test | 18 |
| current3-ui-refresh | ui_refresh_cost_test | 25 |
| current3-chain | rule_guard_chain_rollback_test | 17 |
| current3-held-actions | refactor_held_actions_test | 43 |

`current3-editor-import` 的真实独占 headless 编辑器扫描 exit 0、无错误；加载专项进一步对三个目标逐一执行 `load` / `can_instantiate`，而非只凭 import 退出码推断脚本无 parseError。负向恢复后 `current3-postnegative-parse` 再次 14 checks / exit 0。

真实运行参数（完整绝对命令与 PID 在 manifest）：

```text
<独占E盘Godot.exe> --headless --rendering-method gl_compatibility --audio-driver Dummy --fixed-fps 60 --path <独占generated/project> --scene res://tests/<scene>.tscn
<独占E盘Godot.exe> --headless --rendering-method gl_compatibility --audio-driver Dummy --editor --import --path <独占generated/project>
```

独占引擎为原 D 盘主 EXE 的逐字节 SHA-256 一致副本，不改引擎；不把 console wrapper 改名冒充主程序。独占项目仅关闭 VCS 自动启动与编辑器插件，记录配置变换 SHA；保留原应用 user-dir 和 worker_pool/max_threads=20。APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 仅在子进程环境指向自有物理 E 子树；真实主/派生探针分别报告不同 PID、实际 user://、pool=20，token/JSON 落盘读回验证。每进程 180 秒看门狗，Windows Job Object 挂起分配后恢复，仅回收自有句柄，全部 ActiveProcesses=0；不按进程名清扫。运行顺序串行，不把并行负载下的 COST 数字当性能门。

## 负向检出（同 current3 冻结，仅改自有 fixture 副本）

五个反例全部被拒绝，exit 1；每次恢复原字节并核对 SHA，未改生产脚本：

1. 省略父动作弃牌副作用：原副作用 CHECK 失败。
2. 省略真实 `skip_runtime_guard()`：原父子资源、牌序、RNG、规则事实、等待/尾部及重复跳过断言检出，不能只删断言制造通过。
3. 在真实回滚前注入一个失败 CHECK：回滚后 RESULT checks=19，仍保留唯一注入 failure，新增观察器断言为 true；证明失败证据不会被规则恢复吞掉。
4. UI 保持三参数声明但转发只传 card：编译仍成功，显式 group 合法候选、已选整组与源码透传三个断言失败。
5. Linux 返回类型退回 void：真实 Godot 父合同 parseError，目标 compile 检查失败。

## 平台、性能与版本限制

- Linux 暂停崩溃恢复运行时未执行，本机结果仅 **script compile validated + 父合同反射验证**，不得标 Linux passed。没有伪造 Linux pause/save/resume 回执或运行数据。
- UI 原行为/查询计数专项真实通过；COST 仅观测值，不宣称性能提升、性能门或窗口输入验收。
- 并行生产修改曾增加 `server_data_status_inbox.gd`，第一次当前源码同步未包含新文件，合法 RESULT 仍因依赖编译错误被严格判 RED；保留 `current-*` 日志。扩充原显式 scripts 依赖集后 current3 全部通过，执行期间源码指纹漂移为空。不能把更早冻结的 PASS 拼接成当前整合或发行 PASS。
- current3 完成后，清理时发现并行写入者又修改 `scripts/net/session/lobby_session.gd`；已记录 `current_source_drift_at_cleanup`，所以交付的是 current3 精确冻结证据，不宣称清理时最新全树整合通过。main 合并完成后需重跑最终整合。
- 测试路径部分受 git ignore；`git status`/`git diff` 不能单独证明这些改动是否存在，交接以文件内容与 SHA 清单为准。

收尾已核对 46 条自有进程记录均退出、Job ActiveProcesses=0、日志句柄释放。仅删除自有 `generated`（898399933 bytes）；保留所有历史/最终日志、manifest、负向结果、真实主/worker落盘回执和 `evidence/verified-fixtures` 精确源码。正式工程、正式存档及其他代理的根均未清理。

## 交 main 的私有许可退休锚点（本代理未改 gate）

`tools/check_layer_deps.py` 中该 acceptance 文件的五处旧 ExceptionSite 应由 gate 唯一写入者退休：

1. `EffectManager._guard_continuations`，原 queues 同行（旧 line 35）。
2. `EffectManager._paused_runs`，原 queues 同行（旧 line 35）。
3. `EffectManager._guard_transactions`，原 `get(answer).root == parent`（旧 line 49）。
4. `EffectManager._paused_runs`，原恢复队列断言（旧 line 57）。
5. `EffectManager._guard_continuations`，原尾部/outside 断言（旧 line 58）。

替代均为现有公开观察，无新私有许可。不得扩大其他 fixture 例外或改 baseline 求通过。
